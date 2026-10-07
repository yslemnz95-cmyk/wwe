# Test du module yslem_KeyGate.lua contre un faux serveur /v1/verify.
# usage: python3 tools/mock/build_keygate.py && /tmp/luau_bin/luau tools/mock/keygate_all.lua
import os
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
env = open(os.path.join(here, 'env.lua')).read().rstrip().rsplit('\n', 1)[0]
run = open(os.path.join(here, 'keygate_run.lua')).read()
mod = open(os.path.join(root, 'yslem_KeyGate.lua')).read()
open(os.path.join(here, 'keygate_all.lua'), 'w').write(
    env + '\nlocal loadModule = function()\n' + mod + '\nend\n' + run)
