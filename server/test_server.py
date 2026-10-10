#!/usr/bin/env python3
"""Test de bout en bout : python3 server/test_server.py"""
import json, os, sys, tempfile, threading, urllib.request, urllib.error
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import app

tmp = tempfile.mkdtemp()
os.environ["DB_PATH"] = os.path.join(tmp, "t.db")
srv, store = app.serve("127.0.0.1", 0, os.environ["DB_PATH"], "TESTTOKEN")
port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = "http://127.0.0.1:%d" % port
fails = 0


def call(path, body=None, token=None, raw=None):
    req = urllib.request.Request(base + path, data=(raw if raw is not None else (json.dumps(body).encode() if body is not None else None)),
                                 headers={"Content-Type": "application/json"})
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read().decode() or "null") if "json" in r.headers.get("Content-Type", "") else r.read()
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "null")


def check(name, ok):
    global fails
    print(("ok   " if ok else "FAIL ") + name)
    if not ok:
        fails += 1


A = "TESTTOKEN"
st, r = call("/admin/api/keys", {"robloxUserId": 111, "days": 30, "note": "test"}, A)
key = r["key"]
check("key created (YSL-, 24+ chars)", st == 200 and key.startswith("YSL-") and len(key) >= 28)
check("no clear key in db", key.encode() not in open(os.environ["DB_PATH"], "rb").read())

V = lambda k, uid, script="yslemHub", v=1: call("/v1/verify", {"key": k, "robloxUserId": uid, "script": script, "v": v})
st, r = V(key, 111)
check("valid", st == 200 and r["status"] == "valid" and r["expiresAt"] > 0)
st, r = V(key, 222)
check("key of another user -> invalid", r["status"] == "invalid")
st, r = V("YSL-" + "a" * 30, 111)
check("unknown key -> invalid", r["status"] == "invalid")
st, r = call("/v1/verify", {"key": key, "robloxUserId": 111, "script": "yslemHub", "v": 1, "extra": 1})
check("extra field rejected", st == 400)
st, r = call("/v1/verify", raw=b"not json")
check("garbage rejected", st == 400)
st, r = V(key, 111, "yslempet_EggTP")
check("other script ok", r["status"] == "valid")

fp = key and store.h(key)[:10]
call("/admin/api/keys/revoke", {"fp": fp}, A)
check("revoked", V(key, 111)[1]["status"] == "revoked")
call("/admin/api/keys/ban", {"fp": fp}, A)
check("banned", V(key, 111)[1]["status"] == "banned")
call("/admin/api/keys/restore", {"fp": fp}, A)
check("restored", V(key, 111)[1]["status"] == "valid")

# expired
k2 = store.new_key(333, 1)[0]
store.db.execute("UPDATE keys SET expires=1 WHERE user_id=333"); store.db.commit()
check("expired", V(k2, 333)[1]["status"] == "expired")

# admin protection
check("events need token", call("/admin/api/events")[0] == 401)
check("wrong token", call("/admin/api/events", token="x")[0] == 401)
st, r = call("/admin/api/events?limit=50", token=A)
ev = r["events"]
check("events logged (all attempts)", st == 200 and len(ev) >= 8)
check("game derived from script", any(e["game"] == "Steal An Egg" and e["script"] == "yslemHub" for e in ev) and any(e["game"] == "Ride a Pet" for e in ev))
check("no key / ip in clear in events", all("key" not in e and e["ip"] and "127.0.0.1" not in e["ip"] for e in ev))
st, r = call("/admin/api/events?status=invalid", token=A)
check("filter status", r["events"] and all(e["status"] == "invalid" for e in r["events"]))
st, r = call("/admin/api/events?user=111&game=Ride%20a%20Pet", token=A)
check("filter user+game", len(r["events"]) == 1)
st, r = call("/admin/api/stats", token=A)
check("stats", r["h24"]["executions"] >= 8 and r["byGame"] and len(r["hourly"]) == 24 and r["online"] >= 1)
st, r = call("/admin/api/player?id=111", token=A)
check("player history", r["userId"] == 111 and len(r["events"]) >= 5 and r["keys"])
st, r = call("/admin/api/keys", token=A)
check("keys list", any(k["user_id"] == 111 and k["uses"] >= 5 for k in r["keys"]))
st, page = call("/")
check("dashboard served, no data inline", st == 200 and b"yslem Executions" in page and b"111" not in page)
check("bad key request", call("/admin/api/keys", {"robloxUserId": -1, "days": 5}, A)[0] == 400)
check("injection in script name is stripped", V(key, 111, "<script>alert(1)</script>")[0] == 200 and
      not any("<" in (e["script"] or "") for e in call("/admin/api/events", token=A)[1]["events"]))

# rate limit per key
codes = [V("YSL-" + "b" * 30, 444)[0] for _ in range(25)]
check("rate limit per key (429)", 429 in codes)
print("FAILS", fails)
sys.exit(1 if fails else 0)
