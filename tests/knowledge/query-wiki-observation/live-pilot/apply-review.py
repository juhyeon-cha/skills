from driver import *
import sys
n=sys.argv[1];s=json.loads((R/('start-'+n+'.json')).read_text());review=json.loads((R/('review-'+n+'.json')).read_text());assert review['verdict']=='pass'
save('import-review-'+n+'.json',project('import-review-'+n,n,'review','--run',s['run'],'--review',R/('review-'+n+'.json')))
save('resume-'+n+'.json',project('resume-'+n,n,'resume','--run',s['run']))
status=project('status-final-'+n,n,'status','--run',s['run']);save('status-final-'+n+'.json',status)
assert status['phase']=='completed';doc=(R/('docs-'+n)/'guide.md').read_text();assert 'amount' not in doc and 'total' in doc and (R/('revision-'+n+'.txt')).read_text().strip() in doc
print(status)
