"""Explicitly regenerate an actual historical applying fixture into a NEW directory."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile

SOURCE_COMMIT = 'a1d5e15be20a9e1fa838809b09ae3b445dafc55f'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repository', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
# Fail before generating anything if an existing fixture would be replaced.
args.output.mkdir(parents=True, exist_ok=False)
work = Path(tempfile.mkdtemp(prefix='knowledge-legacy-generator-'))
source = work / 'historical'; source.mkdir()
archive = subprocess.check_output(['git', '-C', str(args.repository), 'archive', SOURCE_COMMIT,
                                   'plugins/toolkit', 'tests/knowledge/foundation-observation'])
with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
    # git archive contains this repository's two fixed tracked prefixes.
    bundle.extractall(source)
root = work / 'execution'; root.mkdir()
installed = root / 'old-toolkit'
shutil.copytree(source / 'plugins/toolkit', installed, ignore=shutil.ignore_patterns('__pycache__'))
cli = installed / 'skills/refresh-knowledge/scripts/knowledge.py'
fixture = source / 'tests/knowledge/foundation-observation'
packet = json.loads((fixture / 'packet-fixed.json').read_text())
repo = root / 'repo'; repo.mkdir()
docs = root / 'docs'; docs.mkdir()
project = root / 'project'
trace = []

def invoke(args, data=None, expected=0):
    result = subprocess.run(list(map(str, args)), input=data, capture_output=True, cwd=root)
    trace.append({'argv':list(map(str,args)), 'rc':result.returncode,
                  'stdout':result.stdout.decode(), 'stderr':result.stderr.decode()})
    (root / 'setup-trace.json').write_text(json.dumps(trace, ensure_ascii=False, indent=2))
    assert result.returncode == expected, trace[-1]
    return result.stdout.decode()

def command(*args):
    return json.loads(invoke([sys.executable, cli, '--project', project, *args]))

invoke(['git','-C',repo,'init','-q'])
invoke(['git','-C',repo,'fast-import','--quiet'], (fixture / 'source-history.fi').read_bytes())
invoke(['git','-C',repo,'reset','--hard',packet['after']['commit']])
(docs / 'guide.md').write_text(packet['plan']['documents'][0]['before_text'])
spec = {'documents':[{'path':d['path'],'claims':d['claims']} for d in packet['bindings']['documents']]}
(root / 'spec.json').write_text(json.dumps(spec))
(root / 'decisions.json').write_text(json.dumps(packet['plan']['decisions']))
command('init','--repo',repo,'--docs',docs,'--repository','fixture/retry',
        '--baseline',packet['before']['commit'],'--path','service.py','--spec',root/'spec.json',
        '--audience',packet['audience'],'--purpose',packet['purpose'])
run = command('start','--rev',packet['after']['commit'])
command('prepare','--run',run['run'],'--decisions',root/'decisions.json')
command('review','--run',run['run'],'--review',fixture/'review-fixed.json')
interruption = """import sys,os
sys.path.insert(0,sys.argv[1])
import knowledge,workflow
original=workflow.finish
def stop(*args,**kwargs):
    original(*args,**kwargs)
    os._exit(91)
workflow.finish=stop
sys.argv=['knowledge','--project',sys.argv[2],'resume','--run',sys.argv[3]]
knowledge.main()
"""
invoke([sys.executable,'-c',interruption,cli.parent,project,run['run']], expected=91)
state=command('status','--run',run['run'])
assert state['phase']=='applying'
assert command('status')['baseline']==packet['before']['commit']
assert (docs/'guide.md').read_text()==packet['plan']['documents'][0]['after_text']
metadata={'root':str(root),'project':str(project),'run':run['run'],'old_cli':str(cli),
          'before':packet['before']['commit'],'after':packet['after']['commit'],
          'source_head':SOURCE_COMMIT}
(root/'metadata.json').write_text(json.dumps(metadata,indent=2))


with sqlite3.connect(project / 'project.sqlite3') as db:
    frozen = {'user_version': db.execute('PRAGMA user_version').fetchone()[0],
              'sql': '\n'.join(db.iterdump())}
(args.output / 'database.json').write_text(json.dumps(frozen, ensure_ascii=False, indent=2) + '\n')
shutil.copytree(project / 'runs', args.output / 'runs')
shutil.copytree(docs, args.output / 'docs')
checks = {p.relative_to(args.output).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in sorted(args.output.rglob('*')) if p.is_file()}
manifest = {'source_commit': SOURCE_COMMIT, 'run': run['run'],
            'before': packet['before']['commit'], 'after': packet['after']['commit'],
            'original_config': {'repo': str(repo), 'docs': str(docs)},
            'relocation': ['project.config.repo', 'project.config.docs'], 'sha256': checks}
(args.output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'fixture': str(args.output), 'generation_trace': str(root / 'setup-trace.json')}))
