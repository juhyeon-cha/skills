import sys,pathlib,subprocess,json,time,hashlib,argparse
root=pathlib.Path('/Users/juhyeon/.harness-workspace/skills/.claude/worktrees/skills-388'); out=root/'tests/knowledge/multi_repo/observation'; base=pathlib.Path('/private/tmp/stage5-work/m0/replay-2'); base.mkdir()
sys.path.insert(0,str(root/'plugins/toolkit/skills/refresh-knowledge/scripts'))
from cli import capture
from impact import bind,impact
import project_service
plan=json.loads((out/'frozen-plan.json').read_text()); hashes=json.loads((out/'freeze-hashes.json').read_text()); assert all(hashlib.sha256((out/n).read_bytes()).hexdigest()==h for n,h in hashes.items())
trace=[]
def run(args,cwd=None):
 t=time.monotonic(); p=subprocess.run(args,cwd=cwd,text=True,capture_output=True); trace.append({'argv':args,'cwd':str(cwd) if cwd else None,'rc':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'seconds':time.monotonic()-t}); return p
repos={}; before={}; bindings={}; projects={}
for name in ['producer','consumer']:
 repo=base/name; repo.mkdir(); docs=base/(name+'-docs'); docs.mkdir(); (docs/'contract.md').write_text('Current field: amount.\n'); (repo/'app.py').write_text(plan['source_inputs'][name+'_v1'])
 for args in [['git','init'],['git','add','app.py'],['git','-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-m','v1']]: assert run(args,repo).returncode==0
 head=run(['git','rev-parse','HEAD'],repo).stdout.strip(); repos[name]=repo
 before[name]=capture(repo,'svc-'+name,head,['app.py']); spec={'documents':[{'path':'contract.md','claims':[{'id':'field','text':'Current field: amount.','evidence':['app.py']}]}]}; bindings[name]=bind(spec,before[name],docs)
 specpath=base/(name+'-spec.json'); specpath.write_text(json.dumps(spec)); project=base/(name+'-project'); projects[name]=project
 args=argparse.Namespace(repo=repo,docs=docs,repository='svc-'+name,baseline=head,path=['app.py'],spec=specpath,audience='Callers',purpose='Read current contract')
 project_service.initialize(args,project)
producer=repos['producer']; (producer/'app.py').write_text(plan['source_inputs']['producer_v2']); assert run(['git','add','app.py'],producer).returncode==0; assert run(['git','-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-m','v2'],producer).returncode==0
head=run(['git','rev-parse','HEAD'],producer).stdout.strip(); after=capture(producer,'svc-producer',head,['app.py']); queue=impact(bindings['producer'],before['producer'],after,base/'producer-docs',producer)
status=project_service.status(argparse.Namespace(run=None,deep=True),projects['producer'])
code="import runpy; p=runpy.run_path(%r); c=runpy.run_path(%r); print(c['parse'](p['emit']()))"%(str(producer/'app.py'),str(repos['consumer']/'app.py'))
p=run([sys.executable,'-c',code]); assert p.returncode!=0 and 'KeyError' in p.stderr
errors={}
for name,repo in [('unavailable',base/'missing-repository'),('denied',base/'denied-source')]:
 try: capture(repo,'svc-consumer',before['consumer']['commit'],['app.py'])
 except Exception as e: errors[name]={'type':type(e).__name__,'message':str(e),'note':'missing path represents unavailable boundary; permission enforcement is not implemented by this probe'}
assert queue['candidates'] and status['baseline']==before['producer']['commit']
record={'source_head':run(['git','rev-parse','HEAD'],root).stdout.strip(),'python':sys.version,'before':before,'producer_after':after,'producer_impact':queue,'status_after_source_change':status,'integration':'failed with consumer KeyError amount','errors':errors,'observations':{'single_repo_impact':'Only producer document candidate; no consumer relationship surface','recorded_status':'Returns old baseline even after source HEAD advance; deep checks exported artifacts only','partial':'Producer v2 plus consumer v1 actually fails integration','permission':'No existing multi-repo permission projection; unavailable capture fails; permission scenario remains implementation work'},'trace':trace,'model_usage':None}
(out/'m0-observation.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n'); print('M0 observation saved; impact candidates',len(queue['candidates']),'integration rc',p.returncode)
