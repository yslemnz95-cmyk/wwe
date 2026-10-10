# Test de yslem_GameAnalyzer.lua : python3 tools/mock/build_analyzer.py && /tmp/luau_bin/luau tools/mock/analyzer_all.lua
import os
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
env = open(os.path.join(here, 'env.lua')).read().rstrip().rsplit('\n', 1)[0]
run = open(os.path.join(here, 'analyzer_run.lua')).read()
src = open(os.path.join(root, 'yslem_GameAnalyzer.lua'), encoding='utf-8').read()
open(os.path.join(here, 'analyzer_all.lua'), 'w').write(env + '\nlocal loadAnalyzer = function()\n' + src + '\nend\n' + run)
