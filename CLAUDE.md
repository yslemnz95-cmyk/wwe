# Projets Roblox de yslem (a lire au debut de chaque session)

Depot : scripts Lua/Luau executes cote client. Branche de travail : `claude/focused-archimedes-me0rpk`.
Verifier un fichier : `/tmp/luau_bin/luau-compile --binary fichier.lua` (rc=0 = ok), `luau-analyze` pour les globales
inconnues (les globales Roblox/executeur apparaissent a tort).

## Projets
| Fichier | Jeu | Role |
|---|---|---|
| `yslemEgg_COMPLETE.lua` | Steal An Egg | hub complet (UI MoonEgg, Instant TP sans Anti Guard, Delivery Stop, Normal) |
| `yslemEgg_InstantTP_Standalone.lua` | Steal An Egg | Instant TP seul + choix du pet (icone, valeur) |
| `yslemEgg_DeliveryStop_Standalone.lua` | Steal An Egg | Delivery Stop seul, stops modifiables (Stops, Pause, Distance, Go Fly/Run) |
| `yslempet_EggTP.lua` | Ride a Pet (PlaceId 124216119978534) | tp vers les oeufs de la map + retour au ranch (drop/reprise devant le plot) |
| `yslem_GameScan.lua` | tous | module d'analyse du jeu (voir plus bas) |
| `GUIDE_Livraison_InstantTP.md` | Steal An Egg | explication de la logique de livraison |

## Regle permanente : analyse integree a CHAQUE projet
Chaque script contient le bloc `yslem GameScan` (entre les marqueurs START / END de `yslem_GameScan.lua`) :
- un bouton **"i"** dans la barre de titre ouvre un panneau d'analyse et copie le rapport dans le presse-papier ;
- l'analyse se lance **automatiquement quand quelque chose echoue** (drop non detecte, cible introuvable, etc.) ;
- le rapport couvre : contexte (jeu, joueur, humanoid, capacites de l'executeur), securite (observations : noms de
  scripts/remotes evocateurs, attributs de minuterie - RIEN n'est modifie), boutons visibles (nom, texte, position),
  prompts (ActionText | ObjectText), remotes, monde (Workspace), inventaire/stats, scripts ;
- quand un nouveau projet est cree ou qu'un bug depend du jeu : coller le bloc, brancher le bouton "i" et appeler
  `GameScan.run()` + `GameScan.copy(...)` dans les branches d'echec, puis demander au joueur de coller le rapport.
- garder `yslem_GameScan.lua` comme source unique : toute amelioration du module est recopiee dans les projets.

## Preferences permanentes du joueur
- Toujours renvoyer le fichier modifie (SendUserFile), commit + push sur la branche ci-dessus, ne PAS creer de PR.
- Delivery Stop fonctionne : ne pas y toucher sauf demande. Toute logique propre a Instant TP est gatee sur `Teleport`.
- Aucune vitesse de livraison au-dessus de 115% de la vitesse de marche (le ratio de saut 1,515 est une distance).
- Style UI "yslemStyle" : contours et textes en degrade anime qui tourne, theme noir, formes arrondies, petite UI,
  aucune information interne (FPS cap, vitesses) affichee a l'utilisateur.
- Nom de marque : yslemEgg (plus aucune mention de Chilli dans le code).
- Ne jamais mentionner de modele / identite d'IA dans les commits, PR ou commentaires.

## Securite (permanent, non negociable)
NE JAMAIS inclure : `loadstring(game:HttpGet(...))`, WebSocket externe, jetons/cles, `HttpGet` vers des depots externes,
desactivation d'anti-triche via `getconnections`, webhook Discord / kill-switch / backdoor RPC, `queue_on_teleport`
(donc pas d'auto-load apres un server hop), remotes d'administration/staff. Pas d'agents (Agent tool) sauf demande.

## Notes jeu : Steal An Egg
- Ligne de separation `World.Areas.SeparationLine` (X ~ 552) : gauche = base/zone sure, droite = gardes.
- Livraison confirmee par `RE/EggWorld/FieldEggRedeemVerdict`; portage via `EggState.CarryChanged`
  (+ verification des soudures `HeldByMe`). Rembobinage serveur : `RE/RigSync/Refresh` avec `Action = "Relocate"`.
- Le hub est protege par le bouclier "Humanoid Swap" (copie de l'Humanoid) : sans lui on meurt au moment du tp.
- Vitesse de marche reelle = min(Humanoid.WalkSpeed, vitesse issue de leaderstats.Speed via TreadmillUtil).

## Notes jeu : Ride a Pet (yslempet_EggTP) - releve par GameScan (appareil mobile, Delta)
- PlaceId 124216119978534. Marche a 20 de vitesse, saut 73. Position typique du joueur : Y ~ 40316 (le ranch est en hauteur).
- Oeufs de la map : `Workspace.RenderedEggs.<Nom>` (prompt `Pick Up | <Nom>`, maintien 0,2 s). Stands : `Workspace.Stalls`
  = Gears (Rick), Food (Tim, prompt "Talk"), Sell (Richie), EggTracker (Eggo). Plots : `Workspace.Plots.Plot` (pets, oeufs).
- **Bouton DROP** : `PlayerGui.Main.BasketTracker.Handler.EggFrame.Drop` (ImageButton "Drop", texte DROP).
  **Remote du drop** : `ReplicatedStorage.Remotes.Game.BasketDrop` (RemoteEvent). Autres remotes utiles dans
  `Remotes.Game` : EggPickup, EggBroke, EggTimerPause, EggArrivalClaim, TeleportToPlot, PickupPet, PetMove, Rebirth.
- Barre "Egg Will Break" (compte a rebours) = on porte un oeuf (dans BasketTracker).
- Securite observee (noms seulement) : attribut joueur `TeleportGraceUntil` (le serveur donne un delai de grace apres un
  teleport legitime -> il verifie les teleports), remotes `Strike`, `Ban`, `Teleporting`, `RE/Ragdoll`, Cmdr (kick, `CmdrAdmin=false`),
  LocalScript `StudioCheatTeleport` (outil de dev). Pas de nom "anticheat" explicite.
- Capacites executeur confirmees : firesignal, fireproximityprompt, setclipboard, gethui, setfpscap, VirtualInputManager.
- Retour au ranch : on se place a l'EXTERIEUR du plot (bord de la boite englobante + marge), on lache l'oeuf (bouton Drop
  via firesignal, puis remote BasketDrop, puis Backspace, clic souris en dernier recours), on le reprend (prompt Pick Up),
  puis VOL a 700% de la vitesse de marche jusque dans le plot et pose au sol. Pas de touche/toucher simule (bloque le joystick).
- Le plot du joueur est trouve par nom d'instance (pseudo/UserId) ou pancarte "Your Ranch" ; jamais le plus proche.
- Idee non activee : `Remotes.Game.TeleportToPlot` (teleport integre du jeu vers le plot, avec delai de grace serveur).
