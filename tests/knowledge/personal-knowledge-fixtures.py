#!/usr/bin/env python3
"""Generate replayable public-CLI scenario transcripts using synthetic inputs only."""
import argparse
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('checks', Path(__file__).with_name('personal-knowledge-check.py'))
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


def generate(output):
    output.mkdir(parents=True, exist_ok=False)
    for scenario in ('personal', 'supported', 'conflicting', 'stale', 'missing', 'ambiguous'):
        case = checks.PersonalKnowledge()
        case.setUp()
        calls = []
        submit = case.submit

        def record(command, value, **kwargs):
            result = submit(command, value, **kwargs)
            calls.append({'command': command, 'input': value, 'response': result})
            return result

        case.submit = record
        try:
            evidence = case.observation() if scenario in ('supported', 'stale') else None
            identity = case.define(evidence=[evidence] if evidence else [])['id']
            if evidence:
                case.review(identity)
            if scenario == 'conflicting':
                case.define(key='alternative', definition='제품 L300')
            if scenario == 'stale':
                case.observation(revision='2', status='partial', observed_at='2026-09-02T00:00:00Z')
            query = {'missing': '배터리 가용 재고', 'ambiguous': '윤활 제품 판매 개수'}.get(scenario)
            result = case.retrieve(query=query) if query else case.retrieve()
            expected = {'personal': 'matched', 'supported': 'matched', 'conflicting': 'conflicting',
                        'stale': 'stale', 'missing': 'no_match', 'ambiguous': 'ambiguous'}[scenario]
            assert result['outcome'] == expected
            (output / (scenario + '.json')).write_text(json.dumps({
                'fixture_version': 1, 'scenario': scenario, 'synthetic': True,
                'initialize': {'source': case.note['source'], 'audience': 'user'},
                'calls': calls}, ensure_ascii=False, indent=2) + '\n')
        finally:
            case.doCleanups()
    print(json.dumps({'output': str(output), 'scenarios': 6, 'live_accuracy_verified': False}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    generate(parser.parse_args().output)
