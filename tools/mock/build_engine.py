# Test du moteur Instant TP (methode du standalone) integre dans SourcesHub.lua
# usage: python3 tools/mock/build_engine.py [SourcesHub.lua] && /tmp/luau_bin/luau tools/mock/engine_all.lua
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
target = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, 'SourcesHub.lua')
env = open(os.path.join(here, 'env.lua')).read().rstrip().rsplit('\n', 1)[0]
run = open(os.path.join(here, 'engine_run.lua')).read()
src = open(target, encoding='utf-8').read()
a = src.index('local InstantEngine = (function()')
b = src.index('tbl4.InstantEngine = InstantEngine')
engine = src[a:b].replace('local InstantEngine = (function()', 'InstantEngine = (function()', 1)
open(os.path.join(here, 'engine_all.lua'), 'w').write(env + '\n' + run.replace('--ENGINE--', engine))
