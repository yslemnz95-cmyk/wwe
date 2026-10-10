#!/usr/bin/env python3
"""Compare deux inventaires GameScan.snapshot() et dit ce qui a change dans le jeu (Game update).

  python3 tools/gamediff.py docs/scans/RideAPet_2026-09-01.txt docs/scans/RideAPet_2026-10-10.txt [--repo .] [--out rapport.md]

Sortie : ajouts, suppressions, renommages probables (meme nom, autre dossier), textes de boutons / prompts / compteurs modifies,
puis l'IMPACT sur les scripts du depot (fichiers .lua qui citent un nom supprime ou renomme).
"""
import argparse, os, re, sys


def load(path):
    meta, rows = {}, {}
    for raw in open(path, encoding="utf-8", errors="replace"):
        line = raw.rstrip("\r\n")
        if not line.strip():
            continue
        if line.startswith("#"):
            k, _, v = line[1:].partition(" ")
            meta[k] = v
            continue
        parts = line.split("|")
        if len(parts) < 5:
            continue
        kind, cls, p, extra, n = parts[0], parts[1], parts[2], "|".join(parts[3:-1]), parts[-1]
        rows[(kind, p)] = (cls, extra, int(n) if n.isdigit() else 1)
    return meta, rows


def leaf(p):
    return p.rsplit("/", 1)[-1]


def leaf_names(p):
    """Noms (feuille) a chercher dans les scripts ; on ignore les noms normalises (#, <guid>) et trop courts."""
    name = leaf(p)
    return [name] if len(name) >= 4 and "#" not in name and "<guid>" not in name else []


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--out")
    ap.add_argument("--files", nargs="*", help="limiter l'impact a ces scripts (sinon : docs/scans/games.json selon le nom du jeu)")
    a = ap.parse_args()

    m1, old = load(a.old)
    m2, new = load(a.new)
    out = []
    w = out.append
    w("# Game update : %s -> %s" % (os.path.basename(a.old), os.path.basename(a.new)))
    w("ancien : %s (%s)" % (m1.get("GAME", "?"), m1.get("DATE", "?")))
    w("nouveau : %s (%s)" % (m2.get("GAME", "?"), m2.get("DATE", "?")))
    if m1.get("GAME", "").split(" PlaceId=")[0:1] != m2.get("GAME", "").split(" PlaceId=")[0:1]:
        w("ATTENTION : les deux inventaires ne semblent pas venir du meme jeu.")

    added = sorted(k for k in new if k not in old)
    removed = sorted(k for k in old if k not in new)
    DYNAMIC = ("WORLD", "PROMPT", "BUTTON")  # un simple changement de nombre n'est pas une mise a jour

    def really_changed(k):
        o, n = old[k], new[k]
        return o[0] != n[0] or o[1] != n[1] or (o[2] != n[2] and k[0] not in DYNAMIC)

    changed = sorted(k for k in new if k in old and really_changed(k))

    # renommages probables : meme type + meme nom de feuille, chemin different
    renamed = []
    rem_by = {}
    for k in removed:
        rem_by.setdefault((k[0], leaf(k[1])), []).append(k)
    used_added, used_removed = set(), set()
    for k in added:
        cands = rem_by.get((k[0], leaf(k[1])))
        if cands and "#" not in leaf(k[1]):
            r = cands[0]
            renamed.append((r, k))
            used_added.add(k)
            used_removed.add(r)
    added2 = [k for k in added if k not in used_added]
    removed2 = [k for k in removed if k not in used_removed]

    w("")
    w("## Resume")
    w("- ajoutes : %d  supprimes : %d  deplaces : %d  modifies : %d  (inchanges : %d)" % (
        len(added2), len(removed2), len(renamed), len(changed), len(new) - len(added) - len(changed)))

    def block(title, items, fmt):
        w("")
        w("## %s (%d)" % (title, len(items)))
        if not items:
            w("(rien)")
        for it in items[:400]:
            w(fmt(it))
        if len(items) > 400:
            w("... +%d autres" % (len(items) - 400))

    block("SUPPRIMES", removed2, lambda k: "- [%s] %s %s" % (k[0], k[1], ("(%s)" % old[k][1]) if old[k][1] else ""))
    block("DEPLACES / RENOMMES", renamed, lambda t: "- [%s] %s  ->  %s" % (t[0][0], t[0][1], t[1][1]))
    block("AJOUTES", added2, lambda k: "+ [%s] %s %s" % (k[0], k[1], ("(%s)" % new[k][1]) if new[k][1] else ""))

    def chg(k):
        o, n = old[k], new[k]
        bits = []
        if o[0] != n[0]:
            bits.append("classe %s -> %s" % (o[0], n[0]))
        if o[1] != n[1]:
            bits.append("texte '%s' -> '%s'" % (o[1], n[1]))
        if o[2] != n[2]:
            bits.append("nombre %d -> %d" % (o[2], n[2]))
        return "~ [%s] %s : %s" % (k[0], k[1], "; ".join(bits))

    block("MODIFIES", changed, chg)

    # impact sur les scripts du depot
    lua = []
    for d, _, fs in os.walk(a.repo):
        if any(x in d for x in (".git", "node_modules", "tools/mock")):
            continue
        for f in fs:
            if f.endswith(".lua"):
                lua.append(os.path.join(d, f))
    only = a.files
    if only is None:
        try:
            import json
            games = json.load(open(os.path.join(a.repo, "docs", "scans", "games.json"), encoding="utf-8"))
            gname = m2.get("GAME", "").lower()
            for key, files in games.items():
                if key in gname:
                    only = files
                    break
        except (OSError, ValueError):
            pass
    if only:
        want = {os.path.normpath(os.path.join(a.repo, f)) for f in only}
        lua = [f for f in lua if os.path.normpath(f) in want]
        w_scope = "scripts examines : " + ", ".join(sorted(os.path.relpath(f, a.repo) for f in lua))
    else:
        w_scope = "scripts examines : tous les .lua du depot (jeu inconnu de docs/scans/games.json)"
    texts = {}
    for f in lua:
        try:
            texts[f] = open(f, encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            pass

    def uses(name):
        pat = re.compile(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"(?![A-Za-z0-9_])")
        hits = []
        for f, lines in texts.items():
            for i, line in enumerate(lines, 1):
                if pat.search(line):
                    hits.append("%s:%d" % (os.path.relpath(f, a.repo), i))
                    if len(hits) >= 6:
                        return hits
        return hits

    w("")
    w("## IMPACT sur nos scripts")
    w(w_scope)
    n_imp = 0
    watch = [("SUPPRIME", k) for k in removed2] + [("DEPLACE", r) for r, _ in renamed] + [("MODIFIE", k) for k in changed if old[k][1] != new[k][1]]
    seen = set()
    for tag, k in watch:
        if k[0] in ("WORLD", "SCREEN"):
            continue
        for name in leaf_names(k[1]):
            if (tag, name) in seen:
                continue
            seen.add((tag, name))
            hits = uses(name)
            if hits:
                n_imp += 1
                extra = ""
                if tag == "DEPLACE":
                    extra = "  -> nouveau chemin : " + next(t[1][1] for t in renamed if t[0] == k)
                w("! %s [%s] %s  cite dans : %s%s" % (tag, k[0], name, ", ".join(hits), extra))
    if n_imp == 0:
        w("Aucun nom supprime / deplace / modifie n'est cite dans nos scripts.")
    w("")
    w("A faire : adapter les scripts ci-dessus (noms reels du nouvel inventaire uniquement), relancer les tests de la maquette, noter les faits dans CLAUDE.md > Notes jeu.")

    text = "\n".join(out)
    if a.out:
        open(a.out, "w", encoding="utf-8").write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
