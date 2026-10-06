---
name: roblox-movement
description: Patrons de deplacement fiables pour les scripts Roblox de yslem (tp, vol par velocite, noclip, retour de controle, prise/drop/reprise confirmes, STOP). A utiliser avant d'ecrire ou modifier tout code de tp, vol ou livraison d'oeuf.
---

# Deplacement et prise/drop (retours du joueur)

- TP : `task.desynchronize()` + CFrame + vitesses a zero, reconfirmer sur ~3 frames si le serveur renvoie ailleurs. Jamais d'ecriture
  CFrame repetee sans verifier l'arrivee.
- Noclip : memoriser les `CanCollide` d'origine et les restaurer EXACTEMENT (tout remettre a true bloque les membres dans le sol).
- Apres tout trajet : `restoreControl` (noclip off, PlatformStand false, Move zero, GettingUp si Physics/Ragdoll/FallingDown/
  PlatformStanding, vitesses nulles). Le joueur ne doit jamais rester fige.
- Vol : velocite uniquement sur son propre personnage, vitesse = WalkSpeed x 7 (700%), 40 studs au-dessus, pose au sol par raycast.
  Aucune vitesse de livraison > 115% de la marche dans Steal An Egg.
- Pas de toucher simule (bloque le joystick) ; clic souris seulement en dernier recours.
- Prise/reprise : TOUJOURS confirmees (barre "Egg Will Break" et/ou compteur du panier), jamais "le prompt a disparu".
  Ne partir vers le plot qu'avec l'oeuf ; si perdu en vol, s'arreter, reprendre, repartir (3 essais).
- Retour au plot : se placer a l'EXTERIEUR (bord de la boite englobante + 20 studs), lacher (bouton DROP par firesignal -> remote
  BasketDrop -> Backspace -> clic), reprendre (confirme), puis voler jusque dans le plot. Plot trouve par proprietaire/nom, jamais le plus proche.
- STOP : drapeau remis a zero seulement au debut d'un nouveau job ; `task.defer(restoreControl)` ; jobs entoures de pcall.
- Positions : viser la position reelle (pivot / prompt) de l'oeuf, pas un attribut potentiellement perime.
