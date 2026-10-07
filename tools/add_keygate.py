# Injecte yslem_KeyGate.lua dans yslemEgg_COMPLETE.lua (apres "local lib = {...}", avant la construction de l'UI).
# usage: python3 tools/add_keygate.py --api https://URL_DU_BOT --invite https://discord.gg/XXXX [--channel "#key"] [--out fichier.lua]
# Sans --out, le script est modifie en place (a faire seulement quand le bot est en ligne).
import argparse, os, re, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument('--api', required=True)
ap.add_argument('--invite', required=True)
ap.add_argument('--channel', default='#key')
ap.add_argument('--target', default=os.path.join(root, 'yslemEgg_COMPLETE.lua'))
ap.add_argument('--out')
ap.add_argument('--name', default='yslemEgg')
a = ap.parse_args()

if not a.api.startswith('https://'):
    sys.exit('--api doit commencer par https://')

mod = open(os.path.join(root, 'yslem_KeyGate.lua')).read()
s = mod.index('-- ===== yslem KeyGate START =====')
e = mod.index('-- ===== yslem KeyGate END =====') + len('-- ===== yslem KeyGate END =====')
block = mod[s:e]
for old, new in (('https://REPLACE_ME', a.api.rstrip('/')),
                 ('https://discord.gg/REPLACE_ME', a.invite),
                 ('CHANNEL = "#key"', 'CHANNEL = "%s"' % a.channel)):
    if old not in block:
        sys.exit('motif introuvable dans le module : ' + old)
    block = block.replace(old, new, 1)
if 'REPLACE_ME' in block:
    sys.exit('il reste un REPLACE_ME dans le bloc')

src = open(a.target).read()
if 'yslem KeyGate START' in src:
    sys.exit('KeyGate deja present dans ' + a.target)
standalone = 'Standalone' in os.path.basename(a.target)
if standalone:
    anchor = 'local localPlayer = Players.LocalPlayer\n'
else:
    anchor = 'local lib = {handles = {}, states = {}}\n'
if src.count(anchor) != 1:
    sys.exit('ancre introuvable ou ambigue : ' + anchor.strip())

if standalone:
    call = '''
local KeyGateStop = function() end
if not KeyGate.require("%s", {onInvalid = function() KeyGateStop() end}) then return end
''' % a.name
    closeblk = 'close.MouseButton1Click:Connect(function()\n\tstate.Cancel = true\n\tfpsOff()\n\tshieldStop()\n\tshineConnection:Disconnect()\n\tgui:Destroy()\nend)\n'
    if src.count(closeblk) != 1:
        sys.exit('bloc de fermeture introuvable ou ambigu')
    hook = 'KeyGateStop = function()\n\tpcall(function() state.Cancel = true; fpsOff(); shieldStop(); shineConnection:Disconnect(); gui:Destroy() end)\nend\n'
    src = src.replace(closeblk, closeblk + hook, 1)
else:
    call = '''
-- Cle personnelle verifiee par le bot (seul acces reseau du script : POST /v1/verify, aucun code distant)
if not KeyGate.require("%s", {onInvalid = function()
	pcall(function() if lib.OnUnload then lib.OnUnload() end end)
	pcall(function() local o = game:GetService("CoreGui"):FindFirstChild("MoonEggGui"); if o then o:Destroy() end end)
	pcall(function() local o = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("MoonEggGui"); if o then o:Destroy() end end)
	pcall(function() if typeof(gethui) == "function" then local o = gethui():FindFirstChild("MoonEggGui"); if o then o:Destroy() end end end)
end}) then return end
''' % a.name
src = src.replace(anchor, anchor + '\n' + block + '\n' + call, 1)
out = a.out or a.target
open(out, 'w').write(src)
print('ecrit :', out)
