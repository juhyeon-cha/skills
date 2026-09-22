from pathlib import Path
import json,hashlib
root=Path('/private/tmp/stage5-work/live')
p=json.loads((root/'baseline-packet.json').read_text())
user='검증은 격리된 로컬 복수 저장소로 한정해. 코드 선행 변경과 문서 선행 계약 변경을 각각 영향 예측→반영→구현 검증→검색·위키 조회까지 실행해.'
def src(i,kind,authority,version,locator,text):return dict(id=i,kind=kind,authority=authority,version=version,locator=locator,text=text,sha256=hashlib.sha256(text.encode()).hexdigest())
for flow in ['code-first','document-first']:
 base=root/flow
 producer=next(x for x in p['records'] if x['flow']==flow and x['repository_id']=='svc-producer')
 target='로컬 실험 목표 contract-total v2: 생산자와 소비자가 amount 대신 total 필드를 교환한다. 값은 10을 유지한다. 현재 두 소스는 amount를 사용하며 이 문서 작성만으로 구현·검증 완료가 되지 않는다. 두 저장소별 검사와 통합 검사 및 독립 리뷰가 필요하다.'
 (base/'target.md').write_text(target+'\n')
 sources=[src('user','user','user_instruction','session-01a0c6f1','conversation:user-stage5-request',user),src('code','code','observed_implementation',producer['revision'],producer['repo_path']+'/app.py',producer['source']),src('target-document','document','context','v2',str(base/'target.md'),target+'\n')]
 record={'version':1,'origin':'code' if flow=='code-first' else 'document','intent':'behavior_change','sources':sources,'current':{'code':'code','description':'두 로컬 기준 저장소는 amount를 교환한다. 소비자 근거는 고정 baseline-packet.json의 별도 svc-consumer 항목이다.'},'target':{'sources':['user','target-document'],'description':target,'acceptance':['생산자 emit()가 total=10을 반환한다.','소비자 parse()가 total을 읽는다.','두 함수를 연결한 결과가 10이다.','두 저장소 문서·검색·위키가 현재 구현 및 미구현 목표를 구분한다.'],'status':'confirmed'},'differences':[{'kind':'behavior','description':'양쪽 소스와 검사가 아직 amount를 사용하므로 total 목표는 미구현이다.','sources':['code','target-document']}],'rationale':'사용자가 승인한 격리 로컬 시험을 amount/total 예제로 구체화한 구현 선택이다. 운영 업무 정책을 승인받았다는 뜻이 아니다. 문서·코드·사용자 근거를 구분하며 원본 intake의 not_verified 상태는 후속 검증 기록과 별개로 보존한다.'}
 (base/'origin-input.json').write_text(json.dumps(record,ensure_ascii=False,indent=2))
 user_origin=dict(record,origin='user')
 (base/'user-origin-input.json').write_text(json.dumps(user_origin,ensure_ascii=False,indent=2))
(root/'origin-freeze.json').write_text(json.dumps({str(x.relative_to(root)):hashlib.sha256(x.read_bytes()).hexdigest() for f in ['code-first','document-first'] for x in [root/f/'target.md',root/f/'origin-input.json',root/f/'user-origin-input.json']},indent=2))
print('Origin inputs and target texts frozen; no implementation changes yet')
