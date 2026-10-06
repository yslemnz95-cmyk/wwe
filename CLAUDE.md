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
| `yslem_GameScan.lua` | tous | module d'analyse du jeu, a coller TEMPORAIREMENT (voir plus bas) |
| `friend/ShinEggFarm_yslem.lua` | Ride a Pet | script SHIN HUB d'un ami repare (TP oeuf, prise confirmee, drop dehors, reprise, vol 700%), UI yslemStyle rouge/noir, bouton GO/STOP. Non teste en jeu (pas de maquette) |
| `tools/mock/` | tous | maquette Roblox + scenarios de test de `yslempet_EggTP.lua` |
| `GUIDE_Livraison_InstantTP.md` | Steal An Egg | explication de la logique de livraison |

## Regle permanente : analyse du jeu = outil TEMPORAIRE (module `yslem_GameScan.lua`)
Quand un jeu est nouveau ou qu'un bug depend du jeu : coller le bloc `yslem GameScan` (marqueurs START / END) dans le script,
ajouter un bouton "i" qui appelle `GameScan.run()` + `GameScan.copy(...)`, faire coller le rapport par le joueur, puis
**RETIRER le bloc et le bouton du projet** (le projet final n'embarque pas l'analyse) et noter les faits utiles dans ce
fichier. `GameScan.find("mot")` fait une recherche ciblee (boutons, textes, remotes, prompts, objets du monde).
Le rapport couvre : contexte, securite (observations de noms seulement - rien n'est modifie), boutons visibles, prompts,
remotes, monde, inventaire/stats, scripts. `yslempet_EggTP.lua` a deja ete analyse : son bloc a ete retire.

## Verification avant de livrer un script
1. `/tmp/luau_bin/luau-compile --binary fichier.lua` (rc=0) ET `luau-analyze fichier.lua | grep "Unknown global"` :
   toute globale qui n'est pas Roblox/executeur est une VRAIE faute de frappe ou une fonction non definie (ex. un
   appel a `place` jamais defini a deja ete trouve ainsi).
2. Test de fumee avec la maquette Roblox : `python3 tools/mock/build.py <scenario> && /tmp/luau_bin/luau tools/mock/all.lua`
   (scenarios : normal, remote, click, vol, stop [secondes], lose). Elle simule le monde de Ride a Pet (oeufs, bouton Drop,
   remote BasketDrop, barre Egg Will Break, plot) et verifie : prise, drop, reprise, vol vers le ranch, STOP, oeuf perdu en vol.

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
- Prise de l'oeuf CONFIRMEE (barre Egg Will Break) ; retour au ranch : on se place a l'EXTERIEUR du plot (bord de la boite
  englobante + 20 studs), on lache l'oeuf (bouton Drop via firesignal, puis remote BasketDrop, puis Backspace, clic souris en
  dernier recours), on le reprend (reprise confirmee), puis VOL a 700% de la vitesse de marche jusqu'a 15 studs apres le
  centre du plot et pose au sol. Pas de toucher simule (bloque le joystick). STOP interrompt tout (drapeau `cancelMove`
  remis a zero seulement au debut d'un trajet).
- Le plot du joueur est trouve par nom d'instance (pseudo/UserId) ou pancarte "Your Ranch" ; jamais le plus proche.
- Idee non activee : `Remotes.Game.TeleportToPlot` (teleport integre du jeu vers le plot, avec delai de grace serveur).
