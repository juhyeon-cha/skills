from driver import *
from datetime import datetime,timezone
import sys
kind=sys.argv[1];actor=sys.argv[2]
p=json.loads((R/(kind+'-review-packet.json')).read_text());raw=(R/(kind+'-attestation-response.json')).read_text();response=json.loads(raw)
receipt={'goal':'exchange','packet':p['packet'],'author':'/root/query_wiki_live_pilot','actor':actor,'host_tool':'collaboration.followup_task' if kind=='partial' else 'collaboration.spawn_agent','call_id':actor,'started_at':(R/(kind+'-review-started.txt')).read_text().strip(),'finished_at':datetime.now(timezone.utc).isoformat(),'prompt_sha256':p['prompt_sha256'],'raw_response':raw,'response':response,'synthetic':False}
save(kind+'-attestation-receipt.json',receipt);result=multi(kind+'-attest','attest',receipt);save(kind+'-attest-result.json',result)
save('query-'+kind+'.json',multi('query-'+kind,'query',{'goal':'exchange'}));print(result)
