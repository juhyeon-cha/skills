from driver import *
review=json.loads((R/'bootstrap-review.json').read_text())
print('Independent result must be inspected by orchestrator before running init:',str(R/'bootstrap-review.json'))
exec((R/'format-check.py').read_text())
for n in ['producer','consumer']:
 inp=json.loads((R/('input-'+n+'.json')).read_text())
 result=project('init-'+n,n,'init','--repo',R/n,'--docs',R/('docs-'+n),'--repository','pilot/'+n,'--baseline',inp['commit'],'--path','app.py','--path','check.py','--spec',R/('spec-'+n+'.json'),'--audience','백엔드 개발자','--purpose','교환 필드와 예외 및 배포 검증 범위를 판단한다')
 save('init-'+n+'.json',result);save('status-initial-'+n+'.json',project('status-initial-'+n,n,'status'))
 print(n,result)
multi('relations-init','init')
