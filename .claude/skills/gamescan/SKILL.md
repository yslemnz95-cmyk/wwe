---
name: gamescan
description: Analyser un jeu Roblox nouveau ou un bug qui depend du jeu avec le module temporaire yslem_GameScan.lua. A utiliser quand les noms de remotes, boutons, plots ou prompts d'un jeu sont inconnus ou que le script rate chez un joueur.
---

# Analyse de jeu (outil TEMPORAIRE)

1. Coller le bloc `yslem GameScan` (marqueurs START/END de `yslem_GameScan.lua`) dans le script.
2. Ajouter un petit bouton "i" qui appelle `GameScan.run()` puis `GameScan.copy(...)` (copie le rapport dans le presse-papiers).
   `GameScan.find("mot")` fait une recherche ciblee (boutons, textes, remotes, prompts, objets du monde).
3. Demander au joueur de coller le rapport. Il couvre : contexte, securite (noms seulement, rien n'est modifie), boutons,
   prompts, remotes, monde, inventaire/stats, scripts.
4. Utiliser les noms reels trouves, puis RETIRER le bloc et le bouton : le projet final n'embarque jamais l'analyse.
5. Noter les faits utiles dans CLAUDE.md (section "Notes jeu").
Ne rien deduire de noms supposes : si un nom n'est pas dans le rapport ou CLAUDE.md, le dire.
