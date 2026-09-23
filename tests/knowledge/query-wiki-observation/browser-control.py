"""Explicit local scenario transitions; preserve every prior artifact and original host/docs."""
from pathlib import Path
import sys,json,hashlib,urllib.request,time
sys.path.insert(0,'/private/tmp/knowledge-query-evidence/live-pilot')
from driver import R, multi, project, run, save
E=Path('/private/tmp/knowledge-query-evidence/browser')
def capture(name):
 v=multi('browser-'+name,'read',{'goal':'exchange'},principal='reader')
 (E/(name+'.json')).write_text(json.dumps(v,ensure_ascii=False,indent=2))
 print(name,v['completion'],v['served'],v['index'],v['projection_id'])
cmd=sys.argv[1]
if cmd=='complete':
 (E/'host-original.json').write_bytes((R/'host.json').read_bytes())
 (E/'producer-guide-original.md').write_bytes((R/'docs-producer/guide.md').read_bytes())
 capture(cmd)
elif cmd=='revoked':
 h=json.loads((E/'host-original.json').read_text());h['principals']['reader']['repositories']['pilot/consumer']=[]
 (R/'host.json').write_text(json.dumps(h,ensure_ascii=False,indent=2));capture(cmd)
elif cmd=='restore-access':
 (R/'host.json').write_bytes((E/'host-original.json').read_bytes());capture(cmd)
elif cmd=='drift':
 doc=R/'docs-producer/guide.md';doc.write_text(doc.read_text()+'\n未검토 외부 변경\n')
 # Resume refuses the changed document rather than overwriting it.
 ident=json.loads((R/'start-producer.json').read_text())['run']
 result=run('browser-resume-drift','knowledge.py','--project',R/'project-producer','resume','--run',ident,expected=1)
 capture(cmd)
elif cmd=='restore-doc':
 (R/'docs-producer/guide.md').write_bytes((E/'producer-guide-original.md').read_bytes());capture(cmd)
elif cmd=='check_failed':
 h=json.loads((E/'host-original.json').read_text());h['checks']['producer-check']['argv']=[sys.executable,'-c','raise SystemExit(1)']
 (R/'host.json').write_text(json.dumps(h,ensure_ascii=False,indent=2));multi('browser-failed-check','check',{'goal':'exchange','checks':['producer-check']});capture(cmd)
elif cmd=='withdrawn':
 # Explicitly scoped experimental goal withdrawal, not an operational policy decision.
 inp=json.loads((R/'goal-intake-input.json').read_text());inp['origin']='user';inp['intent']='current_behavior'
 text='격리된 조회·위키 검증 시나리오에서 exchange 목표를 철회 상태로 둔다. 실제 운영 정책은 변경하지 않는다.'
 inp['sources'].append({'id':'scenario','kind':'user','authority':'user_instruction','version':'withdrawal-scenario-1','locator':'local-fixture:approved-test-scope','text':text,'sha256':hashlib.sha256(text.encode()).hexdigest()})
 inp['target'].update(sources=['producer','consumer','scenario'],status='withdrawn');inp['differences']=[{'kind':'documentation','description':'현재 코드는 그대로 보존하며 문서화 목표를 철회하고 게시 상태에서 제외한다.','sources':['producer','consumer','scenario']}];inp['rationale']='승인된 목표철회 로컬실험 조건. 운영결정 아님.'
 p=save('browser-withdraw-intake-input.json',inp);receipt=project('browser-withdraw-intake','producer','intake','--input',p)
 save('browser-withdraw-intake-result.json',receipt)
 goal=json.loads((R/'request-goal-v2.json').read_text());goal.update(version='v2',status='withdrawn')
 goal['origin']={'kind':'user','request':'local-withdrawal-scenario','cause':'approved-local-test','intake':{'path':receipt['record'],'sha256':hashlib.sha256(Path(receipt['record']).read_bytes()).hexdigest()}}
 multi('browser-withdraw-goal','goal',goal);capture(cmd)
else: raise SystemExit('unknown stage')
