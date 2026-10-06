---
name: yslemstyle
description: Style d'interface "yslemStyle" (contours et textes en degrade anime, theme noir, arrondi, petite UI). A utiliser pour toute creation ou refonte d'UI Roblox de yslem, y compris recoloree (ex. rouge/noir pour SHIN HUB).
---

# yslemStyle

- Fond noir, formes arrondies (UICorner 8-14), UI petite, boutons assez grands pour le tactile.
- Contours : `UIStroke` (ApplyStrokeMode Border) + `UIGradient` rotation 45. Textes : `UIGradient` sur le texte.
- Degrade a bandes : `bands(a, b)` = ColorSequence 5 points (0=a, .25=b, .5=a, .75=b, 1=a). Palette de base blanc/argent/acier ;
  pour une autre marque, remplacer par ses couleurs (ex. rouge vif / rouge moyen / rouge fonce).
- Animation : une seule boucle Heartbeat, une image sur deux ; `rot = (os.clock()*72) % 360`; contours `45 + rot`, textes `rot`.
  Garder la liste des degrades vivants (`living`) et les faire tourner tous.
- Barre de titre vive (couleur de marque claire) avec titre NOIR.
- Aucune info interne affichee (FPS cap, vitesses, noms de remotes).
- Bouton principal GO <-> STOP ; STOP doit toujours marcher (drapeau d'arret remis a zero seulement au debut d'un trajet).
- Fenetre deplacable via UserInputService (InputChanged), pas via le seul InputChanged de la barre. Vue reduite (mini) disponible.
- Textes de l'UI dans la langue demandee (SHIN HUB : tout en anglais).
- Reference de code : `livingStroke`, `livingText`, `darkButton` dans `yslempet_EggTP.lua` ; version rouge/noir dans `friend/ShinEggFarm_yslem.lua`.
