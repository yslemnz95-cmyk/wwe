# Contrat Key System (bot <-> scripts Roblox)

Source de verite partagee entre la session "bot" (GitLab) et la session "scripts" (GitHub). Ne pas modifier d'un seul cote.

## Parcours
1. Le script ouvre une fenetre : invitation Discord + 3 etapes (rejoindre, `/key <pseudo_roblox>` dans le salon cle, coller la cle recue).
2. Le bot lie la cle au **UserId Roblox** (jamais au pseudo) et au compte Discord. Une cle par UserId et par compte Discord.
3. Le script sauvegarde la cle en local (`yslem_key.txt`) et la reverifie au demarrage puis toutes les 15 minutes.

## Endpoint
`POST {BASE}/v1/verify` - `Content-Type: application/json`

Requete (ces 4 champs et rien d'autre) :
```json
{"key": "YSL-xxxxxxxxxxxxxxxxxxxxxxxx", "robloxUserId": 123456, "script": "yslemEgg", "v": 1}
```
Reponse `200` :
```json
{"status": "valid", "expiresAt": 1790000000}
```
`status` : `valid` | `invalid` | `expired` | `revoked` | `banned`.
Cle inconnue, cle fausse et cle liee a un autre UserId renvoient toutes `invalid`.

Autres codes : `429` trop de requetes. Tout autre code, toute reponse non JSON ou statut inconnu = erreur reseau.

## Format de cle
`YSL-` suivi d'au moins 24 caracteres base64url (`[A-Za-z0-9_-]`), 128 caracteres maximum au total. Le script refuse localement tout autre format sans appeler le serveur.

## Comportement du script
- Au demarrage : cle sauvegardee absente ou refusee -> fenetre de cle. Erreur reseau -> refuse de demarrer (fail closed), la cle sauvegardee est conservee.
- `invalid`, `expired`, `revoked`, `banned` : la cle locale est effacee.
- Reverification toutes les 15 min : un statut autre que `valid` arrete le script. 3 erreurs reseau d'affilee l'arretent aussi (1 ou 2 sont tolerees).
- Le script n'envoie aucune autre donnee et ne charge aucun code distant.

## Cote bot (rappel)
Hash + sel serveur uniquement, jamais la cle en clair ; limite de requetes par IP et par cle ; CORS ferme ; HTTPS obligatoire ; pas de log de cle en clair.

## Integration cote script
`python3 tools/add_keygate.py --api https://URL_DU_BOT --invite https://discord.gg/XXXX [--channel "#key"]`
Test : `python3 tools/mock/build_keygate.py && /tmp/luau_bin/luau tools/mock/keygate_all.lua`
