from driver import *
authority={'reference':'Actual delegated pilot scope: isolated local code/document observations only; no new implementation or remote actions. Same-current-commit event recovery observation.','document_updates':True,'implementation':False,'checks':[]}
a=R/'automation-producer'
def auto(n,*args):return run(n,'automation.py','--state',a,*args)
save('operate-init.json',auto('operate-init','init','--project',R/'project-producer','--authority',save('automation-authority.json',authority),'--ref','HEAD'))
event={'event_id':'already-current-1','request_id':'pilot-current-recovery','cause_id':'local-code-change','kind':'code','revision':(R/'revision-producer.txt').read_text().strip()}
save('operate-submit.json',auto('operate-submit','submit','--input',save('automation-event.json',event)))
# Persist transport reply as observation but deliberately withhold its value from subsequent control flow.
auto('operate-next-response-withheld','next')
save('operate-status-after-loss.json',auto('operate-status-after-loss','status'))
save('operate-next-reconciled.json',auto('operate-next-reconciled','next'))
save('operate-status-final.json',auto('operate-status-final','status'))
