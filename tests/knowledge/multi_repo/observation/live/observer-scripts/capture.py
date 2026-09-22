"""Local experiment command capture; stdout remains the observed process output."""
import datetime, hashlib, json, subprocess, sys, time
from pathlib import Path
out=Path(sys.argv[1]); cwd=sys.argv[2]; args=sys.argv[3:]
started=datetime.datetime.now(datetime.timezone.utc).isoformat(); tick=time.monotonic()
p=subprocess.run(args,cwd=cwd,text=True,capture_output=True)
record={"argv":args,"cwd":cwd,"started_at":started,"finished_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),"elapsed_seconds":time.monotonic()-tick,"exit_code":p.returncode,"stdout":p.stdout,"stderr":p.stderr}
out.parent.mkdir(parents=True,exist_ok=True)
with out.open("x") as f: json.dump(record,f,ensure_ascii=False,indent=2)
print(p.stdout,end=""); print(p.stderr,end="",file=sys.stderr)
sys.exit(p.returncode)
