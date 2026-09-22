"""Ad-hoc S5 observer; all model reviews must come from actual host calls."""
from pathlib import Path
import subprocess,json,time,datetime,hashlib,sys
ROOT=Path('/private/tmp/stage5-work/live')
SCRIPTS=Path('/Users/juhyeon/.harness-workspace/skills/.claude/worktrees/skills-388/plugins/toolkit/skills/refresh-knowledge/scripts')
PYTHON='/private/tmp/knowledge-contract-venv/bin/python'
def save(path,value):
 with path.open('x') as f:json.dump(value,f,ensure_ascii=False,indent=2)
 return path
def run(argv,cwd=None,expect=0):
 started=datetime.datetime.now(datetime.timezone.utc).isoformat();t=time.monotonic();p=subprocess.run(list(map(str,argv)),cwd=cwd,capture_output=True,text=True)
 r={'argv':list(map(str,argv)),'cwd':str(cwd) if cwd else None,'started_at':started,'finished_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'elapsed_seconds':time.monotonic()-t,'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
 if len(argv)>1 and Path(str(argv[1])).is_file():r['script_sha256']=hashlib.sha256(Path(str(argv[1])).read_bytes()).hexdigest()
 with (ROOT/'commands.jsonl').open('a') as f:f.write(json.dumps(r,ensure_ascii=False)+'\n')
 if p.returncode!=expect:raise RuntimeError(json.dumps(r,ensure_ascii=False))
 return p.stdout

def knowledge(base,member,*args):return json.loads(run([PYTHON,SCRIPTS/'knowledge.py','--project',base/(member+'-project'),*args]))
def multi(base,action,value=None,principal='operator',label=None):
 args=[PYTHON,SCRIPTS/'multi_repo.py','--state',base/'multi-state','--host',base/'host.json','--principal',principal,action]
 if value is not None:
  inp=save(base/(label+'-input.json'),value);args+=['--input',inp]
 result=json.loads(run(args));save(base/(label+'-output.json'),result);return result

def initialize(flow):
 base=ROOT/flow;multi(base,'init',label='multi-init');goal=json.loads((base/'goal.json').read_text());multi(base,'goal',goal,label='goal-registration')
 for name,affected,kind in [('incorrect',['svc-producer'],goal['origin']['kind']),('correct',['svc-producer','svc-consumer'],goal['origin']['kind']),('user',['svc-producer','svc-consumer'],'user')]:
  origin=dict(goal['origin'])
  if kind=='user':
   ref=Path(json.loads((ROOT/'origins.json').read_text())[flow]['user-origin']['record']);origin.update(kind='user',intake={'path':str(ref),'sha256':hashlib.sha256(ref.read_bytes()).hexdigest()})
  multi(base,'predict',{'goal':'contract-total','origin':origin,'affected':affected,'rationale':'Intentional missing-consumer negative case' if name=='incorrect' else 'Independent pre-change impact response identifies producer writer and consumer field dependency.'},label='prediction-'+name)
 multi(base,'refresh',{'goal':'contract-total'},label='initial-refresh');multi(base,'query',{'goal':'contract-total'},label='initial-query')

def change(flow,member):
 base=ROOT/flow;repo=base/member
 original=(repo/'app.py').read_text();assert 'amount' in original
 (base/(member+'-app-before.py')).write_text(original)
 (repo/'app.py').write_text(original.replace('amount','total'))
 test=(repo/'check.py').read_text();(base/(member+'-check-before.py')).write_text(test);(repo/'check.py').write_text(test.replace('amount','total'))
 run(['git','add','app.py','check.py'],repo);run(['git','commit','-m','Implement local total contract'],repo)
 revision=run(['git','rev-parse','HEAD'],repo).strip();run([PYTHON,'-B','check.py'],repo)
 start=knowledge(base,member,'start','--rev',revision);save(base/(member+'-doc-start.json'),start)
 context=json.loads(Path(start['context']).read_text());text='생산자는 total 필드에 값 10을 담아 반환한다.' if member=='producer' else '소비자는 total 필드를 읽어 값을 반환한다.'
 decisions={'impact':context['impact']['id'],'claims':[{'path':'contract.md','id':'field','action':'replace','reason':'Approved isolated target implementation changes the exchanged field; describe pinned current source, not deployment.','text':text,'evidence':['app.py']}],'unlinked':[]}
 dec=save(base/(member+'-decisions.json'),decisions);prepared=knowledge(base,member,'prepare','--run',start['run'],'--decisions',dec);save(base/(member+'-doc-prepared.json'),prepared)
 print(json.dumps({'revision':revision,'prepared':prepared},ensure_ascii=False))

def apply_doc(flow,member,review):
 base=ROOT/flow;start=json.loads((base/(member+'-doc-start.json')).read_text())
 accepted=knowledge(base,member,'review','--run',start['run'],'--review',review);save(base/(member+'-doc-review-import.json'),accepted)
 result=knowledge(base,member,'resume','--run',start['run']);save(base/(member+'-doc-completion.json'),result)
 print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':
 action,flow,*rest=sys.argv[1:]
 if action=='init':initialize(flow)
 elif action=='change':change(flow,*rest)
 elif action=='apply':apply_doc(flow,*rest)
