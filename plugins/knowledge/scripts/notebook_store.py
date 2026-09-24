"""SQLite locations and ownership. Configured stores own only knowledge_* objects."""
from contextlib import contextmanager
import json
from pathlib import Path
import uuid

APPLICATION = 0x4B4E4231
OWNER = 'knowledge.notebook'
SCHEMA = (
    "CREATE TABLE knowledge_schema (singleton INTEGER PRIMARY KEY CHECK(singleton=1), owner TEXT NOT NULL, version INTEGER NOT NULL, identity TEXT NOT NULL)",
    "CREATE TABLE knowledge_notebooks (id TEXT PRIMARY KEY, source TEXT NOT NULL, audience TEXT NOT NULL CHECK(audience IN ('user','developer')), notes_mode TEXT NOT NULL CHECK(notes_mode IN ('database','files')))",
    "CREATE TABLE knowledge_records (seq INTEGER PRIMARY KEY, notebook TEXT NOT NULL REFERENCES knowledge_notebooks(id), id TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('observation','document','note','review')), object TEXT, revision TEXT, body TEXT NOT NULL, UNIQUE(notebook,id))",
    "CREATE INDEX knowledge_records_object ON knowledge_records(notebook,kind,object,revision)",
    "CREATE TABLE knowledge_dependencies (notebook TEXT NOT NULL, document TEXT NOT NULL, evidence TEXT NOT NULL, PRIMARY KEY(notebook,document,evidence), FOREIGN KEY(notebook,document) REFERENCES knowledge_records(notebook,id), FOREIGN KEY(notebook,evidence) REFERENCES knowledge_records(notebook,id))",
    "CREATE INDEX knowledge_dependencies_evidence ON knowledge_dependencies(notebook,evidence)",
)


def require(value, message):
    if not value:
        raise ValueError('INPUT: ' + message)


def safe_path(path):
    require('..' not in Path(path).parts, 'parent traversal is unsupported in notebook paths')
    path = Path(path).absolute()
    require(not any(p.is_symlink() for p in (path, *path.parents)), 'symlink notebook paths are unsupported')
    return path


def configuration(root):
    root = safe_path(root)
    if root.is_dir() or (not root.exists() and root.suffix != '.json'):
        return None
    value = json.loads(root.read_text(encoding='utf-8'))
    require(isinstance(value, dict) and {'version', 'database', 'notebook', 'artifacts'} <= value.keys()
            and value.keys() <= {'version', 'database', 'notebook', 'artifacts', 'notes', 'publication'},
            'invalid notebook storage configuration')
    require(type(value['version']) is int and value['version'] == 1, 'unsupported storage configuration version')
    require(isinstance(value['notebook'], str) and bool(value['notebook'].strip()), 'notebook must be nonempty text')
    for name in ('database', 'artifacts', 'notes', 'publication'):
        if name in value:
            require(isinstance(value[name], str) and Path(value[name]).is_absolute(), name + ' must be an absolute path')
            safe_path(value[name])
    paths = {k: Path(value[k]) for k in ('database', 'artifacts', 'notes', 'publication') if k in value}
    require(paths['database'] != root, 'configuration cannot be the database')
    for name, path in paths.items():
        if name != 'database':
            require(not path.exists() or path.is_dir(), name + ' must be a directory')
            require(path != paths['database'] and paths['database'] not in path.parents,
                    'database cannot be an artifact directory')
    if 'publication' in paths:
        publication = paths['publication']
        for private in (root, paths['database'], paths['artifacts'], *([paths['notes']] if 'notes' in paths else [])):
            require(publication != private and publication not in private.parents and private not in publication.parents,
                    'publication must be separate from private storage')
    if 'notes' in paths:
        require(paths['notes'] != paths['artifacts'] and paths['notes'] not in paths['artifacts'].parents
                and paths['artifacts'] not in paths['notes'].parents, 'notes and artifacts must be separate')
    return value


def objects(db):
    return db.execute("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE name GLOB 'knowledge_*' ORDER BY name").fetchall()


def verify_schema(db):
    import sqlite3
    expected = sqlite3.connect(':memory:')
    try:
        for sql in SCHEMA:
            expected.execute(sql)
        require(objects(db) == objects(expected), 'incompatible knowledge schema; preserve database')
    finally:
        expected.close()
    rows = db.execute('SELECT owner,version,identity FROM knowledge_schema WHERE singleton=1').fetchall()
    require(len(rows) == 1 and rows[0][:2] == (OWNER, 1) and bool(rows[0][2]),
            'unsupported knowledge schema owner or version; explicit upgrade required')
    require(not db.execute("SELECT 1 FROM sqlite_schema WHERE type='trigger' AND tbl_name GLOB 'knowledge_*'").fetchone(),
            'external trigger on knowledge table')
    return rows[0][2]


def scope_row(db, config, identity):
    row = db.execute('SELECT source,audience,notes_mode FROM knowledge_notebooks WHERE id=?', (config['notebook'],)).fetchone()
    require(row is not None, 'notebook is not initialized')
    require(row[2] == ('files' if 'notes' in config else 'database'), 'notebook note storage mode cannot change')
    scope = {'version': 1, 'source': row[0], 'audience': row[1], 'store': identity, 'notebook': config['notebook']}
    if 'notes' in config:
        scope['notes'] = config['notes']
    return scope


def connect(file, write=False):
    import sqlite3
    file = safe_path(file)
    db = sqlite3.connect(file.as_uri() + ('?mode=rw' if write else '?mode=ro'), uri=True, timeout=0)
    db.execute('PRAGMA foreign_keys=ON')
    return db


def configured_scope(config):
    db = connect(config['database'])
    try:
        db.execute('BEGIN')
        return scope_row(db, config, verify_schema(db))
    finally:
        db.close()


def initialize(config, source, audience, attach=False):
    from observations import notes_scope
    file = safe_path(config['database'])
    if not attach:
        file.parent.mkdir(parents=True, exist_ok=True)
        # Failed new initialization leaves an inspectable empty file, never replaces one.
        with file.open('xb'):
            pass
    db = connect(file, True)
    try:
        db.execute('BEGIN IMMEDIATE')
        if not objects(db):
            for sql in SCHEMA:
                db.execute(sql)
            db.execute('INSERT INTO knowledge_schema VALUES(1,?,?,?)', (OWNER, 1, str(uuid.uuid4())))
        identity = verify_schema(db)
        existing = db.execute('SELECT source,audience,notes_mode FROM knowledge_notebooks WHERE id=?', (config['notebook'],)).fetchone()
        require(existing is None or existing == (source, audience, 'files' if 'notes' in config else 'database'), 'notebook scope cannot change')
        if existing is None:
            db.execute('INSERT INTO knowledge_notebooks VALUES(?,?,?,?)',
                       (config['notebook'], source, audience, 'files' if 'notes' in config else 'database'))
        scope = scope_row(db, config, identity)
        if 'notes' in scope:
            notes_scope(scope, inspect_only=True)
        db.commit()
        # Publish filesystem ownership only after the DB identity is durable. An
        # interrupted publication can retry attach using that same identity.
        if 'notes' in scope:
            notes_scope(scope, create=True)
        return {**scope, 'created': existing is None, 'database': str(file), 'artifacts': config['artifacts']}
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()


class Records:
    def __init__(self, db, notebook=None):
        self.db, self.notebook = db, notebook

    def all(self):
        if self.notebook is None:
            return self.db.execute('SELECT seq,id,kind,body FROM records ORDER BY seq')
        return self.db.execute('SELECT seq,id,kind,body FROM knowledge_records WHERE notebook=? ORDER BY seq', (self.notebook,))

    def insert(self, identity, kind, value):
        body = json.dumps(value, ensure_ascii=False, sort_keys=True)
        if self.notebook is None:
            self.db.execute('INSERT INTO records(id,kind,body) VALUES(?,?,?)', (identity, kind, body))
        else:
            self.db.execute('INSERT INTO knowledge_records(notebook,id,kind,object,revision,body) VALUES(?,?,?,?,?,?)',
                            (self.notebook, identity, kind, value.get('object', value.get('key')), value.get('revision'), body))
            if kind == 'document':
                self.db.executemany('INSERT INTO knowledge_dependencies VALUES(?,?,?)',
                                    [(self.notebook, identity, ref) for ref in value['evidence']])


@contextmanager
def database(root, write=False, create=False):
    from observations import notebook_scope, records
    config = configuration(root)
    file = Path(config['database']) if config else safe_path(root) / 'observations.sqlite'
    fresh = not file.exists()
    if fresh and config is None:
        require(write and create, 'notebook does not exist; import an observation first')
        file.parent.mkdir(parents=True, exist_ok=True)
        with file.open('xb'):
            pass
    db = connect(file, write)
    try:
        db.execute('BEGIN IMMEDIATE' if write else 'BEGIN')
        if config:
            scope = scope_row(db, config, verify_schema(db))
        else:
            if fresh:
                db.execute('CREATE TABLE records (seq INTEGER PRIMARY KEY, id TEXT UNIQUE NOT NULL, kind TEXT NOT NULL, body TEXT NOT NULL)')
                db.execute(f'PRAGMA application_id={APPLICATION}')
                db.execute('PRAGMA user_version=1')
            require(db.execute('PRAGMA application_id').fetchone()[0] == APPLICATION and
                    db.execute('PRAGMA user_version').fetchone()[0] == 1,
                    'unsupported notebook database; preserve it and use a new directory')
            scope = notebook_scope(root)
        store = Records(db, config['notebook'] if config else None)
        store.scope = scope
        if scope:
            require(all(r['value'].get('source', scope['source']) == scope['source'] and
                        (r['kind'] != 'document' or r['value']['audience'] == scope['audience'])
                        for r in records(store)), 'notebook contains records outside its declared scope')
        yield store
        if write:
            db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()


def has_store(root):
    config = configuration(root)
    if config:
        configured_scope(config)
        return True
    return safe_path(safe_path(root) / 'observations.sqlite').exists()


def location(root, name, explicit=None):
    config = configuration(root)
    if explicit is not None:
        path = safe_path(explicit)
        if config and name == 'publication':
            if name in config:
                require(path == Path(config[name]), 'publication differs from configured location')
            for private in (safe_path(root), *(Path(config[k]) for k in ('database', 'artifacts', 'notes') if k in config)):
                require(path != private and path not in private.parents and private not in path.parents,
                        'publication must be separate from private storage')
        return path
    require(config is not None and name in config, name + ' path is required')
    return safe_path(config[name])
