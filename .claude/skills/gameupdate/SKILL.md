---
name: gameupdate
description: "Game update" - le jeu a ete mis a jour (ou un script casse apres une mise a jour) : relancer une analyse complete, la comparer a la precedente, lister tout ce qui a change et adapter les scripts. A utiliser quand le joueur dit "Game update", "le jeu a update", "ca ne marche plus depuis la maj".
---

# Game update (procedure permanente)

Objectif : savoir TOUT ce qui a change dans le jeu depuis la derniere analyse, puis adapter nos scripts avec les noms reels.

1. **Quel jeu ?** Steal An Egg (yslemHub, SourcesHub, standalones) ou Ride a Pet (yslempet_EggTP, friend/ShinEggFarm_yslem). Si ce n'est pas clair, le demander.
2. **Un seul fichier, 2 etapes** : demander au joueur d'executer `yslem_GameAnalyzer.lua` (renvoye avec SendUserFile). Etape 1 = structure, Etape 2 = contenu
   (donnees des modules RS/Data + tous les textes). Chaque etape copie un message pour toi + l'inventaire ; le joueur colle les deux dans le chat. Un badge en bas a droite
   lui dit quand chaque etape est faite. Pas de bloc a coller ni a retirer.
3. **Sauvegarder** le texte dans `docs/scans/<Jeu>_<AAAA-MM-JJ>_etape1.txt (et _etape2.txt)` (commit). S'il n'y a AUCUN inventaire precedent pour ce jeu, celui-ci devient la
   reference (baseline) : le dire, et lancer en plus `GameScan.run()` classique pour les faits lisibles (voir skill gamescan).
4. **Comparer** : `python3 tools/gamediff.py docs/scans/<ancien>.txt docs/scans/<nouveau>.txt --out docs/scans/diff_<date>.md`.
   Le rapport donne supprime / deplace / ajoute / modifie et surtout **IMPACT sur nos scripts** (fichiers et lignes qui citent un nom touche).
5. **Adapter** : corriger les scripts touches avec les noms du NOUVEL inventaire uniquement (rien de suppose). Pour chaque ajout interessant
   (nouveau remote, nouveau bouton), dire ce que ca pourrait permettre sans l'activer sans demande.
6. **Verifier** (skill roblox-verify : compile, globales, maquette) puis mettre a jour `CLAUDE.md > Notes jeu` avec les noms changes.
7. **Retirer** le bloc GameScan et le bouton "snap" du projet (le projet final n'embarque jamais l'analyse). Commit + push, renvoyer le fichier (SendUserFile).

Regles : ne jamais deviner un nom absent de l'inventaire ; si le jeu a change de PlaceId ou de structure majeure, le dire avant de reecrire.
Test des outils : `python3 tools/mock/build_scan.py && /tmp/luau_bin/luau tools/mock/scan_all.lua` et `python3 tools/mock/test_gamediff.py`.
