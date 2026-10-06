# Smoke test of the LOGIC of friend/ShinEggFarm_yslem.lua (everything before the UI block).
# usage: python3 tools/mock/build_friend.py [normal|remote|stop|lose|nodrop] [stop_at_seconds]
#        /tmp/luau_bin/luau tools/mock/friend_all.lua
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
env = open(os.path.join(here, 'env.lua')).read().rstrip().rsplit('\n', 1)[0]
run = open(os.path.join(here, 'friend_run.lua')).read().split('\n', 1)[1]
proj = open(os.path.join(root, 'friend', 'ShinEggFarm_yslem.lua')).read()
cut = proj.index('-- interface: yslemStyle')
cut = proj.rfind('-- ====', 0, cut)
logic = proj[:cut]
logic += '\nreturn {run = runSequence, stop = stopSequence, setStatus = function(f) statusSetter = f end, isRunning = function() return running end, setDip = function(v) autoDip = v end}\n'
scen = sys.argv[1] if len(sys.argv) > 1 else 'normal'
stop_at = sys.argv[2] if len(sys.argv) > 2 else '3'
open(os.path.join(here, 'friend_all.lua'), 'w').write('SCENARIO="' + scen + '"\nSTOP_AT=' + stop_at + '\n' + env + '\nlocal projectFn = function(...)\n' + logic + '\nend\n' + run)
