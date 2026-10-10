# Sources Hub stats (site Vercel)

Projet Vercel `sourceshub-stats` (id prj_2VCPUuzkJFOlbCQkJpp9MRAIHPVb) -> https://sourceshub-stats.vercel.app
Static page dans `public/`, fonctions dans `api/`, stockage Vercel Blob prive (`sourceshub-data`, region fra1, jeton `BLOB_READ_WRITE_TOKEN` lie au projet).

| Route | Role |
|---|---|
| `GET /` | page publique yslemStyle : membres en ligne, executions totales, aujourd'hui, 7 jours, par jeu. Bouton Admin = detail (qui, quel jeu, quel script) |
| `POST /api/ping` | recu depuis `SourcesHub.lua` (champs : uid, name, place, game, script, v, t = start/beat). Rien d'autre n'est accepte |
| `GET /api/stats` | chiffres agreges (publics, sans pseudos) |
| `GET /api/admin` | detail des membres et fil des executions, en-tete `Authorization: Bearer <ADMIN_TOKEN>` |

`ADMIN_TOKEN` = variable d'environnement Vercel (sensible). Jamais dans le depot. La protection "Vercel Authentication" du projet est desactivee (le script Roblox doit pouvoir envoyer ses pings).
Membre en ligne = ping dans les 150 dernieres secondes (un battement par minute).
Un enregistrement par membre (`u/<uid>.json`) : le compteur d'un membre n'est ecrit que par ses propres pings.

Deploiement : connecteur Vercel (`create_deployment`, fichiers en ligne) ou `vercel deploy --prod` depuis ce dossier.
Test local des fonctions (faux Blob) : `node vercel-site/test/run.mjs`.
