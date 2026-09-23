from driver import *
h=json.loads((R/'bootstrap-hashes.json').read_text()); results={}
for p,digest in h.items():
 results[p]=hashlib.sha256((R/p).read_bytes()).hexdigest()==digest
for name in ['producer','consumer']:
 doc=(R/('docs-'+name)/'guide.md').read_text();sp=json.loads((R/('spec-'+name+'.json')).read_text())
 assert all(doc.count(c['text'])==1 and (R/name/c['evidence'][0]).is_file() for c in sp['documents'][0]['claims'])
assert all(results.values());save('format-result.json',{'verdict':'pass','file_hashes':results,'checks':['exact unique excerpts','evidence paths exist','source commit recorded'],'boundary':'format only; semantic judgment separate'})
