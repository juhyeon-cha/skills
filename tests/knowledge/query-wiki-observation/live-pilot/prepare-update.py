from driver import *
import sys
n=sys.argv[1];sp=R/('start-'+n+'.json')
if not sp.exists():save(sp.name,project('start-'+n,n,'start','--rev',(R/('revision-'+n+'.txt')).read_text().strip()))
s=json.loads(sp.read_text());context=json.loads(pathlib.Path(s['context']).read_text());claims=[]
for c in context['bindings']['documents'][0]['claims']:
 text=c['text'];new=text.replace('amount','total') if c['id']=='behavior' else (f"소스 버전: {context['after']['commit']}. 근거: app.py." if c['id']=='version' else text)
 claims.append({'path':'guide.md','id':c['id'],'action':'keep' if text==new else 'replace','reason':'고정 after 소스의 total 계약과 버전을 반영하고 기존 의존성/배포 한계는 보존한다.','text':new,'evidence':c['evidence']})
d={'impact':context['impact']['id'],'claims':claims,'unlinked':[{'change':c,'action':'no-document-change','reason':'check.py는 app.py 계약에 맞춘 로컬 테스트이며 신규 사용자 동작을 도입하지 않는다.'} for c in context['impact']['unlinked_changes']]}
p=project('prepare-'+n,n,'prepare','--run',s['run'],'--decisions',save('decisions-'+n+'.json',d));save('prepare-'+n+'.json',p);print(p)
