"""Actual CLI captures over preserved synthetic fixtures; no semantic reader judgment."""
import hashlib,json,subprocess,time,sys
from pathlib import Path
OUT=Path('/private/tmp/knowledge-diagnostics-evidence')
ROOT=Path('/private/tmp/skills-knowledge-diagnostics')
PYTHON='/private/tmp/knowledge-contract-venv/bin/python'
def hashes(root):
    return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
original=json.loads((OUT/'results.json').read_text())
start=time.monotonic(); cases=[]; answers=[]; coords=[]
request=OUT/'candidate-read-input.json'; request.write_text('{"goal":"contract"}\n')
for index,old in enumerate(original['cases'],1):
    root=Path(old['fixture_path']); before=hashes(root)
    row={'case':old['case'],'alias':'case-'+str(index).zfill(2),'fixture_path':str(root),'calls':{},'legacy_equal':{}}
    for action in ('query','wiki','read'):
        argv=[PYTHON,'-B',str(ROOT/'plugins/knowledge/scripts/multi_repo.py'),'--state',str(root/'state'),'--host',str(root/'host.json'),'--principal','operator',action,'--input',str(request)]
        t=time.monotonic(); p=subprocess.run(argv,capture_output=True,text=True,timeout=60)
        capture={'argv':argv,'elapsed_seconds':time.monotonic()-t,'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
        try: capture['response']=json.loads(p.stdout)
        except ValueError: pass
        row['calls'][action]=capture
        if action in ('query','wiki'): row['legacy_equal'][action]=capture.get('response')==old['legacy'][action]
    row['all_fixture_file_bytes_unchanged']=before==hashes(root)
    row['fixture_file_hashes_before']=before
    row['fixture_file_hashes_after']=hashes(root)
    cases.append(row)
    answers.append({'alias':row['alias'],'public_response':row['calls']['read'].get('response',{'error':'PUBLIC_READ_FAILED'})})
    if old['case'] in ('document_drift','fresh_failed_check','stale_failed_check','no_review','integration_failure','revoke_publish'):
        port=18880+len(coords)
        coords.append({'case':old['case'],'url':'http://127.0.0.1:'+str(port),'argv':[PYTHON,'-B',str(ROOT/'plugins/knowledge/scripts/reader.py'),'--state',str(root/'state'),'--host',str(root/'host.json'),'--principal','operator','--goal','contract','--port',str(port)]})
    print(row['case'],row['legacy_equal'],'unchanged',row['all_fixture_file_bytes_unchanged'],'exit',row['calls']['read']['exit_code'],flush=True)
(OUT/'candidate-results.json').write_text(json.dumps({'synthetic_underlying_receipts':True,'elapsed_seconds':time.monotonic()-start,'cases':cases},ensure_ascii=False,indent=2))
(OUT/'answer-input.json').write_text(json.dumps({'questions':['첫 차단 단계는 무엇인가?','공개 응답으로 확인된 사실은 무엇인가?','다음 조치는 무엇인가?','전체 완료 여부와 문서 본문 제공 가능 여부는 무엇인가?','숨긴 범위가 있는가? 공개 응답으로 알 수 없는 내용은 단정하지 말 것.'],'cases':answers},ensure_ascii=False,indent=2))
(OUT/'browser-coordinates.json').write_text(json.dumps(coords,ensure_ascii=False,indent=2))
assert all(c['all_fixture_file_bytes_unchanged'] and all(c['legacy_equal'].values()) and c['calls']['read']['exit_code']==0 for c in cases)
if '--serve' in sys.argv:
    servers=[]
    try:
        for coord in coords:
            p=subprocess.Popen(coord['argv'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            print(coord['case'],p.stdout.readline().strip(),flush=True); servers.append(p)
        while all(p.poll() is None for p in servers): time.sleep(1)
    finally:
        for p in servers: p.terminate()
