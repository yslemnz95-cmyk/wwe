# API + dashboard des executions (dossier `server/`)

Serveur Python sans dependance (stdlib + SQLite). Il implemente le contrat `docs/KEY_API.md` (`POST /v1/verify`, inchange : 4 champs)
et enregistre CHAQUE appel = une execution ou une tentative : heure, UserId, script, jeu, statut, empreinte de cle, v, IP hachee.
Le jeu est deduit du nom du script via `server/scripts.json` (le client n'envoie rien de plus).

Confidentialite : la cle n'est jamais stockee en clair (HMAC + sel), l'IP est hachee (HMAC tronque), pas de cookies, pas de tiers.
Le dashboard n'affiche rien sans `ADMIN_TOKEN` ; CORS ferme ; limites 60 req/min/IP et 20 req/min/cle.

## Lancer
```
ADMIN_TOKEN=un_long_secret python3 server/app.py          # http://127.0.0.1:8787  (HOST/PORT/DB_PATH modifiables)
python3 server/app.py addkey --user 123456 --days 30     # cree une cle de test (affichee une seule fois)
python3 server/demo_seed.py /tmp/demo.db                  # fausses donnees pour voir le dashboard (DB_PATH=/tmp/demo.db)
python3 server/test_server.py                             # tests de bout en bout (26 verifications)
```
Sans `ADMIN_TOKEN`, un jeton aleatoire est genere et affiche une fois. Derriere un proxy HTTPS (Railway, Render...) : `TRUST_PROXY=1`.
`RESOLVE_NAMES=1` : le serveur (pas le client) resout le pseudo Roblox via users.roblox.com (cache).

## Dashboard (`/`)
Cartes (1 h / 24 h / 7 j, joueurs en ligne, echecs), courbe par heure, jeux, scripts, tentatives suspectes (3+ echecs / 24 h),
liste filtrable en direct (joueur, jeu, script, statut), historique d'un joueur (clic), gestion des cles (creer, revoquer, bannir, retablir).

## Brancher les scripts
Le script envoie deja `POST {BASE}/v1/verify` au demarrage puis toutes les 15 min : pointer `--api` de `tools/add_keygate.py`
vers ce serveur (HTTPS obligatoire). Si le bot Discord (GitLab) reste la source des cles, il doit ecrire dans la meme table `keys`
ou appeler `POST /admin/api/keys` (jeton admin) ; ce serveur peut aussi remplacer le bot cote verification.
Ajouter un nouveau script/jeu : une ligne dans `server/scripts.json`.
