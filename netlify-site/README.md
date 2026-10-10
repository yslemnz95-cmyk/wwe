# Sources Hub stats (site Netlify)

Site : `sourceshub-stats` (https://sourceshub-stats.netlify.app). Fichiers statiques dans `public/`, fonctions dans `netlify/functions/`
(stockage Netlify Blobs, aucune base externe).

| Route | Role |
|---|---|
| `GET /` | page publique yslemStyle : membres en ligne, executions totales, aujourd'hui, 7 jours, par jeu. Bouton Admin = detail (qui, quel jeu, quel script) |
| `POST /api/ping` | recu depuis `SourcesHub.lua` (champs : uid, name, place, game, script, v, t = start/beat). Rien d'autre n'est accepte |
| `GET /api/stats` | chiffres agreges (publics, sans pseudos) |
| `GET /api/admin` | detail des membres et fil des executions, en-tete `Authorization: Bearer <ADMIN_TOKEN>` |

`ADMIN_TOKEN` = variable d'environnement Netlify (secrete, portee Functions). Jamais dans le depot.
Membre en ligne = ping dans les 150 dernieres secondes (le script envoie un battement par minute).

Deploiement : depuis ce dossier, `npx netlify deploy --prod --site 953d7a68-10ba-4c70-a1f4-03f54cd2666f` (apres `npm install`), ou par le connecteur Netlify
(`npx @netlify/mcp@latest --site-id ... --proxy-path ...` : exige que l'hote `netlify-mcp.netlify.app` soit autorise).
Test local des fonctions (faux Blobs) : `node --experimental-strip-types test/run.mjs`.
