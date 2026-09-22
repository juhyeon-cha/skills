"""Verify recorded evidence integrity; does not replay or impersonate model calls."""
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read(path):
    return json.loads(path.read_text())

def verify(root):
    manifest = read(root / 'manifest.json')
    paths = set()
    for entry in manifest['files']:
        relative = Path(entry['path'])
        assert not relative.is_absolute() and '..' not in relative.parts, relative
        assert str(relative) not in paths, relative
        paths.add(str(relative))
        target = root / relative
        assert target.is_file(), relative
        assert target.stat().st_size == entry['bytes'], relative
        assert digest(target) == entry['sha256'], relative
        if 'multi-state' in relative.parts and 'objects' in relative.parts:
            assert target.stem == digest(target), relative
    actual = {str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() and p != root / 'manifest.json'}
    assert paths == actual, ('manifest file set differs', paths ^ actual)
    runtime = read(root / 'runtime-source/identity.json')
    for name, expected in runtime['scripts'].items():
        assert digest(root / 'runtime-source' / name) == expected, name
    frozen = read(root / 'comparison-checkpoints.json')
    assert digest(root / 'comparison-checkpoints.json') == (root / 'comparison-checkpoints.sha256').read_text().strip()
    assert [q['id'] for q in frozen['questions']] == [f'Q{i}' for i in range(1, 7)]
    navigation = []
    for q in frozen['questions']:
        directory = root / 'checkpoints' / q['id']
        retrieval = read(directory / 'retrieval.json')
        baseline, candidate = read(directory / 'baseline.json'), read(directory / 'candidate.json')
        assert baseline['question'] == candidate['question'] == {k: q[k] for k in ('id', 'question')}
        assert baseline['principal'] == candidate['principal'] == retrieval['principal']
        for name, expected in retrieval['files'].items():
            assert digest(directory / name) == expected, (q['id'], name)
        assert retrieval['baseline']['retrieval_operation_count'] == len(retrieval['baseline']['operations'])
        assert retrieval['candidate']['retrieval_operation_count'] == 2
        navigation.append({'question': q['id'], 'baseline': retrieval['baseline']['retrieval_operation_count'], 'candidate': 2})
    for flow in ('code-first', 'document-first'):
        directory = root / flow
        for phase, prefix in (('partial', 'producer-partial'), ('full', 'full')):
            raw = read(root / f'{phase}-review-raw.json')
            actual = next(r['response'] for r in raw['reviews'] if r['flow'] == flow)
            receipt = read(directory / f'{prefix}-attest-input.json')
            completion = read(root / f'{phase}-review-completion.json')
            packet = read(directory / f'{prefix}-packet-output.json')
            assert receipt['response'] == json.loads(receipt['raw_response']) == actual
            assert receipt['actor'] == completion['actor'] != receipt['author']
            assert receipt['packet'] == packet['packet'] == actual['packet']
            assert receipt['prompt_sha256'] == packet['prompt_sha256']
            assert receipt['synthetic'] is False
            review_id = read(directory / f'{prefix}-attest-output.json')['review']
            assert read(directory / 'multi-state/objects' / f'{review_id}.json') == receipt
        for member in ('producer', 'consumer'):
            raw = read(root / f'{member}-doc-review-raw.json')
            actual = next(r['response'] for r in raw['reviews'] if r['flow'] == flow)
            assert read(directory / f'{member}-doc-model-review.json') == actual
            imported = read(directory / f'{member}-doc-review-import.json')
            # Manifest preserves observed paths while the archive keeps their relative layout.
            observed = Path(imported['review']['path']).relative_to('/private/tmp/stage5-work/live')
            assert read(root / observed) == actual
            complete_path = directory / f'{member}-project/runs' / imported['run'] / 'complete.json'
            complete_record = read(complete_path)
            assert complete_record['review'] == imported['review']['id']
            assert complete_record['packet'] == actual['packet'] and complete_record['status'] == 'applied'
        partial = read(directory / 'producer-only-query-output.json')
        assert partial['completion'] == 'incomplete'
        members = {m['repository']: m for m in partial['members']}
        assert members['svc-producer']['validation'] == 'verified'
        assert members['svc-consumer']['validation'] != 'verified'
        checks = read(directory / 'producer-only-checks-output.json')['checks']
        assert {c['check']: c['exit_code'] for c in checks} == {'producer-total': 0, 'consumer-total': 1, 'exchange-total': 1}
        complete = read(directory / 'complete-query-output.json')
        assert complete['completion'] == 'complete' and complete['integration'] == 'verified'
        assert all(m['validation'] == 'verified' and m['evidence']['review_synthetic'] is False for m in complete['members'])
        assert read(directory / 'complete-wiki-output.json')['served'] == 'current'
        assert all(c['exit_code'] == 0 for c in read(directory / 'both-complete-checks-output.json')['checks'])
        compare = read(directory / 'comparison-feedback-output.json')
        assert compare['omissions'] == ['svc-consumer'] and not compare['unresolved']
        assert compare['feedback_count'] == 2
    code = root / 'code-first'
    failed_publication = read(code / 'source-unavailable-publish-output.json')
    assert failed_publication['outcome'] == 'partial'
    assert failed_publication['members'] == {'svc-consumer': 'failed', 'svc-producer': 'published'}
    assert read(code / 'source-restored-publish-output.json')['outcome'] == 'published'
    assert read(code / 'relocated-query-output.json')['completion'] == 'complete'
    restricted = read(root / 'checkpoints/Q4/candidate.json')
    assert restricted['query']['withheld_count'] == 1 and restricted['query']['completion'] == 'incomplete'
    assert 'svc-consumer' not in json.dumps(restricted)
    stale = read(root / 'checkpoints/Q5/candidate.json')
    assert stale['query']['index'] == 'stale' and stale['wiki']['served'] != 'current'
    withdrawn = read(root / 'checkpoints/Q6/candidate.json')
    assert withdrawn['query']['status'] == 'withdrawn' and withdrawn['query']['completion'] == 'incomplete'
    assert all('total' in m['current']['files'][0]['text'] for m in withdrawn['query']['members'])
    commands = [json.loads(line) for line in (root / 'commands.jsonl').read_text().splitlines()]
    assert commands
    for command in commands:
        assert isinstance(command['argv'], list) and command['argv']
        assert isinstance(command['exit_code'], int)
        assert command['elapsed_seconds'] >= 0
        assert isinstance(command['stdout'], str) and isinstance(command['stderr'], str)
        assert command['started_at'] <= command['finished_at']
        if command.get('script_sha256'):
            assert re.fullmatch('[a-f0-9]{64}', command['script_sha256'])
            assert command['script_sha256'] in runtime['scripts'].values()
    calls = []
    for name in ('producer-doc-review', 'consumer-doc-review', 'partial-review', 'full-review',
                 'comparison-baseline-reader', 'comparison-candidate-reader', 'comparison-grader'):
        intent = read(root / f'{name}-dispatch-intent.json')
        dispatch = read(root / f'{name}-dispatch.json')
        completion = read(root / f'{name}-completion.json')
        assert digest(root / f'{name}-prompt.md') == intent['prompt_sha256']
        assert digest(root / f'{name}-raw.json') == completion['raw_sha256']
        assert dispatch['return']['task_name'] == completion['actor']
        assert completion['actor'] != '/root'
        assert intent['synthetic'] is completion['synthetic'] is False
        assert completion['usage_tokens'] is None and completion['money'] is None
        elapsed = (datetime.fromisoformat(completion['finished_at']) - datetime.fromisoformat(completion['started_at'])).total_seconds()
        assert elapsed >= 0
        calls.append({'group': name, 'actor': completion['actor'], 'intent_to_preservation_seconds': elapsed})
        for filename, expected in intent.get('inputs', {}).items():
            assert digest(root / filename) == expected
        if 'input_sha256' in intent:
            assert digest(root / Path(intent['input']).name) == intent['input_sha256']
    actors = {c['group']: c['actor'] for c in calls}
    assert len({actors[n] for n in ('comparison-baseline-reader', 'comparison-candidate-reader', 'comparison-grader')}) == 3
    grading = read(root / 'comparison-grader-raw.json')
    for mode in ('baseline', 'candidate'):
        result = grading[mode]
        assert result['verdict'] == 'pass'
        assert {q['id'] for q in result['questions']} == {f'Q{i}' for i in range(1, 7)}
        assert len(result['questions']) == 6
        assert all(q[key] == 'pass' for q in result['questions'] for key in ('correctness', 'grounding', 'privacy'))
    assert read(root / 'baseline-review-result-1.json')['accepted'] is False
    assert read(root / 'baseline-review-result-2.json')['binding_valid'] is True
    for name, expected in read(root / 'freeze.json').items():
        assert digest(root / name) == expected
    return {'files_verified': len(paths), 'commands_recorded': len(commands), 'retrieval_operations': navigation,
            'receipt_relationships': calls,
            'boundary': 'Recorded bytes and receipt relationships only; semantic judgments remain independent model observations.'}

if __name__ == '__main__':
    import sys
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent / 'live'
    print(json.dumps(verify(root), ensure_ascii=False, indent=2))
