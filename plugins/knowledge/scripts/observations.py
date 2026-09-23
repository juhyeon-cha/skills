"""Append-only local knowledge for explicitly supplied, non-Git observations.

This is a local owner's notebook, not a multi-user authorization service. Review
identities are caller attestations; the orchestrator must supply a real independent
judgment. Neither an import nor a stored hash attests semantic correctness.
"""
from contextlib import contextmanager
from datetime import datetime
import json
from pathlib import Path

from common import digest

APPLICATION = 0x4B4E4231
KINDS = {'observation', 'document', 'note', 'review'}
AREAS = {'usage', 'development', 'domain'}
AUDIENCES = {'user', 'developer'}


def require(value, message):
    if not value:
        raise ValueError('INPUT: ' + message)


def shape(value, fields, optional=()):
    require(isinstance(value, dict) and set(fields) <= set(value)
            and set(value) <= set(fields) | set(optional), 'unexpected or missing fields')


def strings(value, fields):
    for field in fields:
        require(isinstance(value[field], str) and bool(value[field].strip()), field + ' must be nonempty text')


def timestamp(value):
    require(isinstance(value, str), 'observed_at must be a timezone timestamp')
    try:
        result = datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError as error:
        raise ValueError('INPUT: invalid observed_at') from error
    require(result.tzinfo is not None, 'observed_at must include a timezone')
    return result


def validate(kind, value):
    if kind == 'observation':
        shape(value, ('source', 'object', 'revision', 'observed_at', 'status', 'title', 'body', 'metadata'))
        strings(value, ('source', 'object', 'revision', 'title', 'body'))
        timestamp(value['observed_at'])
        require(value['status'] in ('complete', 'partial', 'failed', 'removed'), 'invalid observation status')
        require(isinstance(value['metadata'], dict) and all(isinstance(k, str) and isinstance(v, str)
                for k, v in value['metadata'].items()), 'metadata must contain text values')
    elif kind == 'document':
        shape(value, ('key', 'source', 'title', 'audience', 'area', 'purpose', 'product_version',
                      'author', 'body', 'evidence', 'previous'))
        strings(value, ('key', 'source', 'title', 'purpose', 'product_version', 'author', 'body'))
        require(value['audience'] in AUDIENCES and value['area'] in AREAS, 'invalid audience or area')
        require(isinstance(value['evidence'], list) and value['evidence'] and
                all(isinstance(x, str) for x in value['evidence']) and
                len(set(value['evidence'])) == len(value['evidence']), 'evidence must be distinct observation IDs')
        require(value['previous'] is None or isinstance(value['previous'], str), 'invalid previous document ID')
    elif kind == 'note':
        shape(value, ('source', 'object', 'author', 'body', 'origin'))
        strings(value, ('source', 'object', 'author', 'body', 'origin'))
    elif kind == 'review':
        shape(value, ('document', 'reviewer', 'verdict', 'reason'))
        strings(value, ('document', 'reviewer', 'reason'))
        require(value['verdict'] in ('pass', 'revise', 'blocked'), 'invalid review verdict')
    else:
        raise ValueError('INPUT: unsupported record kind')


def safe_path(path):
    require('..' not in Path(path).parts, 'parent traversal is unsupported in notebook paths')
    path = Path(path).absolute()
    require(not any(p.is_symlink() for p in (path, *path.parents)), 'symlink notebook paths are unsupported')
    return path


def notebook_scope(root, required=False):
    file = safe_path(root) / 'scope.json'
    safe_path(file)
    if not file.exists():
        require(not required, 'wiki needs a scoped notebook; initialize a separate user or developer notebook')
        return None
    scope = json.loads(file.read_text(encoding='utf-8'))
    shape(scope, ('version', 'source', 'audience'), ('notes',))
    strings(scope, ('source',))
    require(scope['version'] == 1 and scope['audience'] in AUDIENCES, 'invalid notebook scope')
    if 'notes' in scope:
        require(isinstance(scope['notes'], str) and Path(scope['notes']).is_absolute(), 'notes path must be absolute')
        safe_path(scope['notes'])
    return scope


def initialize(root, source, audience, notes=None):
    require(isinstance(source, str) and bool(source.strip()) and audience in AUDIENCES, 'invalid notebook scope')
    root = safe_path(root)
    scope = {'version': 1, 'source': source, 'audience': audience}
    if notes is not None:
        require(Path(notes).is_absolute(), 'notes path must be absolute')
        scope['notes'] = str(safe_path(notes))
    existing = notebook_scope(root)
    if existing:
        require(existing == scope, 'notebook scope cannot change')
        return {**scope, 'created': False, 'root': str(root)}
    require(not (root / 'observations.sqlite').exists(),
            'preserve the unscoped notebook; initialize a new directory and explicitly select records to copy')
    if notes is not None:
        require(safe_path(notes) != root, 'personal notes must use a separate directory')
        notes_scope(scope, create=True)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (root / 'scope.json').open('x', encoding='utf-8') as file:
        file.write(json.dumps(scope, ensure_ascii=False, indent=2))
    return {**scope, 'created': True, 'root': str(root)}


def check_scope(root, source=None, audience=None):
    scope = notebook_scope(root)
    if scope:
        require(source is None or source == scope['source'], 'notebook source mismatch')
        require(audience is None or audience == scope['audience'], 'notebook audience mismatch')
    return scope


def notes_scope(scope, create=False):
    directory = safe_path(scope['notes'])
    owner = safe_path(directory / '.notebook-scope')
    expected = {k: scope[k] for k in ('version', 'source', 'audience')}
    if owner.exists():
        require(json.loads(owner.read_text(encoding='utf-8')) == expected, 'personal notes scope mismatch')
    else:
        require(create, 'personal notes scope is missing')
        require(not directory.exists() or not any(directory.glob('*.json')),
                'preserve existing unscoped note files; select a new personal note directory')
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        with owner.open('x', encoding='utf-8') as file:
            file.write(json.dumps(expected, ensure_ascii=False))
    return directory


def personal_notes(root, rows):
    scope = notebook_scope(root)
    if not scope or 'notes' not in scope:
        return []
    directory = notes_scope(scope)
    result = []
    known = latest_observations(rows)
    for file in sorted(directory.glob('*.json')):
        safe_path(file)
        value = json.loads(file.read_text(encoding='utf-8'))
        validate('note', value)
        identity = digest({'kind': 'note', 'value': value})
        require(file.stem == identity and value['source'] == scope['source'] and
                (value['source'], value['object']) in known, 'personal note scope or identity mismatch')
        result.append({'id': identity, 'kind': 'note', 'value': value})
    return result


@contextmanager
def database(root, write=False, create=False):
    import sqlite3
    root = safe_path(root)
    file = root / 'observations.sqlite'
    fresh = not file.exists()
    if fresh:
        require(write and create, 'notebook does not exist; import an observation first')
        root.mkdir(parents=True, exist_ok=True)
        # Exclusive file creation prevents a racing initializer from claiming another DB.
        with file.open('xb'):
            pass
    safe_path(file)
    db = sqlite3.connect(file.as_uri() + ('?mode=rw' if write else '?mode=ro'), uri=True, timeout=0)
    try:
        if write:
            db.execute('BEGIN IMMEDIATE')
        if fresh:
            db.execute('CREATE TABLE records (seq INTEGER PRIMARY KEY, id TEXT UNIQUE NOT NULL, kind TEXT NOT NULL, body TEXT NOT NULL)')
            db.execute(f'PRAGMA application_id={APPLICATION}')
            db.execute('PRAGMA user_version=1')
        require(db.execute('PRAGMA application_id').fetchone()[0] == APPLICATION and
                db.execute('PRAGMA user_version').fetchone()[0] == 1,
                'unsupported notebook database; preserve it and use a new directory')
        scope = notebook_scope(root)
        if scope:
            require(all(r['value'].get('source', scope['source']) == scope['source'] and
                        (r['kind'] != 'document' or r['value']['audience'] == scope['audience'])
                        for r in records(db)), 'notebook contains records outside its declared scope')
        yield db
        if write:
            db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def records(db):
    result = []
    for seq, identity, kind, body in db.execute('SELECT seq,id,kind,body FROM records ORDER BY seq'):
        value = json.loads(body)
        validate(kind, value)
        require(digest({'kind': kind, 'value': value}) == identity, 'record hash mismatch')
        result.append({'id': identity, 'kind': kind, 'value': value})
    return result


def latest_observations(rows):
    latest = {}
    for row in rows:
        if row['kind'] != 'observation':
            continue
        value = row['value']
        key = (value['source'], value['object'])
        if key not in latest or timestamp(value['observed_at']) > timestamp(latest[key]['value']['observed_at']):
            latest[key] = row
    return latest


def document_state(document, rows):
    by_id = {r['id']: r for r in rows}
    latest = latest_observations(rows)
    dependencies = []
    for identity in document['value']['evidence']:
        evidence = by_id[identity]['value']
        current = latest[(evidence['source'], evidence['object'])]
        dependencies.append({'bound': identity, 'latest': current['id'], 'object': evidence['object'],
                             'status': current['value']['status']})
    reviews = [r for r in rows if r['kind'] == 'review' and r['value']['document'] == document['id']]
    review = reviews[-1] if reviews else None
    if any(d['status'] != 'complete' for d in dependencies):
        status = 'evidence_pending'
    elif any(d['bound'] != d['latest'] for d in dependencies):
        status = 'stale'
    elif not review:
        status = 'unreviewed'
    elif review['value']['verdict'] != 'pass':
        status = review['value']['verdict']
    else:
        status = 'current'
    return {**document, 'status': status, 'dependencies': dependencies, 'review': review}


def append(root, kind, value):
    validate(kind, value)
    scope = check_scope(root, value.get('source'), value.get('audience'))
    identity = digest({'kind': kind, 'value': value})
    if kind == 'note' and scope and 'notes' in scope:
        with database(root) as db:
            rows = records(db)
        require((value['source'], value['object']) in latest_observations(rows), 'note needs a known source/object')
        existing = personal_notes(root, rows)
        if any(r['id'] == identity for r in existing):
            return {'id': identity, 'kind': kind, 'created': False}
        directory = safe_path(scope['notes'])
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        file = safe_path(directory / (identity + '.json'))
        with file.open('x', encoding='utf-8') as handle:
            handle.write(json.dumps(value, ensure_ascii=False, indent=2))
        return {'id': identity, 'kind': kind, 'created': True}
    with database(root, True, create=kind == 'observation') as db:
        rows = records(db)
        by_id = {r['id']: r for r in rows}
        if identity in by_id:
            return {'id': identity, 'kind': kind, 'created': False}
        if kind == 'observation':
            for r in rows:
                if r['kind'] == kind and (r['value']['source'], r['value']['object']) == (value['source'], value['object']):
                    require(timestamp(r['value']['observed_at']) != timestamp(value['observed_at']),
                            'different evidence at the same observation time; reconcile the input')
        elif kind == 'document':
            previous = [r for r in rows if r['kind'] == kind and r['value']['source'] == value['source']
                        and r['value']['key'] == value['key']]
            require(value['previous'] == (previous[-1]['id'] if previous else None),
                    'previous must name the latest document revision')
            if previous:
                require(all(previous[-1]['value'][k] == value[k] for k in ('audience', 'area', 'product_version')),
                        'use a new document key for a different audience, area or product version')
            for ref in value['evidence']:
                require(ref in by_id and by_id[ref]['kind'] == 'observation'
                        and by_id[ref]['value']['source'] == value['source'], 'evidence source mismatch or missing observation')
        elif kind == 'note':
            require((value['source'], value['object']) in latest_observations(rows), 'note needs a known source/object')
        elif kind == 'review':
            doc = by_id.get(value['document'])
            require(doc is not None and doc['kind'] == 'document', 'review needs an exact document ID')
            require(doc['value']['author'] != value['reviewer'], 'independent reviewer must differ from author')
            if value['verdict'] == 'pass':
                state = document_state(doc, rows)
                require(state['status'] not in ('stale', 'evidence_pending'), 'changed or incomplete evidence cannot pass')
        db.execute('INSERT INTO records(id,kind,body) VALUES (?,?,?)',
                   (identity, kind, json.dumps(value, ensure_ascii=False, sort_keys=True)))
    return {'id': identity, 'kind': kind, 'created': True}


def read(root, source, audience=None, area=None, product_version=None, query=None):
    require(bool(source), 'explicit source is required')
    scope = check_scope(root, source, audience)
    if scope:
        audience = scope['audience']
    if audience is not None:
        require(audience in AUDIENCES, 'invalid audience')
    if area is not None:
        require(area in AREAS, 'invalid area')
    with database(root) as db:
        rows = records(db)
    rows += personal_notes(root, rows)
    if scope:
        require(all(r['value'].get('source', source) == source and
                    (r['kind'] != 'document' or r['value']['audience'] == audience) for r in rows),
                'notebook contains records outside its declared scope')
    selected = [r for r in rows if r['kind'] != 'review' and r['value']['source'] == source]
    latest_docs = {}
    for row in selected:
        if row['kind'] == 'document':
            latest_docs[row['value']['key']] = row
    documents = [document_state(r, rows) for r in latest_docs.values()
                 if (audience is None or r['value']['audience'] == audience)
                 and (area is None or r['value']['area'] == area)
                 and (product_version is None or r['value']['product_version'] == product_version)]
    if query:
        terms = query.casefold().split()
        documents = [d for d in documents if all(t in (d['value']['title'] + ' ' + d['value']['body']).casefold() for t in terms)]
    current = latest_observations(selected)
    return {'notebook_scope': scope, 'source': source, 'audience': audience, 'area': area, 'product_version': product_version,
            'documents': documents,
            'observations': list(current.values()),
            'notes': [r for r in selected if r['kind'] == 'note'],
            'history': [{'id': r['id'], 'kind': r['kind']} for r in selected],
            'scope': 'Local owner supplied evidence; current means reviewed against latest imported complete observations, not live SAP freshness.'}


def register_commands(parser):
    sub = parser.add_subparsers(dest='notebook_command', required=True)
    init = sub.add_parser('init')
    init.add_argument('--notes', type=Path, help='Canonical personal note directory, outside the notebook DB')
    init.add_argument('--source', required=True)
    init.add_argument('--audience', choices=sorted(AUDIENCES), required=True)
    refresh = sub.add_parser('refresh-sap')
    refresh.add_argument('--plan', type=Path, required=True)
    refresh.add_argument('--output', type=Path, required=True)
    wiki = sub.add_parser('wiki')
    wiki.add_argument('--source', required=True)
    wiki.add_argument('--output', type=Path, required=True)
    wiki.add_argument('--publish', type=Path, help='Stable wiki root containing this new output directory')
    wiki.add_argument('--node', required=True)
    wiki.add_argument('--markdown-it', type=Path, required=True)
    get = sub.add_parser('get')
    get.add_argument('--id', required=True)
    get.add_argument('--source', required=True)
    for kind in ('observe', 'document', 'note', 'review'):
        sub.add_parser(kind).add_argument('--input', type=Path, required=True)
    sap = sub.add_parser('import-sap')
    sap.add_argument('--input', type=Path, required=True)
    sap.add_argument('--producer-version', required=True)
    legacy = sub.add_parser('import-note')
    legacy.add_argument('--file', type=Path, required=True)
    for k in ('source', 'object', 'author'):
        legacy.add_argument('--' + k, required=True)
    for name in ('read', 'export'):
        command = sub.add_parser(name)
        command.add_argument('--source', required=True)
        command.add_argument('--audience', choices=sorted(AUDIENCES))
        command.add_argument('--area', choices=sorted(AREAS))
        command.add_argument('--product-version')
        command.add_argument('--query')
        if name == 'export':
            command.add_argument('--output', type=Path, required=True)


def execute(args):
    command = args.notebook_command
    if command == 'init':
        return initialize(args.project, args.source, args.audience, args.notes)
    if command == 'refresh-sap':
        from sap_refresh import refresh
        return refresh(args.project, args.plan, args.output)
    if command == 'wiki':
        from sap_refresh import wiki
        return wiki(args.project, args.source, args.output, args.node, args.markdown_it, args.publish)
    if command == 'get':
        check_scope(args.project, args.source)
        with database(args.project) as db:
            rows = records(db)
        rows += personal_notes(args.project, rows)
        match = next((r for r in rows if r['id'] == args.id and r['kind'] != 'review'
                      and r['value']['source'] == args.source), None)
        require(match is not None, 'record not found in selected source')
        return match
    if command in ('observe', 'document', 'note', 'review', 'import-sap'):
        value = json.loads(args.input.read_text(encoding='utf-8'))
        if command == 'import-sap':
            from sap_observations import adapt_sap_graph
            value = adapt_sap_graph(value, producer_version=args.producer_version)
        return append(args.project, 'observation' if command in ('observe', 'import-sap') else command, value)
    if command == 'import-note':
        data = args.file.read_bytes()
        import hashlib
        value = {'source': args.source, 'object': args.object, 'author': args.author,
                 'body': data.decode('utf-8'), 'origin': 'legacy-markdown:sha256:' + hashlib.sha256(data).hexdigest()}
        return append(args.project, 'note', value)
    view = read(args.project, args.source, args.audience, args.area, args.product_version, args.query)
    if command == 'export':
        from observation_wiki import export
        return export(view, args.output)
    return view
