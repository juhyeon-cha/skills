import sys,json,copy,html,time
from pathlib import Path
sys.path.insert(0,'/private/tmp/skills-knowledge-query-wiki/tests/knowledge/multi_repo')
from test_multi_repo import Fixture,digest
out=Path('/private/tmp/knowledge-query-evidence')
results=[]
for case in ['complete','partial','withdrawn','revoked','drift','check_failed']:
 started=time.monotonic(); f=Fixture()
 if case=='partial':
  f.update('producer','total'); f.call('run_checks',{'goal':'contract','checks':['producer']}); f.review(['producer'])
 else: f.complete()
 f.call('refresh',{'goal':'contract'}); f.call('publish',{'goal':'contract','audience':'reader'})
 before=f.call('wiki',{'goal':'contract'},'reader'); (out/(case+'-static-before.txt')).write_text(before['markdown'])
 if case=='withdrawn':
  f.goal.update(version='v2',status='withdrawn',origin=f.origin('user','withdrawn')); f.call('set_goal',f.goal)
 elif case=='revoked':
  f.host['principals']['reader']['repositories']['consumer']=[]; f.persist()
 elif case=='drift':
  project=Path(f.host['repositories']['producer']['project']); docs=next(f.root.glob('producer-docs-'+f.revisions['producer']))
  (docs/'contract.md').write_text('Unreviewed changed text')
 elif case=='check_failed':
  f.host['checks']['producer']['argv']=[sys.executable,'-c','raise SystemExit(1)'];f.persist();f.call('run_checks',{'goal':'contract','checks':['producer']})
 query=f.call('query',{'goal':'contract'},'reader'); wiki=f.call('wiki',{'goal':'contract'},'reader')
 candidate=copy.deepcopy(wiki);candidate.pop('markdown');candidate['index']=query['index'];candidate['projection_id']=digest(candidate)
 (out/(case+'-candidate.html')).write_text('<!doctype html><meta charset="utf-8"><pre>'+html.escape(json.dumps(candidate,ensure_ascii=False,indent=2))+'</pre>')
 if case=='complete': assert candidate['completion']=='complete' and candidate['served']=='current'
 else: assert candidate['completion']=='incomplete' and all('documents' not in m for m in candidate['members'])
 if case=='revoked': assert 'consumer' not in json.dumps(candidate) and candidate['withheld_count']==1 and 'consumer' in (out/(case+'-static-before.txt')).read_text()
 results.append({'case':case,'root':str(f.root),'query':query,'wiki':wiki,'candidate':candidate,'elapsed_seconds':time.monotonic()-started,'receipts':'synthetic fixture only'})
(out/'m0-results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
print([(r['case'],r['candidate']['completion'],r['candidate']['index']) for r in results])
