"""Bounded local observation only. All review receipts are synthetic test doubles."""
import importlib.util, json, sys, tempfile, time, hashlib
from pathlib import Path
ROOT=Path('/private/tmp/skills-knowledge-diagnostics')
OUT=Path('/private/tmp/knowledge-diagnostics-evidence')
sys.dont_write_bytecode=True
tempfile.tempdir=str(OUT)
spec=importlib.util.spec_from_file_location('fixture', ROOT/'tests/knowledge/multi_repo/test_multi_repo.py')
fixture=importlib.util.module_from_spec(spec); spec.loader.exec_module(fixture)
from multi_repo import Store, digest, command_files

def error(e): return {'type':type(e).__name__, 'message':str(e)}
def hashes(root):
    return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
def observe(f):
    before=hashes(f.root/'state')
    s=Store(f.root/'state',f.host_path,'operator')
    result={'members':{},'checks':{},'legacy':{}}
    with s.locked(readonly=True):
        g=s.goal('contract'); sources={}
        for r in g['members']:
            try: sources[r]=s.source(r)
            except Exception as e: sources[r]={'observation_error':error(e)}
        for name in list(g['integration'])+[c for m in g['members'].values() for c in m['criteria']]:
            identity=s.state['checks'].get('contract/'+name)
            if not identity:
                result['checks'][name]={'present':False}; continue
            record=s.object(identity); command=s.host['checks'][name]
            matches={'goal':record['goal_hash']==digest(g), 'command':record['command']==command,
                'input_files':record['input_files']==command_files(command),
                'sources':all(sources.get(r)==snapshot for r,snapshot in record['sources'].items()),
                'source_unchanged':record['source_unchanged']}
            result['checks'][name]={'present':True,'identity':identity,'matches':matches,
                'fresh':all(matches.values()),'exit_code':record['exit_code'],
                'record':record}
        for r in g['members']:
            s.policy()
            if not(s.allowed(r,'publish') and s.allowed(r,'query')):
                result['members'][r]={'first_stage':'authorization','withheld':True}; continue
            stage='source'
            try:
                snap=s.source(r); stage='documents'; docs=s.documents(r,snap)
                stage='checks'; checks=s.checked(g,g['members'][r]['criteria'],{r:snap})
                stage='review'; review=s.reviewed(g,r,snap,docs,checks)
                result['members'][r]={'first_stage':None,'validation':'verified','review_synthetic':s.object(review)['synthetic']}
            except Exception as e: result['members'][r]={'first_stage':stage,'error':error(e)}
        if all(m.get('validation')=='verified' for m in result['members'].values()):
            stage='checks'
            try:
                checks=s.checked(g,g['integration'],sources)
                stage='review'
                for r in g['members']: s.reviewed(g,r,sources[r],s.documents(r,sources[r]),checks)
                result['integration']={'validation':'verified'}
            except Exception as e: result['integration']={'first_stage':stage,'error':error(e)}
        else: result['integration']={'not_reached':True}
        for method in ('query','wiki','reading'):
            try: result['legacy'][method]=getattr(s,method)({'goal':'contract'})
            except Exception as e: result['legacy'][method]={'observation_error':error(e)}
    result['state_files_unchanged_by_observation']=hashes(f.root/'state')==before
    return result

def build(name):
    f=fixture.Fixture()
    if name in ('missing_check','no_review'):
        for r in f.host['repositories']: f.update(r,'total')
        checks=['consumer','exchange'] if name=='missing_check' else ['producer','consumer','exchange']
        f.call('run_checks',{'goal':'contract','checks':checks})
    else:
        f.complete(); f.call('refresh',{'goal':'contract'}); f.call('publish',{'goal':'contract'})
    docs=f.root/('producer-docs-'+f.revisions['producer'])/'contract.md'
    if name=='document_drift': docs.write_text('producer uses drift.')
    elif name=='missing_document': docs.rename(docs.with_suffix('.preserved'))
    elif name=='source_dirty':
        p=Path(f.host['repositories']['producer']['path'])/'app.py'; p.write_text(p.read_text()+'# dirty\n')
    elif name in ('fresh_failed_check','stale_failed_check','integration_failure'):
        check='exchange' if name=='integration_failure' else 'producer'
        f.host['checks'][check]['argv']=[sys.executable,'-B','-c',"raise SystemExit('synthetic observed failure')"]
        f.persist(); f.call('run_checks',{'goal':'contract','checks':[check]})
        if name=='stale_failed_check':
            f.host['checks'][check]['argv']=[sys.executable,'-B','-c','pass']; f.persist()
    elif name.startswith('revoke_'):
        right=name.removeprefix('revoke_')
        f.host['principals']['operator']['repositories']['producer'].remove(right); f.persist()
    return f

start=time.monotonic(); cases=[]
for name in ('complete','document_drift','fresh_failed_check','stale_failed_check','missing_check','no_review','source_dirty','missing_document','integration_failure','revoke_publish','revoke_query','revoke_source'):
    t=time.monotonic()
    try:
        f=build(name); observation=observe(f)
        cases.append({'case':name,'fixture_path':str(f.root),'synthetic_receipts':True,'elapsed_seconds':time.monotonic()-t,**observation})
    except Exception as e: cases.append({'case':name,'error':error(e),'elapsed_seconds':time.monotonic()-t})
    (OUT/'results.json').write_text(json.dumps({'production_root':str(ROOT),'synthetic_receipts':True,'tokens_measured':False,'dollars_measured':False,'elapsed_seconds':time.monotonic()-start,'cases':cases},ensure_ascii=False,indent=2))
    print(name, json.dumps(cases[-1].get('members',cases[-1].get('error')),ensure_ascii=False),flush=True)
