exec(open('/private/tmp/knowledge-query-evidence/live-pilot/freeze.py').read().split('freeze=')[0])
freeze=json.loads((R/'frozen.json').read_text())
for name,rev in [('producer','5e0f56489f2a16f78c1b2ed12d708e333d4e71a5'),('consumer','337290f783dc4337012f04c315cd10e9b1b9ec8d')]:
 r=R/name;d=R/('docs-'+name);d.mkdir(exist_ok=True)
 behavior=('생산자 produce()는 {"amount": 1}을 반환한다.' if name=='producer' else '소비자 consume(payload)는 amount 필드 값을 그대로 반환한다. {"amount": 1}은 1을 반환하며, 필드가 없으면 KeyError가 발생한다. 기본값이나 호환 변환은 없다.')
 boundary='교환 필드 이름을 바꾸면 생산자와 소비자를 함께 수정해야 한다. 한쪽만 바꾸면 소비자가 필요한 필드를 찾지 못한다. 이 문서는 고정된 로컬 코드의 현재 동작이며, 실제 배포 동작은 검증하지 않았다.'
 version=f'소스 버전: {rev}. 근거: app.py.'
 text=f'# {name} 교환 계약\n\n{behavior}\n\n{boundary}\n\n{version}\n';(d/'guide.md').write_text(text)
 j('spec-'+name+'.json',{'documents':[{'path':'guide.md','claims':[{'id':'behavior','text':behavior,'evidence':['app.py']},{'id':'boundary','text':boundary,'evidence':['app.py']},{'id':'version','text':version,'evidence':['app.py']}]}]})
 j('input-'+name+'.json',{'repository':name,'commit':rev,'files':{p.name:{'text':p.read_text(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in r.glob('*.py')}})
reader={'context':freeze['reader']+'; '+freeze['purpose'],'questions':freeze['questions'],'documents':{n:(R/('docs-'+n)/'guide.md').read_text() for n in ['producer','consumer']}}
j('reader-input.json',reader)
defect=json.loads(json.dumps(reader));defect['documents']['consumer']=defect['documents']['consumer'].replace('필드가 없으면 KeyError가 발생한다. 기본값이나 호환 변환은 없다.','필드가 없으면 기본값 0을 반환한다.');j('reader-defect-input.json',defect)
j('bootstrap-hashes.json',{str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in R.rglob('*') if p.is_file() and '.git' not in p.parts})
