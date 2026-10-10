# Projets Roblox de yslem (a lire au debut de chaque session)

Depot : scripts Lua/Luau executes cote client. Branche de travail : `claude/focused-archimedes-me0rpk`.
Verifier un fichier : `/tmp/luau_bin/luau-compile --binary fichier.lua` (rc=0 = ok), `luau-analyze` pour les globales
inconnues (les globales Roblox/executeur apparaissent a tort).

## Projets
| Fichier | Jeu | Role |
|---|---|---|
| `yslemHub.lua` | Steal An Egg | hub complet yslemHub (anciennement yslemEgg COMPLETE ; UI, Instant TP sans Anti Guard, Delivery Stop, Normal) |
| `yslemEgg_InstantTP_Standalone.lua` | Steal An Egg | Instant TP seul + choix du pet (icone, valeur) |
| `yslemEgg_DeliveryStop_Standalone.lua` | Steal An Egg | Delivery Stop seul, stops modifiables (Stops, Pause, Distance, Go Fly/Run) |
| `yslempet_EggTP.lua` | Ride a Pet (PlaceId 124216119978534) | tp vers les oeufs de la map + retour au ranch (drop/reprise devant le plot) |
| `SourcesHub.lua` | Steal An Egg | meme logique que yslemHub, pour un serveur ami (Sources Hub), SANS cle (pas de KeyGate). Rouge/noir fixe (pas de menu Theme). UNE seule fenetre avec effets d'ouverture/fermeture (voile + zoom) : barre laterale (sans icones), recherche en haut a droite (en-tete, contour anime yslemStyle + loupe, s'elargit au focus), transition de page a chaque changement d'onglet (glissement + voile + trait lumineux, coupee par UI Optimizer), onglets Steal (le Steal Panel, via `lib.NewToolWindow` qui cree un onglet), Event et Config (copier/importer la config `SHCFG1:`), pied de page FPS/ping. **Stats d'usage** : `lib.StatsSend` envoie `POST https://sourceshub-stats.vercel.app/api/ping` (uid, name, place, game, script, v, t=start/beat ; 1/min) vers le site `vercel-site/` ; interrupteur Config > Usage stats (actif par defaut) + texte qui dit ce qui part ; la reponse est ignoree. Sous-titre = `discord.gg/sourceshubs` (clic = copie). Performance > "UI Optimizer" (`lib.SetNoAnim`) coupe les animations. Anti Guard = carte d'origine (bas de l'ecran) agrandie de 20 %. **Instant TP** : quand l'Anti Guard est OFF, `SafeCarry.InstantHome` execute le moteur `InstantEngine` = la methode du standalone `yslemEgg_InstantTP_Standalone.lua` (sauts, atterrissage, drop/reprise, course vers la zone sure) ; Anti Guard ON = ancienne route `LineDropHome`. Tests : `python3 tools/mock/build_ui.py && luau tools/mock/ui_all.lua` et `python3 tools/mock/build_engine.py && luau tools/mock/engine_all.lua` |
| `yslem_KeyGate.lua` | tous | fenetre de cle yslemStyle + verification aupres du bot (`POST /v1/verify`, contrat dans `docs/KEY_API.md`). Injection : `python3 tools/add_keygate.py --api https://URL --invite https://discord.gg/XXX` (a lancer seulement quand le bot est en ligne, sinon le script se bloque). Test : `python3 tools/mock/build_keygate.py && /tmp/luau_bin/luau tools/mock/keygate_all.lua` |
| `server/` | tous | API de verification de cle (`/v1/verify`, contrat KEY_API) + dashboard web des executions (qui, quel jeu, quel script, tentatives), stdlib Python + SQLite, jeton admin. Doc : `docs/DASHBOARD.md`. Test : `python3 server/test_server.py` |
| `vercel-site/` | Steal An Egg / tous | site Vercel `sourceshub-stats` (https://sourceshub-stats.vercel.app) : page yslemStyle publique (membres en ligne, executions) + fonctions api/ping, stats, admin (Vercel Blob prive), jeton admin en variable d'environnement Vercel. Test : `node vercel-site/test/run.mjs`. Doc : `vercel-site/README.md` |
| `yslem_GameAnalyzer.lua` | tous | **"Game update" en UN fichier, 2 etapes** : Etape 1 = structure (remotes, scripts, ecrans, boutons, prompts, monde, stats) ; Etape 2 = contenu (modules `ReplicatedStorage.Data` via require = pets, raretes, zones, events, produits + tous les textes affiches). Chaque etape copie dans le presse-papier le message pour Claude + l'inventaire ; badge en bas a droite ("Etape N faite - copie-colle"). Fichiers `yslem_analyzer/<PlaceId>_etapeN.txt`, aucun reseau. Test : `python3 tools/mock/build_analyzer.py && /tmp/luau_bin/luau tools/mock/analyzer_all.lua` |
| `yslem_GameScan.lua` | tous | module d'analyse du jeu, a coller TEMPORAIREMENT (voir plus bas) ; `GameScan.snapshot()` = inventaire pour "Game update" (comparaison : `tools/gamediff.py`, inventaires dans `docs/scans/`) |
| `friend/ShinEggFarm_yslem.lua` | Ride a Pet | script SHIN HUB d'un ami, UI rouge/noir yslemStyle, EN ANGLAIS, avec la methode COMPLETE de yslempet_EggTP (tp desync, prise confirmee, drop bouton/remote, reprise confirmee, vol 700%). Test logique : `python3 tools/mock/build_friend.py <normal|remote|nodrop|stop|lose> && /tmp/luau_bin/luau tools/mock/friend_all.lua` |
| `tools/mock/` | tous | maquette Roblox + scenarios de test de `yslempet_EggTP.lua` |
| `GUIDE_Livraison_InstantTP.md` | Steal An Egg | explication de la logique de livraison |

## Regle permanente : analyse du jeu = outil TEMPORAIRE (module `yslem_GameScan.lua`)
Quand un jeu est nouveau ou qu'un bug depend du jeu : coller le bloc `yslem GameScan` (marqueurs START / END) dans le script,
ajouter un bouton "i" qui appelle `GameScan.run()` + `GameScan.copy(...)`, faire coller le rapport par le joueur, puis
**RETIRER le bloc et le bouton du projet** (le projet final n'embarque pas l'analyse) et noter les faits utiles dans ce
fichier. `GameScan.find("mot")` fait une recherche ciblee (boutons, textes, remotes, prompts, objets du monde).
Le rapport couvre : contexte, securite (observations de noms seulement - rien n'est modifie), boutons visibles, prompts,
remotes, monde, inventaire/stats, scripts. `yslempet_EggTP.lua` a deja ete analyse : son bloc a ete retire.

## Game update (procedure permanente, skill `gameupdate`)
Quand le joueur ecrit "Game update" (ou dit que le jeu a ete mis a jour / qu'un script ne marche plus depuis la maj) : on relance une analyse
complete, on la compare a la precedente pour savoir tout ce qui a change, puis on adapte les scripts.
1. **Un seul fichier** : le joueur execute `yslem_GameAnalyzer.lua` dans le jeu, clique Etape 1 (structure), colle dans le chat, puis Etape 2 (contenu : donnees des modules
   + tous les textes), colle. Le texte copie commence par un message pour Claude ; il contient l'inventaire COMPLET (noms et textes seulement, rien n'est modifie, aucun reseau ;
   les modules `RS/Data` sont lus avec `require`, deja charges par le jeu). Ancienne voie : bloc `yslem GameScan` + bouton "snap".
2. Sauver chaque etape dans `docs/scans/<Jeu>_<AAAA-MM-JJ>_etape1.txt` et `_etape2.txt` (la premiere analyse devient la reference du depot).
3. `python3 tools/gamediff.py docs/scans/<ancien>.txt docs/scans/<nouveau>.txt` : supprime / deplace / ajoute / modifie + IMPACT sur nos scripts
   (fichiers:lignes qui citent un nom touche ; quels scripts pour quel jeu : `docs/scans/games.json`).
4. Adapter les scripts avec les noms du NOUVEL inventaire uniquement, verifier (compile + globales + maquette), mettre a jour "Notes jeu" ci-dessous.
5. Commit + push, renvoyer le(s) fichier(s) modifie(s). (Ancienne voie seulement : RETIRER le bloc GameScan et le bouton du projet.)
Tests : `python3 tools/mock/build_scan.py && /tmp/luau_bin/luau tools/mock/scan_all.lua` et `python3 tools/mock/test_gamediff.py` et `python3 tools/mock/build_analyzer.py && /tmp/luau_bin/luau tools/mock/analyzer_all.lua`.

### Notes Game update (Steal An Egg, premier scan reel)
- Le scan est bruite par les objets dynamiques : `AreaEggSlotsClient`, `ClientRenderedAssets`, `PlacedEggRenders`, `__ClientTreadmillRenders`, `Transient`
  (noms = identifiants hex) -> normalises en `<id>` et non parcourus ; un simple changement de NOMBRE (oeufs, boutons generes, prompts) n'est pas un changement.
- Format d'inventaire `#SNAPSHOT v3` (lignes `KIND|classe|chemin|extra|n` ; kinds : REMOTE SCRIPT LIBRARY VALUE SCREEN BUTTON PROMPT WORLD STAT ATTR TEXT DATA). `tools/gamediff.py` compare deux fichiers de meme etape.
- Vu dans le jeu (noms seulement, a NE PAS utiliser) : `ContentCreatorsAdminPanel`, `RE/StaffConsole/*`, `CmdrClient/Commands/*` = outils staff/admin.

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
Exception voulue par yslem (stats Sources Hub) : SourcesHub.lua fait un POST a sens unique vers `sourceshub-stats.vercel.app/api/ping` (uid, pseudo, jeu, nom du script, version), visible et desactivable dans Config, reponse ignoree, aucun code charge. Aucun autre appel reseau. Exception voulue par yslem (key system) : le module `yslem_KeyGate.lua` fait UNE requete HTTPS vers le bot, `POST /v1/verify`,
avec 4 champs (cle, UserId, nom du script, version). Pas de cle en dur, pas de code distant, aucun autre appel reseau. La
revocation d'une cle par le bot arrete le script de ce joueur : c'est un controle de licence visible et documente
(`docs/KEY_API.md`), pas un kill-switch cache.

## Notes jeu : Steal An Egg
- Ligne de separation `World.Areas.SeparationLine` (X ~ 552) : gauche = base/zone sure, droite = gardes.
- Livraison confirmee par `RE/EggWorld/FieldEggRedeemVerdict`; portage via `EggState.CarryChanged`
  (+ verification des soudures `HeldByMe`). Rembobinage serveur : `RE/RigSync/Refresh` avec `Action = "Relocate"`.
- Le hub est protege par le bouclier "Humanoid Swap" (copie de l'Humanoid) : sans lui on meurt au moment du tp.
- Vitesse de marche reelle = min(Humanoid.WalkSpeed, vitesse issue de leaderstats.Speed via TreadmillUtil).
- **Scan complet 2026-10-10** (reference : `docs/scans/Steal-An-Egg_2026-10-10_etape1.txt` structure, `_etape2.txt` contenu ; premiere analyse = base, pas de diff possible).
  Zones (`RS/Data/Areas/Configs`, 13) : Forest, Desert, Snow, Lake, Jungle, Volcano, Prehistoric, Cosmic, Abyss Ocean, Cherry Blossom, Light Dark (affiche "Angels & Demons"),
  Titan Temple, **Enchanted Forest** (ProgressionOrder 13, batte `EnchantedHammer`, ouverte par le flag `LiveEventFlag_EnchantedForestOpen`). 8 pets par zone (DropTable).
  Raretes (`RS/Data/Rarity/Configs`, 17) : Common, Uncommon, SuperRare, Rare, Epic, Legendary, Mythic, Rainbow, BrainrotGod ("Squishy God"), Cosmic, Secret, Eternal, Limited,
  Divine, Transcendent, Titan, LightDark ("Light & Dark", rang 12). Le rang est dans `Rarity.Rank` (pas de RarityNumber).
  Flags d'evenements : attributs `WS/LiveEventFlag_<Nom>` (EnchantedForestOpen, LightDarkReveal, RiftOpen, StarHandlerOpen) + `Event_ButterflyBloom`, `ScrambleOutbreakActive`.
  Evenements/modules : Rift (3 bannieres Riftborn/Riftbeasts/Shattered Rift), ScrambleTradeIn (labo, bannieres Biohazard/Experimental/Unstable DNA), BossEvent (Abyss Overlord, toutes les 1800 s),
  BeanstalkEvent, Sakura (Great Bloom toutes les 1800 s, monnaie SakuraCrystals), LightVsDarkness, MonsterParasite, DragonEgg, CaptureTheEgg, RaceRally/MountRace, Wisp/Enchanted Forest (WispQuests),
  BanjoCricket, SammyEvent, oeufs limites (Extinction, Luminous), Monster/Brainrot/Luminous Egg.
  Remotes de fin de revelation : `RF/Fusery/FinishReveal` et `RF/ScrambleTradeIn/AskFinishReveal` (les scripts disaient "Finishaide" : corrige).
  Staff/admin vus (NE PAS utiliser) : `ContentCreatorsAdminPanel`, `AdminAbuseEgg`, `Flags/StaffTagFlags`, Cmdr, `RE/StaffConsole/*`.
  Limites du scan : plusieurs modules `Flags/*` renvoient "ERR Requested module experienced an error" au require ; les valeurs longues sont tronquees avec "...".
  **Mode course (Race Rally / Mount Race)** : actif en direct (`RaceRallyFlags.ContentEnabled` vaut true alors que le defaut est false). Monnaie `RaceTokens` (affichee "Trophies"), `DefaultRacer` Ostrich, `EventName` RaceRally,
  produit DoubleTrophies (x2). Flags : JoinSeconds 60, Laps 3, NitroSuccessPercent 10 ; MountRaceFlags : AccelSeconds 3, AirFallSeconds 2.5, AllowLateJoin true, BoostPadMultiplier 1.6, BoostPadSeconds 1.2.
  Phases `MountRace.Phase` : Countdown, Joining, Racing, Results. Attributs joueur : RaceId, RaceLap, RacePlace, RaceFinishPlace, RaceFinishTime, RaceGridFrame ; attributs RaceRallyJoinEndsAt / RaceRallyRunning ; bots `WS/RaceEventBotsEnabled`, `RaceEventBotCount`.
  Tags de piste : RaceBoostPad, RaceJump, RaceLoop, RacePowerUpSpawn, RaceSlowPad ; dossier monde `WS/RaceTrack`. Power-ups (`RS/Data/RacePowerUps`, 1 usage, touche E) : Drilla Ambush, Egg Splatter, Dr Scramble Pod, Serum (liste tronquee dans le scan).
  Racers : Bird, Cheetah, Lizard, Ostrich, Seahorse, Snail. Jalons Wins1/3/10/12/15/17/19/21/24/27 (oeufs Race Bird/Race Cheetah/Engine Snail + racers + items Cosmic/Eternal/Secret). Boutique : CashBooster, DoubleTrophies, MutationToken, RacingBat, SpeedBoost, TreadmillBoost.
  Remotes : `RF/RaceRally/{AskBuy, AskClaimMilestone, AskEquipRacer}`, `RE/MountRace/{AskLeave, OutroFinished, PowerUpMoment, PowerUp}`. UI : `RaceRallyUI`, `MountRaceUI`, `MountRaceBoardUI`, `RacePowerUpUI`, bouton HUD `RaceRallyButton`, `Handbrake` ("DRIFT"), `LeaveButton` ("RETURN HOME").
  Admin (NE PAS utiliser) : `CmdrClient/Commands/raceRally`. Evenements voisins : TrexRun (remotes Herd/Trampled/Wave/FetchHerd, TrexRunFlags) et RedLightGreenLight (flags). Teaser "MOUNTS... NEXT WEEK" dans `GUI/CutsceneUI/Mounts`. Nos hubs ne gerent pas la course (rien de casse).

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
