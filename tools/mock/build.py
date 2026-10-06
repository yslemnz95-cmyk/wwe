# Smoke test of yslempet_EggTP.lua under the plain luau interpreter with a small Roblox mock.
# usage: python3 tools/mock/build.py [normal|remote|click|vol|stop|lose] [stop_at_seconds]
#        /tmp/luau_bin/luau tools/mock/all.lua
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
env = open(os.path.join(here, 'env.lua')).read().rstrip().rsplit('\n', 1)[0]
run = open(os.path.join(here, 'run.lua')).read().split('\n', 1)[1]
proj = open(os.path.join(root, 'yslempet_EggTP.lua')).read()
run = run.replace('local code = io.open("/home/user/wwe/yslempet_EggTP.lua"):read("*a")\n', '').replace('local fn, err = load(code, "yslempet")\nassert(fn, err)\n', 'local fn = projectFn\n').replace('os.exit(1)', 'error("load failed")')
scen = sys.argv[1] if len(sys.argv) > 1 else 'normal'
stop_at = sys.argv[2] if len(sys.argv) > 2 else '3'
open(os.path.join(here, 'all.lua'), 'w').write('SCENARIO="' + scen + '"\nSTOP_AT=' + stop_at + '\n' + env + '\nlocal projectFn = function(...)\n' + proj + '\nend\n' + run)
