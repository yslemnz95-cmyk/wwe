# Test de la couche UI (lib) d'un hub : python3 tools/mock/build_ui.py [fichier.lua] && /tmp/luau_bin/luau tools/mock/ui_all.lua
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
target = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, 'SourcesHub.lua')
env = open(os.path.join(here, 'env.lua')).read().rstrip().rsplit('\n', 1)[0]
run = open(os.path.join(here, 'ui_run.lua')).read()
src = open(target, encoding='utf-8').read()
cut = src.index('local SourcesLib = lib\n') + len('local SourcesLib = lib\n')
lib = src[:cut] + '\nreturn SourcesLib\n'
open(os.path.join(here, 'ui_all.lua'), 'w').write(env + '\nlocal loadLib = function()\n' + lib + '\nend\n' + run)
