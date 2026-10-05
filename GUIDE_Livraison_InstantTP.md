# Guide complet : la logique de livraison (Instant TP, Anti Guard, Delivery Stop, Normal)

Ce guide décrit ce que fait réellement `yslemEgg_COMPLETE.lua`. Les numéros de ligne sont approximatifs (le fichier bouge).
Rien ici n'a été testé en jeu par moi : c'est la lecture du code, pas un test.

---

## 0. Le problème que tout ça résout

Quand on vole un œuf, il faut le ramener à la base. Entre l'œuf et la base il y a :

- **la ligne de séparation** (`workspace.World.Areas.SeparationLine`, X ≈ 552) : à gauche de la ligne = zone sûre (base), à droite = terrain des gardes ;
- **les gardes** qui patrouillent et frappent le joueur qui porte un œuf (le joueur tombe, l'œuf tombe) ;
- **le serveur**, qui vérifie la position du joueur (anti-téléportation) et vous "rembobine" (message `RE/RigSync/Refresh` avec `Action = "Relocate"`) si vous avancez trop vite ou trop loin d'un coup.

Toute la logique de livraison est donc un compromis entre **vitesse** (arriver avant le garde) et **crédibilité** (ne pas se faire rembobiner).

Le plafond de vitesse du hub : **115 %** (`tbl4.SafeCarry.Cap(ratio) = math.min(ratio, 1.15)`). Le seul chiffre au-dessus est `HopRatio = 1.515`, mais c'est une **distance** de saut (en studs), pas une vitesse.

---

## 1. Les quatre modes (`tbl4.Method`)

Choisis par `tbl4.Method.Apply(name)`. Noms : `Normal`, `Instant TP`, `Delivery Stop`.

| Réglage posé par `Apply` | Normal | Instant TP | Delivery Stop |
|---|---|---|---|
| `sc.Teleport` | false | **true** | false |
| `sc.StopMode` | false | false | **true** |
| `sc.LineDrop` | false | true | true |
| `sc.HopStop` (distance devant la ligne) | 48 | **14** | 48 |
| Anti Guard | inchangé | **éteint** (version Chilli-style) | éteint |
| `SpeedJitter` | 0,08 | 0 | 0 |

`LineDrop` veut dire "méthode de la ligne" : on ne marche pas tout le trajet, on saute jusqu'à la ligne, on pose l'œuf, on le reprend, on franchit. `Teleport` et `StopMode` sont les deux variantes.

---

## 2. Normal : `tbl4.SafeCarry.Home`

Le mode "humain". Il marche (ou plutôt glisse en vitesse imposée) de l'endroit où on a pris l'œuf jusqu'à la base.

Étapes :
1. `stealHome()` donne le point d'arrivée (le podium `GearGiver_Slap/Podium` + un offset, sinon repli `(528.7, 70.57, -364.11)`).
2. `safeCarry.Plan(...)` calcule la vitesse de portage : `WalkSpeed × Cap(CarryRatio) × Mult`. `Mult` est le `SpeedMultiplier` de l'œuf porté (un gros œuf ralentit). `Plan` renvoie aussi si le garde de la zone est plus rapide que nous (`PlanOk`).
3. `safeCarry.NewHuman(true)` : un petit "simulateur d'humain" (variation de vitesse `Factor`, couloir `Lane`, pauses, sauts). C'est lui qui fait ralentir et zigzaguer le personnage. Dans le mode Instant TP sans Anti Guard on le **contourne** (facteur forcé à 1, couloir 0).
4. Le point de contrôle : on va d'abord à `X = ligne − 7` (sept pas au-delà de la ligne), puis seulement à la base. Raison : le serveur valide la livraison quand on est franchement du côté sûr.
5. Boucle : à chaque `Heartbeat`, on pose directement `AssemblyLinearVelocity` vers la cible, plafonnée par `min(vitesse, distance/0,05)` (pour ne pas dépasser la cible).
6. Si l'œuf tombe (le garde a frappé) : `slicedfn50` (suivre l'œuf et le reprendre, voir §6) puis on reprend la course.

---

## 3. Instant TP : `tbl4.SafeCarry.LineDropHome` (aussi appelé par `InstantHome`)

C'est la méthode "Instant Steal" de Chilli Hub, adaptée. Idée : **ne jamais traverser le terrain des gardes à pied**.

### 3.1 Phase 1 : les sauts ("hops")
- Distance d'un saut : `max(WalkSpeed × HopRatio, 40)` studs (HopRatio 1,515).
- À chaque saut : `root.CFrame = CFrame.new(x2, hauteur, lane)`. La hauteur est `Y de départ + HopLift (42)` : on reste **en l'air** au-dessus des gardes.
- On attend `HopGap` (0,1 s par défaut, réduit à ~0,06 s en Instant TP sans Anti Guard) entre deux sauts : c'est la cadence que le serveur tolère.
- Détection d'échec : après chaque pause, on regarde si le serveur nous a rembobiné (`flag3` mis par le message Relocate, `Analyzer.ImpulseAt`, vitesse > 150, ou le corps à plus de 10 studs derrière la cible). Si oui : `hopRetries` (jusqu'à 6 essais).
- Si l'œuf est lâché par le serveur pendant les sauts : `tbl4.SafeCarry.Regrab` le reprend tout de suite (téléportation dessus si > 40 studs, course sinon) et le saut reprend de là.

### 3.2 Phase 2 : l'atterrissage devant la ligne
- Cible : `(X ligne + HopStop, Y ligne + 3,35, lane)`. En Instant TP `HopStop = 14`.
- Un **raycast** vers le bas trouve le vrai sol (on évite l'eau et le vide).
- On se pose (`slicedfn59`), on attend `0,08 s`, on vérifie que le serveur ne nous a pas ramené trop loin (`landed.X − cible.X > 12`) et on recommence jusqu'à 3 fois.
- Règle "jamais en arrière" : si on est déjà plus près de la ligne que la cible, on reste (sinon on s'éloignerait).

### 3.3 Phase 3 : déposer / reprendre
- Après `DropDelay` (0,05 s en Instant TP), `EggState.DropFieldEgg("PlayerRequest")` : on lâche l'œuf **exprès**.
- Pourquoi ? L'œuf au sol n'est plus "porté par un joueur" ; le garde ne le poursuit plus, et on le reprend à côté, ce qui remet un état de portage propre juste devant la ligne.
- Reprise : `slicedfn50(arg, uid)` (état machine "suivre l'œuf et le reprendre", voir §6). En Instant TP il est réglé plus agressif : portée 30, intervalle 0,03 s, rayon de prompt 10, plus `task.spawn(slicedfn28, uid)` à chaque `fireproximityprompt`.

### 3.4 Phase 4 : la zone sûre
- **Sans Anti Guard** (la version actuelle) : dès que l'œuf est repris, on appelle `tbl4.SafeCarry.Home` (donc le trajet du mode Normal : point de contrôle à `X ligne − 7`, puis base), avec la course en ligne droite sans ralentissements et sans temps de réaction (`CarryReact` ignoré).
- Sinon (ancien comportement) : `crossLine` = même chose mais depuis la boucle de la ligne.

### 3.5 Les extras propres à Instant TP
- **Caméra figée** pendant les sauts (`CameraType = Scriptable` + `CFrame` figé), relâchée à l'atterrissage (`slicedfn55`). Évite que la caméra "danse" avec les téléportations.
- **FPS cap 60/30** (`tbl4.CarryCap.On("pulse")`) : alterne `setfpscap(60)` / `setfpscap(30)` toutes les 0,15 s dès le début du vol jusqu'à la fin. Idée : les gros écarts de framerate rendent le moment où le serveur compare les positions moins prévisible ; c'est de l'empirique, pas une garantie. Un token `cap.Gen` évite que deux boucles se battent. Auto-coupure après 60 s.
- **Clones** (`tbl4.PostClone`, `tbl4.DropClone`, `tbl4.ClearClones`) : une copie visuelle du personnage reste à l'endroit où l'œuf a été pris pendant le vol ; elle est supprimée à l'arrivée.

### 3.6 Les réglages d'Instant TP sans Anti Guard (les "accélérations")
Dans le wrapper de livraison (`slicedfn54`, après `tbl4.Tune.Apply()`) :
- `HopGap = max(0,05 ; HopGap × 0,6)`
- `DirectMargin = clamp(…, 0,6 ; 0,9)` (la marge de temps avant de franchir la ligne ; plus bas = plus rapide mais plus risqué). Elle ne descend pas sous 0,6 après chaque succès, et **remonte de 0,3 (jusqu'à 3) après un rejet**.
- Autres : dépose 0,05 s, atterrissage 0,08 s, contrôle de livraison 0,03 s, pas de `CarryReact`.

---

## 4. Delivery Stop : `LineDropHome` avec `StopMode`

À ne pas toucher (il marche). C'est la même méthode de la ligne, mais avec des **arrêts** sur le trajet :
- `Stops = 3` (réglable) : sur le trajet des sauts, on s'arrête `Stops − 1` fois, on **dépose** l'œuf, on le **reprend**, puis on repart ("Delivery step 2/3: taking the egg back").
- Chaque arrêt fonctionne si la surface sous nous est solide (raycast). Sinon (eau/vide) on fait seulement une courte pause de 0,3 s sans lâcher l'œuf.
- Si l'œuf retourne dans son nid (`record.State == "Slot"`), on arrête.
- Delivery Stop **éteint** Anti Guard (voir §5).
- Pas de caméra figée : le gel est désactivé quand `StopMode`.

---

## 5. Anti Guard (module à la fin du fichier)

Le principe original (Chilli) : au moment où on prend l'œuf, un **chemin de téléportations** envoie le personnage plusieurs fois vers la base puis le ramène au départ, pour que le garde "perde" sa cible. Les pas viennent de `chilliAntiGuard.Default = slicedfn20(25, 0, 0.05, 1.27, 1.52, 2.5)` :

- 25 étapes `To = "home"`, à `At = 0, 0.05, 0.10 … 1.20 s` ;
- 1 étape `To = "start"` à 1,27 s (retour au point de départ) ;
- `ReleaseAt = 1.52` s (fin) ; `BusyLimit = 2.5` s (garde-fou) ;
- `Disguise = true`, `Freeze = true`, `Limp = false`, `HopRandom = 0,085`, `HoldRandom = 0,395`.

Fonctions clés :
- `slicedfn38` : ajoute des variations aléatoires aux temps (`HopRandom`, `HoldRandom`, `StartRandom`).
- `slicedfn40` : la boucle d'exécution du chemin (`slicedfn43` attend, `slicedfn44` fait le déplacement avec un contrôle de décalage).
- `slicedfn42` / `Fire` : déclenchent la course quand on porte un œuf et que la fonction est activée.
- `slicedfn32` : fabrique le "profil actif" : en mode ligne (`LineDrop`), la destination devient "Next To Line" avec `Stay = true` (on retire l'étape `start`) et `LineOffset = 14`. En Instant TP, la séquence est de plus compressée de moitié (`At × 0,5`, `ReleaseAt = dernier + 0,1`, jitter réduit).
- Déguisement : copies du personnage (`slicedfn26`) pendant la séquence, 14 s de watchdog, `MoonLib.ReleaseCamera`, `tbl4.ClearClones` à l'arrivée.

Ce que fait **Chilli lui-même** (vérifié dans leur fichier déobfusqué) : dans la livraison, `if antiGuard.Enabled and not LineDrop` → **Anti Guard n'est jamais attendu en Instant TP ni en Delivery Stop**. Il ne sert qu'en Normal. C'est pour ça que la version "Chilli-style" (Instant TP sans Anti Guard) est plus cohérente.

Dans la livraison Normal avec Anti Guard (`deliverOnce`) :
1. attendre jusqu'à 1 s qu'Anti Guard démarre ("Waiting for Anti Guard to start") ;
2. attendre jusqu'à 30 s qu'il finisse ("Anti Guard is slipping past the guard") ;
3. si le garde a frappé, attendre qu'on puisse bouger ;
4. attendre 0,3 s de stabilisation ("Anti Guard done, getting ready") puis monter à `Y base + Height (70)` ;
5. si l'œuf est resté au sol : `slicedfn50` pour le reprendre, puis `Home`.

---

## 6. Prendre / reprendre un œuf

| Fonction | Rôle |
|---|---|
| `slicedfn28(uid)` | Demande de prise : `EggState.CarryFieldEgg(uid)` |
| `slicedfn47(uid)` | Position d'un œuf posé dans le monde (`workspace[uid]` ou `AreaEggSlotsClient`) |
| `slicedfn48(uid)` | Position de l'œuf via `RF/EggWorld/AskFieldEggSnapshot` (record.BottomCFrame) |
| `slicedfn50(arg, uid)` | Machine à états : suit l'œuf (vitesse vers sa position, plafonnée), tire `fireproximityprompt` + `CarryFieldEgg`, jusqu'à ce qu'on le porte |
| `slicedfn58()` | Record de l'œuf porté (pour savoir s'il est retourné dans son nid : `State == "Slot"`) |
| `tbl4.Steal.WrongEgg(uid)` | Si on porte un autre œuf que celui voulu, le lâche |
| `tbl4.Steal.HeldByMe()` | Vérifie par les soudures (Weld/Joint) que l'œuf est vraiment attaché à notre personnage |
| `tbl4.SafeCarry.Regrab(arg, uid, force)` | Reprise rapide : téléporte sur l'œuf s'il est à > 40 studs, sinon course, puis `slicedfn50` |

États d'un œuf (`record.State`) : `Slot` (dans son emplacement), `Dropped` (au sol), `Carried` (porté), `Claimed`.

La détection de portage : `EggState.CarryChanged` (signal du jeu avec `IsCarrying`, `Uid`, `SpeedMultiplier`), doublée par `HeldByMe` toutes les 0,2 s (si l'œuf n'est plus attaché depuis > 0,8 s, on considère qu'il est tombé : `GuessedDrop`).

La livraison est confirmée par `RE/EggWorld/FieldEggRedeemVerdict` (`SafeCarry.LastDelivered = os.clock()`).

---

## 7. L'apprentissage automatique (`tbl4.Analyzer`, `tbl4.Tune`)

- `Analyzer` enregistre chaque tentative : mode, île (`Island()`), succès/échec, événements (`hop`, `pullback`, `nest`, `tune`).
- `Tune.Apply()` (au début de chaque livraison) copie les valeurs apprises (`HopRatio`, `HopGap`, `Ratio`) dans `SafeCarry`.
- `Tune.Learn(mode, island, ok, rejected)` : après un succès, il réduit un peu `HopGap` (`−0,01`, mais pas sous la valeur par défaut) ; après un rejet serveur il l'augmente (`+0,02`, max 0,2).
- Le wrapper apprend aussi `DirectMargin` (voir §3.6).

---

## 8. Les fonctions de mouvement bas niveau

- `tbl4.Root()` : `HumanoidRootPart` du personnage.
- `tbl4.WalkSpeed()` : vitesse de marche réelle (Humanoid + `leaderstats.Speed` via `TreadmillUtil.SpeedPowerToWalkSpeed`).
- `slicedfn38(pos)` : téléporte tout le personnage (`PivotTo` + remise à zéro des vitesses de chaque pièce).
- `slicedfn57(cible, vitesse, timeout, stopFn)` (dans LineDropHome) : course en ligne droite par vitesse imposée.
- `tbl4.SafeCarry.Cap(ratio)` : plafond de 115 %.
- `tbl4.SafeCarry.Avoid(pos, cible)` : évite les gardes sur le chemin (utilisé en Normal).

---

## 9. Pourquoi le serveur "rembobine" (les causes à connaître)

1. **Trop loin d'un coup** : un saut plus grand que la distance de vitesse tolérée. D'où `HopRatio` fixe (1,515) et la détection `pulledBack`.
2. **Trop vite entre deux sauts** : `HopGap` trop petit ; le serveur n'a pas eu le temps de valider la position précédente.
3. **Marge directe trop courte** (`DirectMargin`) : on franchit la ligne trop tôt par rapport au temps de trajet "autorisé".
4. **Retour en arrière** : si on se téléporte *derrière* une position déjà validée (d'où la règle "jamais en arrière" à l'atterrissage).
5. **Œuf lâché** par le garde : l'état de portage est rompu, il faut reprendre l'œuf avant de continuer (sinon la livraison n'est pas comptée).

Le script réagit à ces cas par les retries, l'apprentissage de `HopGap` / `DirectMargin`, et la reprise de l'œuf.

---

## 10. Sécurité (ce qui est volontairement absent)

Pas de `loadstring`, pas de `HttpGet`, pas de WebSocket, pas de webhook, pas de `queue_on_teleport` (neutralisé à `nil` en tête de fichier), pas de panneaux d'administration. Dans le fichier principal il reste, hérité de la source, un bloc qui chercherait des connexions avec `getconnections` : `getconnections` est mis à `nil` en tête de fichier, donc ce bloc ne fait rien (il est protégé par `pcall`).

---

## 11. Le standalone (`yslemEgg_InstantTP_Standalone.lua`)

Reprend **uniquement** la logique Instant TP sans Anti Guard (sauts, atterrissage devant la ligne, dépose/reprise, zone sûre, reprise en route, caméra figée, FPS 60/30), avec un petit panneau doré à traits (strokes) : liste des œufs du terrain avec **image**, **nom** et **valeur ($/s)**, tri par valeur, bouton **Steal Selected** (devient **Cancel** pendant le vol).
La valeur est calculée avec la même formule que le hub : `EarningRate × facteur d'échelle × multiplicateur de mutation`.
Pas de Delivery Stop, pas d'Anti Guard, pas de réglages cachés.

Limites : il n'est pas testé en jeu, et il n'a pas la mémoire d'apprentissage (`Tune` / `Analyzer`) du hub : les valeurs sont fixes (HopGap 0,06, atterrissage 0,08, etc.).
