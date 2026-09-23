from driver import *
h=json.loads((R/'host.json').read_text());save('host-initial-mismatch.json',h)
h['repositories']={'pilot/'+n:c for n,c in h['repositories'].items()}
for p in h['principals'].values():p['repositories']={'pilot/'+n:rs for n,rs in p['repositories'].items()}
for c in h['checks'].values():c['repositories']=['pilot/'+n for n in c['repositories']];c['cwd_repository']='pilot/'+c['cwd_repository']
save('host.json',h)
g=json.loads((R/'registered-goal.json').read_text());g['members']={'pilot/'+n:m for n,m in g['members'].items()};save('registered-goal-v2.json',g)
# A new relation state preserves the failed earlier setup rather than mutating identity anchors.
p=R/'driver.py';p.write_text(p.read_text().replace("R/'relations'","R/'relations-v2'"))
