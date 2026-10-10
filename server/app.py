#!/usr/bin/env python3
"""yslem Key API + execution dashboard (stdlib only, SQLite).

- POST /v1/verify          contrat docs/KEY_API.md (key, robloxUserId, script, v) -> {"status", "expiresAt"}
- GET  /                   dashboard (page vide : les donnees exigent le jeton admin)
- GET  /admin/api/...      evenements, stats, cles (Authorization: Bearer <ADMIN_TOKEN>)

Chaque appel a /v1/verify est une execution (ou une tentative) : on enregistre l'heure, le UserId, le script,
le jeu (deduit du nom du script via scripts.json), le statut et une empreinte de cle. Jamais la cle en clair,
jamais l'IP en clair (HMAC tronque). Rien d'autre n'est envoye par le client.

Variables d'environnement : ADMIN_TOKEN (sinon genere et affiche une fois), SALT (sinon fichier .salt local),
DB_PATH (defaut yslem_api.db), HOST, PORT, RESOLVE_NAMES=1 (nom Roblox via users.roblox.com, cache).
"""
import argparse, base64, hashlib, hmac, json, os, secrets, sqlite3, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
KEY_PREFIX = "YSL-"
MAX_BODY = 2048
RATE_IP = (60, 60)      # 60 requetes / 60 s / IP
RATE_KEY = (20, 60)     # 20 requetes / 60 s / empreinte de cle
STATUSES = ("valid", "invalid", "expired", "revoked", "banned")


def load_salt():
    env = os.environ.get("SALT")
    if env:
        return env.encode()
    path = os.path.join(os.path.dirname(os.environ.get("DB_PATH", os.path.join(HERE, "yslem_api.db"))) or HERE, ".salt")
    if os.path.exists(path):
        return open(path, "rb").read()
    salt = secrets.token_bytes(32)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(salt)
    return salt


class Store:
    def __init__(self, path, salt):
        self.salt = salt
        self.lock = threading.Lock()
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.executescript("""
        CREATE TABLE IF NOT EXISTS keys(
            fp TEXT PRIMARY KEY, hash TEXT UNIQUE NOT NULL, user_id INTEGER NOT NULL,
            expires INTEGER NOT NULL, state TEXT NOT NULL DEFAULT 'active', note TEXT DEFAULT '', created INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS events(
            id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, user_id INTEGER, script TEXT, game TEXT,
            v INTEGER, status TEXT NOT NULL, fp TEXT, ip TEXT, owner_id INTEGER);
        CREATE INDEX IF NOT EXISTS ev_ts ON events(ts);
        CREATE INDEX IF NOT EXISTS ev_user ON events(user_id);
        CREATE TABLE IF NOT EXISTS names(user_id INTEGER PRIMARY KEY, name TEXT, ts INTEGER);
        """)
        self.db.commit()

    def h(self, text):
        return hmac.new(self.salt, text.encode(), hashlib.sha256).hexdigest()

    # ---- keys
    def new_key(self, user_id, days, note=""):
        key = KEY_PREFIX + base64.urlsafe_b64encode(secrets.token_bytes(24)).decode().rstrip("=")
        hh = self.h(key)
        now = int(time.time())
        with self.lock:
            self.db.execute("INSERT INTO keys(fp,hash,user_id,expires,state,note,created) VALUES(?,?,?,?,?,?,?)",
                            (hh[:10], hh, int(user_id), now + int(days) * 86400, "active", note[:80], now))
            self.db.commit()
        return key, hh[:10]

    def set_state(self, fp, state):
        with self.lock:
            cur = self.db.execute("UPDATE keys SET state=? WHERE fp=?", (state, fp))
            self.db.commit()
            return cur.rowcount > 0

    def list_keys(self):
        with self.lock:
            rows = self.db.execute("""SELECT k.fp,k.user_id,k.expires,k.state,k.note,k.created,
                (SELECT MAX(ts) FROM events e WHERE e.fp=k.fp) AS last_seen,
                (SELECT COUNT(*) FROM events e WHERE e.fp=k.fp) AS uses
                FROM keys k ORDER BY k.created DESC""").fetchall()
        return [dict(r) for r in rows]

    # ---- verification
    def verify(self, key, user_id):
        hh = self.h(key)
        with self.lock:
            row = self.db.execute("SELECT * FROM keys WHERE hash=?", (hh,)).fetchone()
        if row is None or row["user_id"] != user_id:
            return "invalid", None, hh[:10], (row["user_id"] if row else None)
        if row["state"] == "banned":
            return "banned", None, hh[:10], row["user_id"]
        if row["state"] == "revoked":
            return "revoked", None, hh[:10], row["user_id"]
        if row["expires"] <= time.time():
            return "expired", None, hh[:10], row["user_id"]
        return "valid", row["expires"], hh[:10], row["user_id"]

    def log(self, user_id, script, game, v, status, fp, ip, owner_id=None):
        with self.lock:
            self.db.execute("INSERT INTO events(ts,user_id,script,game,v,status,fp,ip,owner_id) VALUES(?,?,?,?,?,?,?,?,?)",
                            (int(time.time()), user_id, script, game, v, status, fp, ip, owner_id))
            self.db.commit()

    # ---- dashboard queries
    def events(self, limit=100, before=None, script=None, status=None, user=None, game=None):
        q, args = "SELECT e.*, n.name AS name FROM events e LEFT JOIN names n ON n.user_id=e.user_id WHERE 1=1", []
        if before:
            q += " AND e.id<?"; args.append(int(before))
        if script:
            q += " AND e.script=?"; args.append(script)
        if game:
            q += " AND e.game=?"; args.append(game)
        if status:
            q += " AND e.status=?"; args.append(status)
        if user:
            q += " AND (e.user_id=? OR n.name LIKE ?)"; args.extend([int(user) if str(user).isdigit() else -1, "%" + str(user) + "%"])
        q += " ORDER BY e.id DESC LIMIT ?"; args.append(max(1, min(int(limit), 500)))
        with self.lock:
            rows = self.db.execute(q, args).fetchall()
        return [dict(r) for r in rows]

    def stats(self):
        now = int(time.time())
        out = {}
        with self.lock:
            c = self.db.cursor()
            for label, span in (("h1", 3600), ("h24", 86400), ("d7", 7 * 86400)):
                r = c.execute("SELECT COUNT(*) n, COUNT(DISTINCT user_id) u, SUM(status!='valid') bad FROM events WHERE ts>?", (now - span,)).fetchone()
                out[label] = {"executions": r["n"], "players": r["u"], "failed": r["bad"] or 0}
            out["online"] = c.execute("SELECT COUNT(DISTINCT user_id) FROM events WHERE status='valid' AND ts>?", (now - 20 * 60,)).fetchone()[0]
            out["byGame"] = [dict(r) for r in c.execute(
                "SELECT COALESCE(game,'?') game, COUNT(*) n, COUNT(DISTINCT user_id) players FROM events WHERE ts>? GROUP BY game ORDER BY n DESC", (now - 7 * 86400,))]
            out["byScript"] = [dict(r) for r in c.execute(
                "SELECT COALESCE(script,'?') script, COUNT(*) n FROM events WHERE ts>? GROUP BY script ORDER BY n DESC", (now - 7 * 86400,))]
            out["byStatus"] = [dict(r) for r in c.execute(
                "SELECT status, COUNT(*) n FROM events WHERE ts>? GROUP BY status", (now - 7 * 86400,))]
            hours = [now - (23 - i) * 3600 for i in range(24)]
            out["hourly"] = [c.execute("SELECT COUNT(*) FROM events WHERE ts>=? AND ts<?", (t - t % 3600, t - t % 3600 + 3600)).fetchone()[0] for t in hours]
            out["suspects"] = [dict(r) for r in c.execute(
                """SELECT user_id, COUNT(*) n, MAX(ts) last FROM events WHERE status!='valid' AND ts>? AND user_id IS NOT NULL
                   GROUP BY user_id HAVING n>=3 ORDER BY n DESC LIMIT 10""", (now - 86400,))]
        return out

    def player(self, user_id):
        with self.lock:
            rows = self.db.execute("SELECT * FROM events WHERE user_id=? ORDER BY id DESC LIMIT 200", (user_id,)).fetchall()
            keys = self.db.execute("SELECT fp,expires,state,note,created FROM keys WHERE user_id=?", (user_id,)).fetchall()
            name = self.db.execute("SELECT name FROM names WHERE user_id=?", (user_id,)).fetchone()
        return {"userId": user_id, "name": name["name"] if name else None, "events": [dict(r) for r in rows], "keys": [dict(r) for r in keys]}

    def cache_name(self, user_id, name):
        with self.lock:
            self.db.execute("INSERT OR REPLACE INTO names(user_id,name,ts) VALUES(?,?,?)", (user_id, name, int(time.time())))
            self.db.commit()

    def has_name(self, user_id):
        with self.lock:
            return self.db.execute("SELECT 1 FROM names WHERE user_id=?", (user_id,)).fetchone() is not None


class Limiter:
    def __init__(self):
        self.hits, self.lock = {}, threading.Lock()

    def allow(self, bucket, rule):
        limit, span = rule
        now = time.time()
        with self.lock:
            lst = [t for t in self.hits.get(bucket, ()) if now - t < span]
            if len(lst) >= limit:
                self.hits[bucket] = lst
                return False
            lst.append(now)
            self.hits[bucket] = lst
            if len(self.hits) > 20000:
                self.hits = {k: v for k, v in self.hits.items() if v and now - v[-1] < span}
        return True


def resolve_name(store, user_id):
    """Optionnel (RESOLVE_NAMES=1) : une requete serveur -> users.roblox.com, resultat mis en cache."""
    try:
        import urllib.request
        with urllib.request.urlopen("https://users.roblox.com/v1/users/%d" % user_id, timeout=4) as r:
            data = json.loads(r.read().decode())
        if isinstance(data.get("name"), str):
            store.cache_name(user_id, data["name"][:40])
    except Exception:
        pass


def make_handler(store, scripts, admin_token, limiter, resolve):
    page = open(os.path.join(HERE, "static", "dashboard.html"), "rb").read()

    class H(BaseHTTPRequestHandler):
        server_version = "yslem"
        sys_version = ""

        def log_message(self, *a):
            pass

        def client_ip(self):
            fwd = self.headers.get("X-Forwarded-For")
            ip = fwd.split(",")[-1].strip() if fwd and os.environ.get("TRUST_PROXY") == "1" else self.client_address[0]
            return ip

        def send(self, code, body=b"", ctype="application/json", extra=None):
            if isinstance(body, (dict, list)):
                body = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            if ctype.startswith("text/html"):
                self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:")
                self.send_header("X-Frame-Options", "DENY")
            for k, v in (extra or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)

        def body_json(self):
            try:
                n = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                return None
            if n <= 0 or n > MAX_BODY:
                return None
            try:
                data = json.loads(self.rfile.read(n).decode())
            except Exception:
                return None
            return data if isinstance(data, dict) else None

        def authed(self):
            tok = self.headers.get("Authorization", "")
            tok = tok[7:] if tok.startswith("Bearer ") else ""
            ok = hmac.compare_digest(tok.encode(), admin_token.encode())
            if not ok:
                time.sleep(0.4)
                self.send(401, {"error": "unauthorized"})
            return ok

        # ---------------------------------------------------------- routes
        def do_GET(self):
            u = urlparse(self.path)
            if u.path in ("/", "/index.html"):
                return self.send(200, page, "text/html; charset=utf-8")
            if u.path == "/healthz":
                return self.send(200, {"ok": True})
            if not u.path.startswith("/admin/api/"):
                return self.send(404, {"error": "not found"})
            if not self.authed():
                return
            q = {k: v[0] for k, v in parse_qs(u.query).items()}
            try:
                if u.path == "/admin/api/events":
                    return self.send(200, {"events": store.events(q.get("limit", 100), q.get("before"), q.get("script"), q.get("status"), q.get("user"), q.get("game"))})
                if u.path == "/admin/api/stats":
                    return self.send(200, store.stats())
                if u.path == "/admin/api/keys":
                    return self.send(200, {"keys": store.list_keys()})
                if u.path == "/admin/api/player":
                    return self.send(200, store.player(int(q.get("id", "0"))))
                if u.path == "/admin/api/scripts":
                    return self.send(200, {"scripts": scripts})
            except (ValueError, sqlite3.Error):
                return self.send(400, {"error": "bad request"})
            self.send(404, {"error": "not found"})

        def do_POST(self):
            u = urlparse(self.path)
            if u.path == "/v1/verify":
                return self.verify()
            if not u.path.startswith("/admin/api/"):
                return self.send(404, {"error": "not found"})
            if not self.authed():
                return
            data = self.body_json()
            if data is None:
                return self.send(400, {"error": "bad request"})
            if u.path == "/admin/api/keys":
                uid, days = data.get("robloxUserId"), data.get("days", 30)
                if not isinstance(uid, int) or isinstance(uid, bool) or uid <= 0 or not isinstance(days, int) or not 1 <= days <= 3650:
                    return self.send(400, {"error": "robloxUserId (int) and days (1-3650) required"})
                key, fp = store.new_key(uid, days, str(data.get("note", "")))
                return self.send(200, {"key": key, "fp": fp, "note": "shown once"})
            if u.path in ("/admin/api/keys/revoke", "/admin/api/keys/ban", "/admin/api/keys/restore"):
                state = {"revoke": "revoked", "ban": "banned", "restore": "active"}[u.path.rsplit("/", 1)[1]]
                fp = data.get("fp")
                if not isinstance(fp, str) or not store.set_state(fp, state):
                    return self.send(404, {"error": "unknown key"})
                return self.send(200, {"ok": True, "state": state})
            self.send(404, {"error": "not found"})

        def verify(self):
            ip = store.h("ip:" + self.client_ip())[:12]
            if not limiter.allow("ip:" + ip, RATE_IP):
                return self.send(429, {"error": "too many requests"})
            data = self.body_json()
            if data is None or set(data) != {"key", "robloxUserId", "script", "v"}:
                return self.send(400, {"error": "bad request"})
            key, uid, script, v = data["key"], data["robloxUserId"], data["script"], data["v"]
            if (not isinstance(key, str) or not key.startswith(KEY_PREFIX) or len(key) > 128 or
                    not isinstance(uid, int) or isinstance(uid, bool) or uid <= 0 or
                    not isinstance(script, str) or not 1 <= len(script) <= 40 or not isinstance(v, int) or isinstance(v, bool)):
                return self.send(400, {"error": "bad request"})
            script = "".join(ch for ch in script if ch.isalnum() or ch in "_-. ")[:40]
            game = (scripts.get(script) or {}).get("game")
            if not limiter.allow("key:" + store.h(key)[:10], RATE_KEY):
                return self.send(429, {"error": "too many requests"})
            status, expires, fp, owner = store.verify(key, uid)
            store.log(uid, script, game, v, status, fp, ip, owner)
            if resolve and not store.has_name(uid):
                threading.Thread(target=resolve_name, args=(store, uid), daemon=True).start()
            out = {"status": status}
            if status == "valid":
                out["expiresAt"] = expires
            self.send(200, out)

    return H


def serve(host, port, db_path, admin_token, scripts_path=None, resolve=False):
    os.environ.setdefault("DB_PATH", db_path)
    store = Store(db_path, load_salt())
    scripts = json.load(open(scripts_path or os.path.join(HERE, "scripts.json"), encoding="utf-8"))
    handler = make_handler(store, scripts, admin_token, Limiter(), resolve)
    srv = ThreadingHTTPServer((host, port), handler)
    return srv, store


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", nargs="?", default="serve", choices=["serve", "addkey"])
    ap.add_argument("--host", default=os.environ.get("HOST", "127.0.0.1"))
    ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8787")))
    ap.add_argument("--db", default=os.environ.get("DB_PATH", os.path.join(HERE, "yslem_api.db")))
    ap.add_argument("--user", type=int, help="addkey : UserId Roblox")
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--note", default="")
    a = ap.parse_args()
    os.environ["DB_PATH"] = a.db
    if a.cmd == "addkey":
        if not a.user:
            sys.exit("--user requis")
        store = Store(a.db, load_salt())
        key, fp = store.new_key(a.user, a.days, a.note)
        print(key, "(empreinte %s)" % fp)
        return
    token = os.environ.get("ADMIN_TOKEN")
    if not token:
        token = secrets.token_urlsafe(24)
        print("ADMIN_TOKEN genere (affiche une seule fois) :", token)
    srv, _ = serve(a.host, a.port, a.db, token, resolve=os.environ.get("RESOLVE_NAMES") == "1")
    print("yslem API sur http://%s:%d  (dashboard : /, API : POST /v1/verify)" % (a.host, a.port))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
