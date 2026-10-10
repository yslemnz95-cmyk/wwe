# Test de GameScan.snapshot : python3 tools/mock/build_scan.py && /tmp/luau_bin/luau tools/mock/scan_all.lua
import os
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
env = open(os.path.join(here, 'env.lua')).read().rstrip().rsplit('\n', 1)[0]
run = open(os.path.join(here, 'scan_run.lua')).read()
src = open(os.path.join(root, 'yslem_GameScan.lua'), encoding='utf-8').read()
open(os.path.join(here, 'scan_all.lua'), 'w').write(env + '\nlocal loadScan = function()\n' + src.replace('\nreturn GameScan', '\nreturn GameScan') + '\nend\n' + run)
