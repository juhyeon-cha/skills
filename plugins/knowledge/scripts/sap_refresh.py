"""Explicit, bounded SAP recollection followed by notebook import and writer handoff."""
import json
from pathlib import Path
import subprocess
from datetime import datetime, timezone

from observations import append, read, require, safe_path, shape, strings, timestamp, database, records
from sap_observations import adapt_sap_graph


def validate_plan(plan):
    shape(plan, ('version', 'cli', 'producer_version', 'db', 'source', 'tenant', 'level', 'objects'))
    require(plan['version'] == 1, 'unsupported SAP refresh plan version')
    strings(plan, ('producer_version', 'db', 'source', 'tenant', 'level'))
    require(isinstance(plan['cli'], list) and 1 <= len(plan['cli']) <= 2
            and all(isinstance(x, str) and Path(x).is_absolute() and Path(x).is_file() for x in plan['cli']),
            'cli must be an absolute executable, optionally followed by an absolute CLI script')
    require(Path(plan['db']).is_absolute() and safe_path(plan['db']).is_file(), 'use an existing explicit SAP DB')
    require(isinstance(plan['objects'], list) and 1 <= len(plan['objects']) <= 20, 'select 1 to 20 objects')
    ids = set()
    for item in plan['objects']:
        shape(item, ('id', 'type', 'name'))
        strings(item, ('id', 'type', 'name'))
        require(item['type'] in ('DDLS', 'CLAS'), 'unsupported SAP object type')
        require(item['id'] not in ids, 'duplicate object ID')
        ids.add(item['id'])
    return plan


def call(plan, arguments):
    # SAP owns credentials and source binding. No shell or credential arguments.
    return subprocess.run([*plan['cli'], 'graph', *arguments, '--db', plan['db']],
                          stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=180)


def exported(plan, item):
    result = call(plan, ['show-id', item['id']])
    require(result.returncode == 0, 'SAP local export failed; inspect the SAP CLI separately')
    raw = json.loads(result.stdout)
    value = adapt_sap_graph(raw, producer_version=plan['producer_version'])
    require((value['source'], value['object'], raw['observation']['object_type'], raw['observation']['source_key'])
            == (plan['source'], item['id'], item['type'], item['name']), 'refresh selection identity mismatch')
    return value


def refresh(root, plan_path, output):
    plan = validate_plan(json.loads(plan_path.read_text(encoding='utf-8')))
    root, output = safe_path(root), safe_path(output)
    require(root != safe_path(plan['db']).parent, 'keep notebook separate from SAP DB directory')
    # Inspect all selected objects before the first network request. No guessed identities.
    before = {item['id']: exported(plan, item) for item in plan['objects']}
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock = root / 'sap-refresh.lock'
    safe_path(lock)
    with lock.open('x'):
        pass
    try:
        output.mkdir(parents=True, exist_ok=False, mode=0o700)
        existing = []
        if (root / 'observations.sqlite').exists():
            with database(root) as db:
                existing = records(db)
        for value in before.values():
            # An upgraded exporter can read the exact old observation. Preserve
            # its original producer attribution instead of relabeling history.
            def comparable(observation):
                return {**observation, 'metadata': {k: v for k, v in observation['metadata'].items()
                        if k != 'producer_version'}}
            if not any(row['kind'] == 'observation' and comparable(row['value']) == comparable(value)
                       for row in existing):
                append(root, 'observation', value)
        report = {'ok': True, 'source': plan['source'], 'attempts': [], 'output': str(output)}
        for item in plan['objects']:
            started = datetime.now(timezone.utc).isoformat()
            attempt = {'object': item['id'], 'name': item['name'], 'started_at': started}
            try:
                result = call(plan, ['collect', '--type', item['type'], '--objects', item['name'],
                                     '--source', plan['source'], '--tenant', plan['tenant'], '--level', plan['level']])
                attempt['exit_code'] = result.returncode
                value = exported(plan, item)
                require(timestamp(value['observed_at']) > timestamp(before[item['id']]['observed_at']),
                        'collection produced no newer observation; old success is not this attempt')
                attempt.update(append(root, 'observation', value))
                attempt['status'] = value['status']
                attempt['ok'] = result.returncode == 0 and value['status'] == 'complete'
            except (ValueError, OSError, subprocess.TimeoutExpired) as error:
                # Keep a bounded diagnosis, never arbitrary SAP stdout, auth URLs or credentials.
                attempt.update(ok=False, status='collection_unverified', error=type(error).__name__)
            report['attempts'].append(attempt)
            report['ok'] = report['ok'] and attempt['ok']
            (output / 'collection.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
            if attempt['status'] == 'collection_unverified':
                break  # Authentication/identity/timeouts require a human check, not repeated logins.
        view = read(root, plan['source'])
        handoff = {'source': plan['source'], 'collection_ok': report['ok'],
                   'documents': [d for d in view['documents'] if d['status'] != 'current'],
                   'observations': view['observations'], 'notes': view['notes'],
                   'instruction': 'Compare exact evidence, update only relevant explanations, preserve key/purpose/version and previous ID; obtain a real independent review. Collection is not semantic approval.'}
        (output / 'handoff.json').write_text(json.dumps(handoff, ensure_ascii=False, indent=2), encoding='utf-8')
        report['pending_documents'] = len(handoff['documents'])
        report['handoff'] = str(output / 'handoff.json')
        report['scope'] = 'One bounded refresh; no scheduler or automatic semantic approval. See collection.json even when prior documents remain current.'
        (output / 'collection.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        return report
    finally:
        lock.unlink()


def wiki(root, source, output, node, markdown_it):
    from observation_wiki import export
    output = safe_path(output)
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    export(read(root, source), output / 'content')
    scripts = Path(__file__).resolve().parent / 'wiki'
    for command in ([node, str(scripts / 'build.mjs'), str(output / 'content'), str(output / 'site'), str(markdown_it)],
                    [node, str(scripts / 'check.mjs'), str(output / 'content/manifest.json'), str(output / 'site')]):
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        require(result.returncode == 0, 'wiki build/check failed; preserve output and inspect runtime dependencies')
    return {'ok': True, 'index': str(output / 'site/index.html'),
            'site': str(output / 'site'), 'scope': 'Local static wiki snapshot; serve on loopback to use search.'}
