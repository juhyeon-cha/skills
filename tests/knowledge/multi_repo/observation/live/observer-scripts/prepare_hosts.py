from pathlib import Path
import json,hashlib
root=Path('/private/tmp/stage5-work/live');origins=json.loads((root/'origins.json').read_text())
python='/private/tmp/knowledge-contract-venv/bin/python'
for flow in ['code-first','document-first']:
 base=root/flow
 integration="import runpy\np=runpy.run_path("+repr(str(base/'producer/app.py'))+")\nc=runpy.run_path("+repr(str(base/'consumer/app.py'))+")\npayload=p['emit']()\nassert payload == {'total': 10}, payload\nassert c['parse'](payload) == 10\nprint('integration total=10 verified')\n"
 (base/'integration.py').write_text(integration)
 host={'version':1,'repositories':{ 'svc-'+n:{'path':str(base/n),'url':'https://'+n+'.invalid/example','scope':['app.py'],'project':str(base/(n+'-project'))} for n in ['producer','consumer']},'principals':{'operator':{'manage':True,'repositories':{'svc-'+n:['source','query','publish'] for n in ['producer','consumer']}},'reader':{'manage':False,'repositories':{'svc-'+n:['source','query','publish'] for n in ['producer','consumer']}},'producer-only':{'manage':False,'repositories':{'svc-producer':['source','query','publish']}}},'checks':{'producer-total':{'repositories':['svc-producer'],'argv':[python,'-B','-c',"from app import emit; assert emit() == {'total': 10}; print('producer total=10 verified')"],'cwd_repository':'svc-producer'},'consumer-total':{'repositories':['svc-consumer'],'argv':[python,'-B','-c',"from app import parse; assert parse({'total': 10}) == 10; print('consumer total verified')"],'cwd_repository':'svc-consumer'},'exchange-total':{'repositories':['svc-producer','svc-consumer'],'argv':[python,'-B',str(base/'integration.py')],'cwd_repository':'svc-producer'}}}
 (base/'host.json').write_text(json.dumps(host,ensure_ascii=False,indent=2))
 intake=Path(origins[flow]['origin']['record'])
 goal={'id':'contract-total','version':'v2','status':'active','members':{'svc-producer':{'target':'emit() returns total=10','criteria':['producer-total']},'svc-consumer':{'target':'parse() reads total and returns 10','criteria':['consumer-total']}},'integration':['exchange-total'],'origin':{'kind':'code' if flow=='code-first' else 'document','request':flow+'-request','cause':'stage5-authorized-local-test','intake':{'path':str(intake),'sha256':hashlib.sha256(intake.read_bytes()).hexdigest()}}}
 (base/'goal.json').write_text(json.dumps(goal,ensure_ascii=False,indent=2))
(root/'host-freeze.json').write_text(json.dumps({str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for flow in ['code-first','document-first'] for p in [root/flow/'host.json',root/flow/'goal.json',root/flow/'integration.py']},indent=2))
print('Host checks/goal inputs frozen before source changes; CLI compatibility not yet exercised')
