"""Portable, scoped history transfer; originals and foreign DB objects stay untouched."""
import json
from common import digest
from notebook_store import configuration, database, safe_path, require


def write_new(path, value, reuse=False):
    path = safe_path(path)
    if path.exists():
        require(reuse and json.loads(path.read_text(encoding='utf-8')) == value,
                'artifact exists with different content or overwrite was not requested')
        return str(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='utf-8') as file:
        file.write(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2))
    return str(path)


def backup(root, output):
    from observations import notebook_scope, read_snapshot
    scope = notebook_scope(root, required=True)
    view, rows = read_snapshot(root, scope['source'])
    payload = {'version': 1, 'scope': {k: scope[k] for k in ('source', 'audience')}, 'records': rows}
    bundle = {**payload, 'digest': digest(payload)}
    return {'output': write_new(output, bundle), 'records': len(rows), 'digest': bundle['digest']}


def restore(root, input_path):
    from observations import records, append_record, shape, strings, AUDIENCES
    config = configuration(root)
    require(config is not None, 'restore needs an initialized configured notebook')
    require('notes' not in config, 'restore into a notebook with DB-managed notes; preserve external originals separately')
    bundle = json.loads(safe_path(input_path).read_text(encoding='utf-8'))
    shape(bundle, ('version', 'scope', 'records', 'digest'))
    payload = {k: bundle[k] for k in ('version', 'scope', 'records')}
    require(type(bundle['version']) is int and bundle['version'] == 1 and digest(payload) == bundle['digest'],
            'invalid notebook backup version or digest')
    shape(bundle['scope'], ('source', 'audience'))
    strings(bundle['scope'], ('source',))
    require(bundle['scope']['audience'] in AUDIENCES and isinstance(bundle['records'], list), 'invalid backup scope or records')
    with database(root, write=True) as db:
        require({k: db.scope[k] for k in ('source', 'audience')} == bundle['scope'], 'backup scope differs from notebook')
        existing = records(db)
        if existing:
            require(existing == bundle['records'], 'restore destination must be empty or exactly match the backup')
            return {'created': False, 'records': len(existing)}
        for record in bundle['records']:
            shape(record, ('id', 'kind', 'value'))
            require(record['id'] == digest({'kind': record['kind'], 'value': record['value']}), 'backup record hash mismatch')
            result = append_record(db, record['kind'], record['value'])
            require(result['created'], 'duplicate backup record')
        require(records(db) == bundle['records'], 'restored history differs')
    return {'created': True, 'records': len(bundle['records'])}
