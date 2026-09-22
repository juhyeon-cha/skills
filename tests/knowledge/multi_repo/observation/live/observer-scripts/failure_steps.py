from live_steps import *
from collect_checkpoint import collect
import copy

def host_write(base,tag,value):
 before=(base/'host.json').read_bytes();save(base/(tag+'-host-before.json'),json.loads(before));(base/'host.json').write_text(json.dumps(value,ensure_ascii=False,indent=2));save(base/(tag+'-host-after.json'),value);return before

def permission():
 base=ROOT/'code-first';h=json.loads((base/'host.json').read_text());h['principals']['reader']['repositories']['svc-consumer']=[];old=host_write(base,'revoked',h)
 collect('code-first','Q4')
 for name in ['Q4-query-output.json','Q4-wiki-output.json']:
  v=json.loads((base/name).read_text());assert v['completion']=='incomplete' and v['withheld_count']==1
  assert 'svc-consumer' not in json.dumps(v) and 'consumer.invalid' not in json.dumps(v)
 (base/'host.json').write_bytes(old);multi(base,'query',{'goal':'contract-total'},'reader','permission-restored');print('permission recorded')

def unavailable():
 base=ROOT/'code-first';original=base/'consumer';away=base/'consumer-unavailable'
 before=knowledge(base,'consumer','status','--deep');save(base/'failure-project-before.json',before)
 original.rename(away)
 try:
  run([PYTHON,SCRIPTS/'knowledge.py','--project',base/'consumer-project','start','--rev','HEAD'],expect=1)
  after=knowledge(base,'consumer','status','--deep');save(base/'failure-project-after.json',after);assert before==after
  refreshed=multi(base,'refresh',{'goal':'contract-total'},label='source-unavailable-refresh');assert next(m for m in refreshed['members'] if m['repository']=='svc-consumer')['validation']=='source_unavailable'
  result=multi(base,'publish',{'goal':'contract-total','audience':'reader'},label='source-unavailable-publish');assert result['outcome']=='partial' and result['members']['svc-consumer']=='failed'
  wiki=multi(base,'wiki',{'goal':'contract-total'},'reader','source-unavailable-wiki');assert wiki['served']=='unavailable_or_partial'
 finally:away.rename(original)
 multi(base,'refresh',{'goal':'contract-total'},label='source-restored-refresh');multi(base,'publish',{'goal':'contract-total','audience':'reader'},label='source-restored-publish');assert multi(base,'wiki',{'goal':'contract-total'},'reader','source-restored-wiki')['served']=='current';print('unavailable/recovery recorded')

def clone():
 base=ROOT/'code-first';run(['git','clone','--no-hardlinks',base/'producer',base/'producer-relocated']);h=json.loads((base/'host.json').read_text());h['repositories']['svc-producer']['path']=str(base/'producer-relocated');old=host_write(base,'relocated',h)
 try:
  result=multi(base,'query',{'goal':'contract-total'},'reader','relocated-query');assert result['completion']=='complete';assert {m['repository'] for m in result['members']}=={'svc-producer','svc-consumer'}
 finally:(base/'host.json').write_bytes(old)
 print('clone identity recorded')

def stale():
 base=ROOT/'code-first';repo=base/'producer';original=(repo/'app.py').read_text();save(base/'stale-source-before.json',{'text':original});(repo/'app.py').write_text(original+'# Advance source revision after managed publication.\n');run(['git','add','app.py'],repo);run(['git','commit','-m','Advance local observation revision'],repo)
 collect('code-first','Q5');q=json.loads((base/'Q5-query-output.json').read_text());w=json.loads((base/'Q5-wiki-output.json').read_text());assert q['index']=='stale' and q['completion']=='incomplete';assert w['served']=='unavailable_or_partial';assert all('documents' not in m for m in w['members']);print('stale checkpoint recorded')

def register_record(base,name,intent,status,description):
 value=json.loads((base/'user-origin-input.json').read_text());code=next(s for s in value['sources'] if s['id']=='code');code['text']=(base/'producer/app.py').read_text();code['version']=run(['git','rev-parse','HEAD'],base/'producer').strip();code['sha256']=hashlib.sha256(code['text'].encode()).hexdigest();value.update(origin='user',intent=intent);value['current']['description']='The pinned current producer uses total; independent consumer evidence is retained in this flow.';value['target'].update(status=status,description=description,sources=['code','user']);value['differences']=[{'kind':'documentation' if intent=='current_behavior' else 'behavior','description':description,'sources':['code','user']}];value['rationale']='Authorized isolated S5 scenario only; preserve current code and historical request, never infer production policy approval.'
 inp=save(base/(name+'-intake-input.json'),value);registered=knowledge(base,'producer','intake','--input',inp);save(base/(name+'-intake-output.json'),registered);path=Path(registered['record']);return {'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}

def comparisons(flow):
 base=ROOT/flow
 for kind in ['incorrect','correct','user']:
  pred=json.loads((base/('prediction-'+kind+'-output.json')).read_text())['prediction'];v=multi(base,'compare',{'goal':'contract-total','prediction':pred,'feedback':[]},label='comparison-'+kind)
  assert v['omissions']==(['svc-consumer'] if kind=='incorrect' else [])
 ref=register_record(base,'omission','current_behavior','confirmed','Maintain current knowledge that the original producer-only prediction omitted the consumer dependency; actual both-source changes and integration evidence are retained.')
 decision=register_record(base,'decision','current_behavior','confirmed','Local authoring decision: retain the old wrong prediction, link the consumer dependency and distinguish the approved total target from verified current behavior. No new production policy.')
 pred=json.loads((base/'prediction-incorrect-output.json').read_text())['prediction'];result=multi(base,'compare',{'goal':'contract-total','prediction':pred,'feedback':[{'kind':'omission','repositories':['svc-consumer'],'intake':ref,'description':'Consumer omission routed to existing current-documentation intake.'},{'kind':'decision','repositories':['svc-producer','svc-consumer'],'intake':decision,'description':'Retain wrong prediction with correction and shared current/target evidence.'}]},label='comparison-feedback');assert result['unresolved']==[]
 print('comparisons and feedback intakes recorded')

def withdraw():
 base=ROOT/'code-first';ref=register_record(base,'withdrawal','behavior_change','withdrawn','Withdraw this isolated total goal without rolling back current source commits; retain implemented total behavior as observed history.')
 goal=json.loads((base/'goal.json').read_text());goal.update(version='v3',status='withdrawn');goal['origin'].update(kind='user',intake=ref);multi(base,'goal',goal,label='withdrawal-goal');p=multi(base,'publish',{'goal':'contract-total','audience':'reader'},label='withdrawal-publish');assert p['outcome']=='withdrawn';collect('code-first','Q6');q=json.loads((base/'Q6-query-output.json').read_text());assert q['status']=='withdrawn' and q['completion']=='incomplete';assert "'total'" in (base/'producer/app.py').read_text();assert "'total'" in (base/'consumer/app.py').read_text();print('withdrawal recorded without rollback')

if __name__=='__main__':
 action,*args=sys.argv[1:];globals()[action](*args)
