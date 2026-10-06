---
name: roblox-verify
description: Verifier un script Roblox/Luau de yslem avant de le livrer (compile, analyse des globales, maquette, regles de securite). A utiliser a chaque fois qu'un fichier .lua du depot est cree ou modifie.
---

# Verification avant livraison

1. `/tmp/luau_bin/luau-compile --binary <fichier>` doit renvoyer rc=0.
2. `/tmp/luau_bin/luau-analyze <fichier> 2>&1 | grep "Unknown global"` (attention : stderr). Ignorer les globales Roblox/executeur
   (game, workspace, Enum, Vector3, CFrame, Color3, UDim2, UDim, Instance, task, warn, TweenInfo, ColorSequence*,
   RaycastParams, OverlapParams, gethui, firesignal, fireproximityprompt). Tout le reste est une VRAIE faute
   (fonction jamais definie, ex. `place`).
3. Test de logique avec la maquette (`tools/mock/`) :
   - Ride a Pet perso : `python3 tools/mock/build.py <normal|remote|click|vol|stop [s]|lose> && /tmp/luau_bin/luau tools/mock/all.lua`
   - Script de l'ami : `python3 tools/mock/build_friend.py <normal|remote|nodrop|stop [s]|lose> && /tmp/luau_bin/luau tools/mock/friend_all.lua`
   Piege de la maquette : `obj.Parent = nil` ne retire pas l'objet de `Children` apres la 1re affectation ; retirer a la main.
4. Securite (non negociable) : grep le fichier pour `loadstring`, `HttpGet`, `getconnections`, `queue_on_teleport`, `webhook`, `WebSocket`. Aucun.
5. Dire clairement ce qui est teste (maquette) et ce qui ne l'est pas (jeu reel, UI).
6. Fin de tache : `SendUserFile`, commit + push sur la branche de travail, pas de PR, arbre git propre (sinon le hook d'arret bloque).
