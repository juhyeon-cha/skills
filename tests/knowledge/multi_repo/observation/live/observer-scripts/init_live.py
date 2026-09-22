from pathlib import Path
import json,subprocess,hashlib,time
root=Path('/private/tmp/stage5-work/live')
script='/Users/juhyeon/.harness-workspace/skills/.claude/worktrees/skills-388/plugins/toolkit/skills/refresh-knowledge/scripts/knowledge.py'
python='/private/tmp/knowledge-contract-venv/bin/python'
packet=json.loads((root/'baseline-packet.json').read_text()); trace=[]
for r in packet['records']:
 repo=Path(r['repo_path']);docs=Path(r['docs_path']);base=repo.parent;name=repo.name
 assert subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()==r['revision']
 assert hashlib.sha256((repo/'app.py').read_bytes()).hexdigest()==r['source_sha256']
 assert hashlib.sha256((docs/'contract.md').read_bytes()).hexdigest()==r['document_sha256']
 argv=[python,script,'--project',r['project_path'],'init','--repo',str(repo),'--docs',str(docs),'--repository',r['repository_id'],'--baseline',r['revision'],'--path','app.py','--spec',str(base/(name+'-spec.json')),'--audience',packet['reader'],'--purpose',packet['purpose']]
 t=time.monotonic();p=subprocess.run(argv,text=True,capture_output=True);trace.append({'argv':argv,'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'elapsed_seconds':time.monotonic()-t});assert p.returncode==0,p.stderr
 argv=[python,script,'--project',r['project_path'],'status'];p=subprocess.run(argv,text=True,capture_output=True);trace.append({'argv':argv,'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr});assert p.returncode==0,p.stderr
 status=json.loads(p.stdout);assert status['baseline']==r['revision'];assert Path(status['settings']['repo'])==repo
(root/'init-trace.json').write_text(json.dumps(trace,ensure_ascii=False,indent=2))
print('Initialized and inspected',len(packet['records']),'projects after actual independent baseline review')
