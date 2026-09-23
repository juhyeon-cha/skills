import pathlib,json,subprocess,time,os,hashlib
R=pathlib.Path('/private/tmp/knowledge-query-evidence/live-pilot');K=pathlib.Path('/private/tmp/skills-knowledge-query-wiki/plugins/knowledge/scripts');P='/private/tmp/knowledge-contract-venv/bin/python'
ENV=dict(os.environ,KNOWLEDGE_WRITER_SKILL='/private/tmp/skills-knowledge-query-wiki/plugins/toolkit/skills/writing-for-humans',PYTHONDONTWRITEBYTECODE='1')
def save(name,obj):
 p=R/name;p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n');return str(p)
def run(name,script,*args,expected=0):
 start=time.time();v=subprocess.run([P,str(K/script),*map(str,args)],env=ENV,capture_output=True,text=True)
 rec={'argv':[P,str(K/script),*map(str,args)],'started_at':start,'elapsed_seconds':time.time()-start,'exit_code':v.returncode,'stdout':v.stdout,'stderr':v.stderr};save('trace-'+name+'.json',rec)
 if v.returncode!=expected: raise RuntimeError(rec)
 return json.loads(v.stdout) if v.stdout else None
def project(n,name,*args):return run(n,'knowledge.py','--project',R/('project-'+name),*args)
def multi(n,action,obj=None,principal='operator'):
 args=['--state',R/'relations-v2','--host',R/'host.json','--principal',principal,action]
 if obj is not None: args+=['--input',save('request-'+n+'.json',obj)]
 return run(n,'multi_repo.py',*args)
if __name__=='__main__':run('doctor','knowledge.py','doctor')
