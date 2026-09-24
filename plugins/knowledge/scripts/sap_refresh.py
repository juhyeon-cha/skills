"""Explicit, bounded SAP recollection followed by notebook import and writer handoff."""
import json
import os
from contextlib import contextmanager
from pathlib import Path
import subprocess
from datetime import datetime, timezone

from observations import append, read, require, safe_path, shape, strings, timestamp, database, records, check_scope, notebook_scope
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


@contextmanager
def refresh_lock(root):
    # Keep this file: unlinking a locked inode would let another writer bypass it.
    lock = safe_path(root / 'sap-refresh.lock')
    with lock.open('a+b') as file:
        if os.name == 'nt':
            import msvcrt
            if file.tell() == 0:
                file.write(b'0')
                file.flush()
            file.seek(0)
            msvcrt.locking(file.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            yield
        finally:
            if os.name == 'nt':
                file.seek(0)
                msvcrt.locking(file.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(file.fileno(), fcntl.LOCK_UN)


def refresh(root, plan_path, output):
    plan = validate_plan(json.loads(plan_path.read_text(encoding='utf-8')))
    root, output = safe_path(root), safe_path(output)
    check_scope(root, plan['source'])
    require(root != safe_path(plan['db']).parent, 'keep notebook separate from SAP DB directory')
    # Inspect all selected objects before the first network request. No guessed identities.
    before = {item['id']: exported(plan, item) for item in plan['objects']}
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    with refresh_lock(root):
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


def wiki(root, source, output, node, markdown_it, publish=None):
    from observation_wiki import export
    scope = notebook_scope(root, required=True)
    view = read(root, source)
    output = safe_path(output)
    if publish is not None:
        publish = safe_path(publish)
        require(publish in output.parents, 'wiki output must be a new child of its stable publication root')
        owner = publish / 'scope.json'
        safe_path(owner)
        safe_path(publish / 'index.html')
        if owner.exists():
            require(json.loads(owner.read_text(encoding='utf-8')) == scope, 'wiki publication scope mismatch')
        else:
            require(not publish.exists() or not any(publish.iterdir()), 'publication root is not an empty knowledge wiki')
            publish.mkdir(parents=True, exist_ok=True, mode=0o700)
            with owner.open('x', encoding='utf-8') as file:
                file.write(json.dumps(scope, ensure_ascii=False))
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    from urllib.parse import quote
    base_path = '/' + quote((output / 'site').relative_to(publish).as_posix(), safe='/') + '/' if publish else '/'
    export(view, output / 'content', base_path)
    scripts = Path(__file__).resolve().parent / 'wiki'
    for command in ([node, str(scripts / 'build.mjs'), str(output / 'content'), str(output / 'site'), str(markdown_it)],
                    [node, str(scripts / 'check.mjs'), str(output / 'content/manifest.json'), str(output / 'site')]):
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        require(result.returncode == 0, 'wiki build/check failed; preserve output and inspect runtime dependencies')
    if publish is not None:
        import os
        import tempfile
        from urllib.parse import quote
        target = quote((output / 'site/index.html').relative_to(publish).as_posix(), safe='/')
        content = ('<!doctype html><html lang="ko"><meta charset="utf-8">'
                   '<meta http-equiv="refresh" content="0;url=' + target + '">'
                   '<title>내 지식</title><a href="' + target + '">내 지식 열기</a></html>')
        # Only checked snapshots become the entry point; a failed build leaves it unchanged.
        safe_path(publish / 'index.html')
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=publish, delete=False) as file:
            file.write(content)
            temporary = file.name
        import hashlib
        from common import digest
        receipt = {'revision': digest(view), 'published_at': datetime.now(timezone.utc).isoformat(),
                   'entry_hash': hashlib.sha256(content.encode('utf-8')).hexdigest()}
        receipt_path = safe_path(publish / 'published.json')
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=publish, delete=False) as file:
            json.dump(receipt, file, ensure_ascii=False)
            receipt_temp = file.name
        os.replace(receipt_temp, receipt_path)
        os.replace(temporary, publish / 'index.html')
    return {'ok': True, 'entry': str(publish / 'index.html') if publish else None,
            'index': str(output / 'site/index.html'),
            'site': str(output / 'site'), 'scope': 'Local static wiki snapshot; serve on loopback to use search.'}
