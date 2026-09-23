from driver import *
sources=[]
for n in ['producer','consumer']:
 revision=(R/('revision-'+n+'.txt')).read_text().strip();text=(R/n/'app.py').read_text()
 sources.append({'id':n,'kind':'code','authority':'observed_implementation','version':revision,'locator':str(R/n/'app.py'),'text':text,'sha256':hashlib.sha256(text.encode()).hexdigest()})
value={'version':1,'origin':'code','intent':'current_behavior','sources':sources,'current':{'code':'producer','description':'두 저장소가 total 필드를 교환하도록 로컬 코드가 변경됐다.'},'target':{'sources':['producer','consumer'],'description':'고정 구현의 total 계약과 누락 KeyError를 문서화한다.','acceptance':['produce() == {total:1}','consume({total:1}) == 1','consume({}) raises KeyError'],'status':'confirmed'},'differences':[{'kind':'documentation','description':'초기 amount 문서에서 total 문서로 변경','sources':['producer','consumer']}],'rationale':'실제 로컬 코드 변화에서 파생된 문서 및 교환 검증 목표; 원격 배포나 사용자 정책 승인 주장 없음.'}
intake=project('goal-intake','producer','intake','--input',save('goal-intake-input.json',value));save('goal-intake-result.json',intake)
p=pathlib.Path(intake['record']);goal=json.loads((R/'goal-input.json').read_text());goal['origin']={'kind':'code','request':'pilot-amount-total','cause':'local-code-change','intake':{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}}
save('registered-goal.json',goal);save('goal-result.json',multi('goal','goal',goal));save('query-before-review.json',multi('query-before-review','query',{'goal':'exchange'}))
