"""Version-one project persistence and immutable run evidence."""
from contextlib import contextmanager
import json
import os
import sqlite3
import tempfile


def read(path):
    from cli import read_json
    return read_json(path)


def dump(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def immutable(path, value):
    from cli import write_new
    if path.is_symlink():
        raise ValueError('ARTIFACT_SYMLINK: ' + str(path))
    if path.exists():
        if read(path) != value:
            raise ValueError('ARTIFACT_CONFLICT: ' + str(path))
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        write_new(path, value)
    return str(path)


@contextmanager
def database(project, write=False):
    path = project / 'project.sqlite3'
    if path.is_symlink():
        raise ValueError('PROJECT_SYMLINK: database must be local')
    db = sqlite3.connect(path.as_uri() + '?mode=rw', uri=True, timeout=0)
    try:
        if db.execute('PRAGMA user_version').fetchone()[0] != 1:
            raise ValueError('PROJECT_VERSION: unsupported; no automatic migration')
        db.execute('BEGIN IMMEDIATE' if write else 'BEGIN')
        if write and (project / 'retired.json').exists():
            raise ValueError('PROJECT_RETIRED: preserve this project; initialize the recorded successor with a reviewed baseline')
        yield db
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()


def project_row(db):
    config, current, active = db.execute('SELECT config, current, active FROM project WHERE id=1').fetchone()
    return json.loads(config), json.loads(current), active


def run_row(db, run_id):
    row = db.execute('SELECT data FROM runs WHERE id=?', (run_id,)).fetchone()
    if not row:
        raise ValueError('RUN_NOT_FOUND: ' + str(run_id))
    return json.loads(row[0])


def save_run(db, run, *fields):
    # Keep the v1 JSON record; serialize only fields changed by this transition.
    assignments = ', '.join("?, json(?)" for _ in fields)
    values = [value for field in fields for value in ('$.' + field, dump(run[field]))]
    db.execute('UPDATE runs SET data=json_set(data, ' + assignments + ') WHERE id=?',
               (*values, run['id']))


def project_summary(db):
    config, baseline, active = db.execute(
        "SELECT config, json_extract(current, '$.snapshot.commit'), active FROM project WHERE id=1"
    ).fetchone()
    return json.loads(config), baseline, active


def run_summaries(db):
    # SQLite projects scalars; Python never deserializes historical source,
    # document or packet bodies just to list state. No schema migration.
    rows = db.execute("""SELECT id, json_extract(data, '$.phase'),
        json_extract(data, '$.before.commit'), json_extract(data, '$.after.commit'),
        json_extract(data, '$.attempt.id'), json_extract(data, '$.review'),
        json_extract(data, '$.completion.id') FROM runs ORDER BY rowid""")
    for identity, phase, before, after, attempt, review, completion in rows:
        yield {'id': identity, 'phase': phase, 'before': {'commit': before},
               'after': {'commit': after}, 'attempt': {'id': attempt} if attempt else None,
               'review': json.loads(review) if review else None,
               'completion': {'id': completion} if completion else None}


CONTEXT_FIELDS = ('before', 'after', 'bindings', 'impact', 'intake', 'audience', 'purpose', 'documents')


def verify_context(project, run):
    path = project / 'runs' / run['id'] / 'context.json'
    try:
        if path.is_symlink():
            raise ValueError('symlink')
        expected = {key: run[key] for key in CONTEXT_FIELDS if key in run}
        if read(path) != expected:
            raise ValueError('content differs from stored run')
    except (ValueError, OSError) as error:
        raise ValueError('CONTEXT_INVALID: ' + str(path) + ': ' + str(error) +
                         '; preserve the artifact and restore a trusted original, or terminate before apply; '
                         'for partial application retire to a reviewed successor') from error


def initialize_project(project, config, current):
    project.mkdir(parents=True, exist_ok=True)
    # Publish a fully initialized database exclusively; never upgrade or replace one.
    fd, name = tempfile.mkstemp(prefix='.project-init-', dir=project)
    os.close(fd)
    try:
        db = sqlite3.connect(name)
        try:
            db.executescript('''CREATE TABLE project (id INTEGER PRIMARY KEY CHECK(id=1), config TEXT NOT NULL, current TEXT NOT NULL, active TEXT);
CREATE TABLE runs (id TEXT PRIMARY KEY, data TEXT NOT NULL);
PRAGMA user_version=1;''')
            db.execute('INSERT INTO project VALUES(1,?,?,NULL)',
                       (dump(config), dump(current)))
            db.commit()
        finally:
            db.close()
        os.link(name, project / 'project.sqlite3')
    finally:
        os.unlink(name)


def has_run(db, identity):
    return db.execute('SELECT 1 FROM runs WHERE id=?', (identity,)).fetchone() is not None


def insert_active_run(db, run):
    db.execute('INSERT INTO runs VALUES(?,?)', (run['id'], dump(run)))
    db.execute('UPDATE project SET active=? WHERE id=1', (run['id'],))


def complete_run(db, snapshot, bindings):
    db.execute('UPDATE project SET current=?, active=NULL WHERE id=1',
               (dump({'snapshot': snapshot, 'bindings': bindings}),))


def clear_active(db):
    db.execute('UPDATE project SET active=NULL WHERE id=1')


def review_artifact(project, run):
    from cli import identify
    identity = identify(run['review'])
    return {'id': identity, 'path': str(project / 'runs' / run['id'] /
            run['attempt']['id'] / ('review-' + identity + '.json'))}


def verify_review(project, run):
    from pathlib import Path
    if not run.get('review'):
        return
    path = Path(review_artifact(project, run)['path'])
    try:
        if path.is_symlink() or read(path) != run['review']:
            raise ValueError('content differs from stored review or is a symlink')
    except (ValueError, OSError) as error:
        raise ValueError('REVIEW_INVALID: ' + str(path) + ': ' + str(error) +
                         '; preserve the artifact and restore a trusted original') from error
