"""Replay real independent reviews against a copied current package; no model calls."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
PLUGIN = HERE.parents[2] / 'plugins/toolkit'


def run(output):
    output.mkdir(parents=True, exist_ok=False)
    trace = []
    with tempfile.TemporaryDirectory(prefix='foundation installed ') as temporary:
        root = Path(temporary)
        installed = root / 'toolkit'
        shutil.copytree(PLUGIN, installed, ignore=shutil.ignore_patterns('__pycache__'))
        cli = installed / 'skills/refresh-knowledge/scripts/knowledge.py'
        repo = root / 'repo'; repo.mkdir()
        docs = root / 'docs'; docs.mkdir()
        project = root / 'project'
        packets = {k: json.loads((HERE / f'packet-{k}.json').read_text()) for k in ['bad', 'fixed', 'c']}
        baseline = packets['bad']['before']['commit']
        second = packets['bad']['after']['commit']
        third = packets['c']['after']['commit']

        def invoke(argv, expected=0, input_bytes=None):
            result = subprocess.run(list(map(str, argv)), input=input_bytes, capture_output=True, cwd=root)
            entry = {'argv': list(map(str, argv)), 'rc': result.returncode,
                     'stdout': result.stdout.decode(), 'stderr': result.stderr.decode()}
            trace.append(entry)
            (output / 'trace.json').write_text(json.dumps(trace, ensure_ascii=False, indent=2) + '\n')
            assert (result.returncode == 0) == (expected == 0), entry
            if expected > 1:
                assert result.returncode == expected, entry
            return entry

        def git(*args, input_bytes=None):
            return invoke(['git', '-C', repo, *args], input_bytes=input_bytes)['stdout'].strip()

        def command(*args, expected=0):
            result = invoke([sys.executable, cli, '--project', project, *args], expected)
            return json.loads(result['stdout']) if expected == 0 else result

        def save(name, value):
            path = root / name; path.write_text(json.dumps(value, ensure_ascii=False)); return path

        def intake_source(identity, kind, authority, version, text):
            return dict(id=identity, kind=kind, authority=authority, version=version,
                        locator='synthetic/' + identity, text=text, sha256=hashlib.sha256(text.encode()).hexdigest())

        git('init', '-q')
        git('fast-import', '--quiet', input_bytes=(HERE / 'source-history.fi').read_bytes())
        git('reset', '--hard', third)
        original = packets['bad']['plan']['documents'][0]['before_text']
        (docs / 'guide.md').write_text(original)
        spec = {'documents': [{'path': d['path'], 'claims': d['claims']} for d in packets['bad']['bindings']['documents']]}
        spec_path = save('spec.json', spec)
        command('doctor')
        command('init', '--repo', repo, '--docs', docs, '--repository', 'fixture/retry',
                '--baseline', baseline, '--path', 'service.py', '--spec', spec_path,
                '--audience', packets['bad']['audience'], '--purpose', packets['bad']['purpose'])
        code_source = intake_source('code', 'code', 'observed_implementation', second, packets['bad']['after']['files'][0]['text'])
        request = dict(version=1, origin='code', intent='current_behavior', sources=[code_source],
                       current={'code': 'code', 'description': 'Pinned retry implementation.'},
                       target={'sources': ['code'], 'description': 'Explain changed attempt limit and retained exceptions.',
                               'acceptance': ['Preserve ConnectionError-only retry and final error propagation.'], 'status': 'confirmed'},
                       differences=[{'kind': 'documentation', 'description': 'Guide still describes the previous limit.', 'sources': ['code']}],
                       rationale='The synthetic change intentionally raises the retry limit.')
        receipt = command('intake', '--input', save('intake-code.json', request))
        # The recorded independent reviews are v1 without intake. Keep their exact identity.
        first = command('start', '--rev', second)
        assert command('start', '--rev', second)['run'] == first['run']
        assert command('start', '--rev', third, expected=1)
        # A separate intake-bound run must reject those same recorded responses.
        legacy_project = project
        project = root / 'intake-project'
        command('init', '--repo', repo, '--docs', docs, '--repository', 'fixture/retry',
                '--baseline', baseline, '--path', 'service.py', '--spec', spec_path,
                '--audience', packets['bad']['audience'], '--purpose', packets['bad']['purpose'])
        new_intake = command('intake', '--input', root / 'intake-code.json')
        bound = command('start', '--rev', second, '--intake', new_intake['intake'])
        bound_prepared = command('prepare', '--run', bound['run'], '--decisions',
                                 save('bound-decisions.json', packets['fixed']['plan']['decisions']))
        bound_packet = json.loads(Path(bound_prepared['packet']).read_text())
        assert bound_packet['version'] == 2 and bound_packet['intake']['id'] == new_intake['intake']
        assert bound_packet['id'] != packets['fixed']['id']
        assert 'REVIEW_STALE' in command('review', '--run', bound['run'], '--review', HERE / 'review-fixed.json', expected=1)['stderr']
        assert command('status')['baseline'] == baseline and (docs / 'guide.md').read_text() == original
        project = legacy_project
        run_id = first['run']
        for key in ['bad', 'fixed']:
            prepared = command('prepare', '--run', run_id, '--decisions', save('decisions-' + key + '.json', packets[key]['plan']['decisions']))
            packet_path = Path(prepared['packet'])
            assert json.loads(packet_path.read_text()) == packets[key]
            command('review', '--run', run_id, '--review', HERE / f'review-{key}.json')
            if key == 'bad':
                assert command('resume', '--run', run_id)['phase'] == 'revise'
                assert (docs / 'guide.md').read_text() == original
        stale = command('review', '--run', run_id, '--review', HERE / 'review-bad.json', expected=1)
        assert 'REVIEW_STALE' in stale['stderr']
        exact_packet = packet_path.read_bytes(); packet_path.write_bytes(b'{')
        assert 'ARTIFACT_CORRUPT' in command('resume', '--run', run_id, expected=1)['stderr']
        assert packet_path.read_bytes() == b'{' and (docs / 'guide.md').read_text() == original
        packet_path.write_bytes(exact_packet)
        (docs / 'guide.md').write_text('Independent edit retained.')
        assert 'STALE_DOCUMENT' in command('resume', '--run', run_id, expected=1)['stderr']
        assert (docs / 'guide.md').read_text() == 'Independent edit retained.'
        (docs / 'guide.md').write_text(original)
        interruption = '''import os,sys
sys.path.insert(0,sys.argv[1])
import knowledge,workflow
original=workflow.finish
def stop(*args,**kwargs):
    original(*args,**kwargs)
    os._exit(91)
workflow.finish=stop
sys.argv=['knowledge','--project',sys.argv[2],'resume','--run',sys.argv[3]]
knowledge.main()
'''
        invoke([sys.executable, '-c', interruption, cli.parent, project, run_id], 91)
        assert command('status', '--run', run_id)['phase'] == 'applying'
        assert command('status')['baseline'] == baseline
        assert command('resume', '--run', run_id)['phase'] == 'completed'
        assert (docs / 'guide.md').read_text() == (HERE / 'document-b.md').read_text()
        next_run = command('start', '--rev', third)
        prepared = command('prepare', '--run', next_run['run'], '--decisions', save('decisions-c.json', packets['c']['plan']['decisions']))
        assert json.loads(Path(prepared['packet']).read_text()) == packets['c']
        command('review', '--run', next_run['run'], '--review', HERE / 'review-c.json')
        assert command('resume', '--run', next_run['run'])['phase'] == 'completed'
        assert command('status')['baseline'] == third
        assert (docs / 'guide.md').read_text() == (HERE / 'document-c.md').read_text()
        assert command('resume', '--run', run_id)['historical']
        # All other starting points use this same installation and project.
        target_source = intake_source('request', 'user', 'user_instruction', 'request-v1', 'Return CSV headers for empty lists; reject unauthorized requests without a file.')
        request.update(origin='user', intent='behavior_change', sources=[target_source],
                       current={'code': None, 'description': 'No export implementation.'},
                       target={'sources': ['request'], 'description': target_source['text'],
                               'acceptance': ['Empty list: headers only.', 'Unauthorized: no file and reject.'], 'status': 'confirmed'},
                       differences=[{'kind': 'behavior', 'description': 'Export must be implemented.', 'sources': ['request']}],
                       rationale='Preserve target and hand off to stage 3.')
        user = command('intake', '--input', save('intake-user.json', request))
        assert user['phase'] == 'pending_implementation'
        assert command('intake-status', '--intake', user['intake'])['input']['current']['code'] is None
        assert 'INTAKE_ROUTE' in command('start', '--rev', third, '--intake', user['intake'], expected=1)['stderr']
        document_source = intake_source('document', 'document', 'context', 'spec-v1', 'Target: export empty lists as CSV headers.')
        request.update(origin='document', sources=[target_source, document_source])
        doc_target = command('intake', '--input', save('intake-doc-target.json', request))
        assert doc_target['phase'] == 'pending_implementation'
        request.update(intent='wording_only', sources=[document_source],
                       target={'sources': ['document'], 'description': 'Same export goal, clarified wording.',
                               'acceptance': ['Preserve conditions and pending implementation.'], 'status': 'confirmed'},
                       differences=[{'kind': 'wording', 'description': 'Only wording changed.', 'sources': ['document']}],
                       rationale='Compare before/after prose, without implementing the goal.')
        wording = command('intake', '--input', save('intake-wording.json', request))
        assert wording['phase'] == 'no_code_work'
        assert command('intake-status', '--intake', wording['intake'])['document_quality'] == 'not_evaluated'
        dependency = installed / 'skills/review-knowledge/SKILL.md'
        dependency.rename(dependency.with_suffix('.held'))
        assert 'DEPENDENCY_UNREACHED' in command('start', '--rev', third, expected=1)['stderr']
        dependency.with_suffix('.held').rename(dependency)
        # End a new run, then quarantine this project and explicitly initialize its successor.
        git('config', 'user.name', 'Foundation fixture'); git('config', 'user.email', 'fixture@example.invalid')
        source = repo / 'service.py'; source.write_text(source.read_text() + '\n# New documentation scope\n')
        git('add', '.'); git('commit', '-qm', 'next scope')
        revision = git('rev-parse', 'HEAD')
        abandoned = command('start', '--rev', revision)
        reason = root / 'reason.txt'; reason.write_text('Scope changed; preserve evidence and review a successor baseline.')
        command('terminate', '--run', abandoned['run'], '--reason-file', reason)
        assert 'RUN_TERMINATED' in command('start', '--rev', revision, expected=1)['stderr']
        successor = root / 'successor'
        command('retire', '--reason-file', reason, '--successor', successor)
        assert 'PROJECT_RETIRED' in command('start', '--rev', revision, expected=1)['stderr']
        assert command('status')['baseline'] == third
        old_project = project; project = successor
        next_spec = {'documents': [{'path': d['path'], 'claims': d['claims']} for d in packets['c']['plan']['next_bindings']['documents']]}
        command('init', '--repo', repo, '--docs', docs, '--repository', 'fixture/retry', '--baseline', third,
                '--path', 'service.py', '--spec', save('successor-spec.json', next_spec),
                '--audience', packets['c']['audience'], '--purpose', 'Reviewed successor after scope change')
        assert command('start', '--rev', revision)['phase'] == 'awaiting_decisions'
        assert (old_project / 'retired.json').exists()
        (output / 'result.json').write_text(json.dumps({'status': 'pass', 'review_source': 'preserved v1 independent responses on no-intake runs; no new model invocation', 'intake_validation': 'v2 rejects historical v1 response; no new semantic review claimed',
            'baseline': third, 'document': (docs / 'guide.md').read_text(),
            'installation_hashes': {str(p.relative_to(installed)): hashlib.sha256(p.read_bytes()).hexdigest()
                                    for p in sorted(installed.rglob('*')) if p.is_file() and '__pycache__' not in p.parts},
            'scope': ['two changes', 'real review rejection/repair replay', 'stale review', 'corrupt packet', 'independent edit',
                      'process exit/reentry', 'all intake origins', 'intake-bound stale review rejection', 'missing skill', 'terminate/retire/successor']},ensure_ascii=False,indent=2)+'\n')
    print('PASS: installed integrated replay; preserved reviews, not a new agent execution')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--out',type=Path,required=True)
    run(parser.parse_args().out)
