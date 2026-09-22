"""Collect same-checkpoint raw and aggregate inputs; no semantic answer generation."""
from live_steps import *

def collect(flow,question,principal='reader'):
 base=ROOT/flow;folder=ROOT/'checkpoints'/question;folder.mkdir(parents=True,exist_ok=False)
 protocol=json.loads((ROOT/'comparison-checkpoints.json').read_text());q=next(q for q in protocol['questions'] if q['id']==question)
 host=json.loads((base/'host.json').read_text());rights=host['principals'][principal]['repositories'];visible=[r for r in host['repositories'] if 'source' in rights.get(r,[]) and 'query' in rights.get(r,[])]
 artifacts=[];operations=[]
 def file_artifact(kind,path,transform=None):
  path=Path(path);raw=path.read_bytes();v=json.loads(raw) if path.suffix=='.json' else raw.decode();out=transform(v) if transform else v
  artifacts.append({'kind':kind,'source_sha256':hashlib.sha256(raw).hexdigest(),'value':out})
  operations.append({'operation':'file-read','path':str(path),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'transformed':bool(transform)})
 state=json.loads((base/'multi-state/state.json').read_text())
 def object_path(ident):return base/'multi-state/objects'/(ident+'.json')
 goal=json.loads(object_path(state['goals']['contract-total']).read_text());hidden=len(goal['members'])-len(visible)
 def scope_goal(v):
  if not hidden:return v
  return {'id':v['id'],'version':v['version'],'status':v['status'],'required_count':len(v['members']),'withheld_count':hidden,'members':{r:m for r,m in v['members'].items() if r in visible}}
 file_artifact('goal',object_path(state['goals']['contract-total']),scope_goal)
 if not hidden:file_artifact('intake',goal['origin']['intake']['path'])
 for repo in visible:
  cfg=host['repositories'][repo];member='producer' if repo=='svc-producer' else 'consumer'
  for args,label in [(['rev-parse','HEAD'],'revision'),(['show','HEAD:app.py'],'source')]:
   argv=['git','-C',cfg['path'],*args];value=run(argv);artifacts.append({'kind':label,'repository':repo,'value':value});operations.append({'operation':'command','argv':argv})
  argv=[PYTHON,SCRIPTS/'knowledge.py','--project',cfg['project'],'status','--deep'];value=json.loads(run(argv));artifacts.append({'kind':'project-status','repository':repo,'value':value});operations.append({'operation':'command','argv':list(map(str,argv))})
  file_artifact('document',base/(member+'-docs/contract.md'))
 for check,ident in state['checks'].items():
  record=json.loads(object_path(ident).read_text())
  if set(record['sources'])<=set(visible):file_artifact('check',object_path(ident))
 for ident in state['reviews']:
  record=json.loads(object_path(ident).read_text());packet=json.loads(object_path(record['packet']).read_text())
  if set(packet['sources'])<=set(visible):file_artifact('review',object_path(ident))
 if not hidden:
  for ident in state['events']:
   event=json.loads(object_path(ident).read_text())
   if event['kind'] in ['comparison','prediction']:file_artifact(event['kind'],object_path(event[event['kind']]))
 # Raw cached/published projections are permitted only where no rights have been withdrawn.
 if not hidden:
  if state['index'].get('contract-total'):file_artifact('previous-index',object_path(state['index']['contract-total']))
  for ident in state['publications']:
   record=json.loads(object_path(ident).read_text())
   if record['principal']==principal:file_artifact('publication',object_path(ident))
 baseline={'question':{'id':q['id'],'question':q['question']},'principal':principal,'artifacts':artifacts}
 save(folder/'baseline.json',baseline)
 candidate={'question':baseline['question'],'principal':principal,'query':multi(base,'query',{'goal':'contract-total'},principal,label=question+'-query'),'wiki':multi(base,'wiki',{'goal':'contract-total'},principal,label=question+'-wiki')}
 save(folder/'candidate.json',candidate)
 save(folder/'retrieval.json',{'flow':flow,'principal':principal,'checkpoint':q['checkpoint'],'baseline':{'operations':operations,'retrieval_operation_count':len(operations),'supplied_artifacts':len(artifacts)},'candidate':{'retrieval_operation_count':2,'supplied_artifacts':2},'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [folder/'baseline.json',folder/'candidate.json']},'limitations':'Preparation retrieval operations and supplied artifact count, not inferred user clicks or thought steps. Intermediate authorization selection/state enumeration excluded from both displayed counts; no runtime-efficiency claim.'})
 print(json.dumps({'question':question,'artifacts':len(artifacts),'baseline_operations':len(operations),'candidate_operations':2}))
if __name__=='__main__':collect(*sys.argv[1:])
