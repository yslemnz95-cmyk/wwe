# Test de yslem_GameUpdate_v2.lua : python3 tools/mock/build_update.py && /tmp/luau_bin/luau tools/mock/update_all.lua
import os
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
env = open(os.path.join(here, 'env.lua')).read().rstrip().rsplit('\n', 1)[0]
run = open(os.path.join(here, 'update_run.lua')).read()
src = open(os.path.join(root, 'yslem_GameUpdate_v2.lua'), encoding='utf-8').read()
open(os.path.join(here, 'update_all.lua'), 'w').write(env + '\nlocal loadUpdate = function()\n' + src + '\nend\n' + run)
