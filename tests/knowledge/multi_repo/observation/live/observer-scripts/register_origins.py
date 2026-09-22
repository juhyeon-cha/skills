from pathlib import Path
import json,subprocess,time
root=Path('/private/tmp/stage5-work/live');trace=[];records={}
for flow in ['code-first','document-first']:
 base=root/flow;records[flow]={}
 for name in ['origin','user-origin']:
  argv=['/private/tmp/knowledge-contract-venv/bin/python','/Users/juhyeon/.harness-workspace/skills/.claude/worktrees/skills-388/plugins/toolkit/skills/refresh-knowledge/scripts/knowledge.py','--project',str(base/'producer-project'),'intake','--input',str(base/(name+'-input.json'))]
  t=time.monotonic();p=subprocess.run(argv,capture_output=True,text=True);trace.append({'argv':argv,'elapsed_seconds':time.monotonic()-t,'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr});assert p.returncode==0,p.stderr
  records[flow][name]=json.loads(p.stdout)
(root/'origin-trace.json').write_text(json.dumps(trace,ensure_ascii=False,indent=2));(root/'origins.json').write_text(json.dumps(records,ensure_ascii=False,indent=2));print(json.dumps(records,ensure_ascii=False))
