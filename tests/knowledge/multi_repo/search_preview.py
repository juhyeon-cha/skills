"""Observe fixed search questions and a pinned baseline on isolated repositories."""
import argparse
from datetime import datetime, timezone
import hashlib
import http.client
import json
from pathlib import Path
import subprocess
import threading
import time
from types import ModuleType
from urllib.parse import quote, urlsplit

from search_fixture import published_fixture
from test_multi_repo import ROOT, SCRIPTS
from reader import make_server

QUERIES = ['금액 단위','변경 total','운영 배포','재시도 상한','total 120','METADATA_ONLY_771','양자결제']
QUESTIONS = ['금액 필드 이름과 단위는?', '계약 변경 시 소비자는 무엇을 변경하나?',
             '어떤 검사가 운영 배포를 보장하나?', '재시도 상한은?', 'JSON 예제의 필드와 값은?',
             '숨겨진 저장소나 오래된 본문에서 답할 수 있나?',
             'METADATA_ONLY_771은 문서 근거로 검색되는가?', '양자결제를 지원하는가?']
BASE = '13550c1eb8c9f52d8b123c6cbc43abeed57e915c'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--observe-only',action='store_true')
    args = parser.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    fixture = published_fixture()
    baseline = ModuleType('baseline_reader');baseline.__file__ = str(SCRIPTS/'reader.py')
    source = subprocess.run(['git','show',BASE + ':plugins/knowledge/scripts/reader.py'],cwd=ROOT,
                            check=True,capture_output=True,text=True).stdout
    exec(compile(source, '<pinned baseline reader>', 'exec'),baseline.__dict__)
    servers=[];threads=[];records=[]
    def start(factory):
        server=factory(fixture.root/'state',fixture.host_path,'reader','contract',0)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        servers.append(server);threads.append(thread);return server
    def request(server,route,name):
        clock=time.perf_counter();conn=http.client.HTTPConnection('127.0.0.1',server.server_port,timeout=15)
        try:
            conn.request('GET',route);response=conn.getresponse();body=response.read()
            elapsed=(time.perf_counter()-clock)*1000
            (args.output/name).write_bytes(body)
            records.append({'route':route,'file':name,'status':response.status,'elapsed_ms':elapsed,
                            'bytes':len(body),'sha256':hashlib.sha256(body).hexdigest()})
            if response.status!=200:raise RuntimeError('Observation failed: '+route)
            return body
        finally:conn.close()
    try:
        candidate=start(make_server);old=start(baseline.make_server)
        answers=[]
        for i,query in enumerate(QUERIES):
            value=json.loads(request(candidate,'/api/search?q='+quote(query),'query-'+str(i+1)+'.json'))
            pages=[]
            for j,hit in enumerate(value['results']):
                name='arrival-'+str(i+1)+'-'+str(j)+'.html'
                request(candidate,urlsplit(hit['url']).path,name);pages.append(name)
            answers.append({'query':query,'response':value,'arrival_files':pages})
        for i in range(5):
            request(old,'/?q='+quote(QUERIES[0]),'baseline-'+str(i)+'.html')
            request(candidate,'/search/?q='+quote(QUERIES[0]),'candidate-'+str(i)+'.html')
        normal_host=json.loads(fixture.host_path.read_text())
        fixture.host['principals']['reader']['repositories']['consumer']=[];fixture.persist()
        revoked=json.loads(request(candidate,'/api/search?q=total','revoked.json'))
        fixture.host=normal_host;fixture.persist()
        state=fixture.root/'state/state.json';normal_state=state.read_bytes()
        changed=json.loads(normal_state);changed['index']={'contract':'0'*64};state.write_text(json.dumps(changed))
        stale=json.loads(request(candidate,'/api/search?q='+quote(QUERIES[0]),'stale-index.json'))
        state.write_bytes(normal_state)
        docs=fixture.root/('producer-search-docs-'+fixture.revisions['producer'])/'contract.md'
        original=docs.read_bytes();docs.write_text('Unreviewed replacement')
        drift=json.loads(request(candidate,'/api/search?q=total','drift.json'));docs.write_bytes(original)
        packet={'questions':QUESTIONS,'searches':answers,'revoked':revoked,'drift':drift,'stale_index':stale,
                'scope':'Local example only. Review receipts are synthetic. No operating deployment is established.'}
        (args.output/'reader-packet.json').write_text(json.dumps(packet,ensure_ascii=False,indent=2))
        summary={'created_at':datetime.now(timezone.utc).isoformat(),'url':'http://127.0.0.1:'+str(candidate.server_port),
                 'fixture':str(fixture.root),'baseline_commit':BASE,'requests':records,
                 'model_tokens':None,'model_cost':None,'review_receipts':'synthetic',
                 'browser_observed':False,'independent_model_observed':False}
        (args.output/'observations.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
        candidate_times=[r['elapsed_ms'] for r in records if r['file'].startswith('candidate-')]
        if max(candidate_times)>2000:raise RuntimeError('Fixed HTTP latency criterion exceeded')
        print(json.dumps({'url':summary['url'],'fixture':str(fixture.root),'requests':len(records)},ensure_ascii=False),flush=True)
        if not args.observe_only:
            while True:time.sleep(1)
    except KeyboardInterrupt:pass
    finally:
        for server in servers:server.shutdown()
        for thread in threads:thread.join(3)
        for server in servers:server.server_close()


if __name__=='__main__':main()
