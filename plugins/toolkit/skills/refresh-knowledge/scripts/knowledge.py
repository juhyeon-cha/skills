#!/usr/bin/env python3
"""Project-scoped knowledge updates: one durable run ID across agent handoffs."""
import argparse
from contextlib import contextmanager
import importlib.metadata
import json
import os
from pathlib import Path
import shutil
import sqlite3
import sys
import tempfile

sys.dont_write_bytecode = True


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


def save_run(db, run):
    db.execute('UPDATE runs SET data=? WHERE id=?', (dump(run), run['id']))


def summary(project, run):
    result = {'run': run['id'], 'phase': run['phase'],
              'before': run['before']['commit'], 'after': run['after']['commit'],
              'context': str(project / 'runs' / run['id'] / 'context.json')}
    if run.get('attempt'):
        result['packet'] = str(project / 'runs' / run['id'] / run['attempt']['id'] / 'packet.json')
    if run.get('completion'):
        result['completion'] = str(project / 'runs' / run['id'] / 'complete.json')
    return result


def initialize(args, project):
    from cli import capture
    from impact import bind
    repo, docs = args.repo.resolve(strict=True), args.docs.resolve(strict=True)
    snapshot = capture(repo, args.repository, args.baseline, args.path)
    bindings = bind(read(args.spec), snapshot, docs)
    if not args.audience.strip() or not args.purpose.strip():
        raise ValueError('CONTEXT: audience and purpose are required')
    config = {'repo': str(repo), 'docs': str(docs), 'repository': args.repository,
              'scope': snapshot['scope'], 'audience': args.audience, 'purpose': args.purpose}
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
                       (dump(config), dump({'snapshot': snapshot, 'bindings': bindings})))
            db.commit()
        finally:
            db.close()
        os.link(name, project / 'project.sqlite3')
    finally:
        os.unlink(name)
    return {'project': str(project), 'phase': 'initialized', 'baseline': snapshot['commit']}


def start(args, project):
    from cli import capture, identify
    from impact import document_bytes, impact
    with database(project, True) as db:
        config, current, active = project_row(db)
        after = capture(Path(config['repo']), config['repository'], args.rev, config['scope'])
        intake_record = None
        if args.intake:
            from intake import load
            intake_record = load(project, args.intake)
            if intake_record['route'] != 'current_documentation' or intake_record['phase'] != 'awaiting_document_update':
                raise ValueError('INTAKE_ROUTE: only current documentation enters code-to-document execution')
            inp = intake_record['input']
            source = next(s for s in inp['sources'] if s['id'] == inp['current']['code'])
            if source['version'] != after['commit']:
                raise ValueError('INTAKE_VERSION: current evidence must name the requested pinned commit')
        if active:
            run = run_row(db, active)
            if run.get('intake') != intake_record:
                raise ValueError('INTAKE_CHANGED: resume the original intake or terminate the run')
            if run['after']['id'] != after['id']:
                raise ValueError('RUN_ACTIVE: finish or resolve ' + active + ' before another change')
            return summary(project, run)
        if current['bindings'] is None:
            raise ValueError('NO_TRACKED_CLAIMS: initialize a new project with a reviewed baseline')
        queue = impact(current['bindings'], current['snapshot'], after, Path(config['docs']), Path(config['repo']))
        if after['id'] == current['snapshot']['id']:
            return {'phase': 'unchanged', 'baseline': after['commit']}
        run_id = identify({'before': current['snapshot']['id'], 'after': after['id'],
                           'bindings': current['bindings']['id'], 'intake': args.intake})
        if db.execute('SELECT 1 FROM runs WHERE id=?', (run_id,)).fetchone():
            raise ValueError('RUN_TERMINATED: this change was ended; use a new reviewed project for the same change')
        context = {'before': current['snapshot'], 'after': after, 'bindings': current['bindings'],
                   'impact': queue, 'intake': intake_record, 'audience': config['audience'], 'purpose': config['purpose'],
                   'documents': [{'path': d['path'], 'text': document_bytes(Path(config['docs']), d['path']).decode('utf-8')}
                                 for d in current['bindings']['documents']]}
        immutable(project / 'runs' / run_id / 'context.json', context)
        run = {'id': run_id, 'phase': 'awaiting_decisions', **context,
               'attempt': None, 'review': None, 'completion': None}
        db.execute('INSERT INTO runs VALUES(?,?)', (run_id, dump(run)))
        db.execute('UPDATE project SET active=? WHERE id=1', (run_id,))
        return summary(project, run)


def prepare(args, project):
    from update import prepare as prepare_plan
    from workflow import pack
    with database(project, True) as db:
        config, _, active = project_row(db)
        run = run_row(db, args.run)
        if active != args.run or run['phase'] not in ('awaiting_decisions', 'awaiting_review', 'revise', 'blocked', 'ready'):
            raise ValueError('RUN_PHASE: cannot prepare in ' + run['phase'])
        decisions = read(args.decisions)
        plan = prepare_plan(decisions, run['bindings'], run['before'], run['after'], Path(config['docs']), Path(config['repo']))
        packet = pack(plan, run['bindings'], run['before'], run['after'], Path(config['repo']), config['audience'], config['purpose'])
        immutable(project / 'runs' / args.run / packet['id'] / 'packet.json', packet)
        run.update(phase='awaiting_review', attempt=packet, review=None)
        save_run(db, run)
        return summary(project, run)


def review(args, project):
    from workflow import shape
    with database(project, True) as db:
        _, _, active = project_row(db)
        run = run_row(db, args.run)
        if active != args.run or run['phase'] not in ('awaiting_review', 'revise', 'blocked', 'ready'):
            raise ValueError('RUN_PHASE: cannot review in ' + run['phase'])
        result = read(args.review)
        shape(result, 'review')
        packet = run['attempt']
        if packet:
            immutable(project / 'runs' / args.run / packet['id'] / 'packet.json', packet)
        if not packet or result['packet'] != packet['id'] or result['plan'] != packet['plan']['id']:
            raise ValueError('REVIEW_STALE: review does not match latest attempt')
        if result['verdict'] == 'pass' and (result['findings'] or any(v != 'pass' for v in result['checks'].values())):
            raise ValueError('REVIEW_INCONSISTENT: pass needs all checks and no findings')
        from cli import identify
        immutable(project / 'runs' / args.run / packet['id'] / ('review-' + identify(result) + '.json'), result)
        run.update(phase='ready' if result['verdict'] == 'pass' else result['verdict'], review=result)
        save_run(db, run)
        return summary(project, run)


def completed_summary(project, run, config, current):
    from impact import impact, document_bytes
    result = summary(project, run)
    result['historical'] = current['snapshot']['id'] != run['after']['id']
    if not result['historical']:
        if current['bindings'] is not None:
            impact(current['bindings'], current['snapshot'], current['snapshot'], Path(config['docs']), Path(config['repo']))
        for doc in run['attempt']['plan']['documents']:
            if document_bytes(Path(config['docs']), doc['path']) != doc['after_text'].encode('utf-8'):
                raise ValueError('COMPLETED_DOCUMENT_CHANGED: ' + doc['path'])
        immutable(project / 'runs' / run['id'] / 'complete.json', run['completion'])
    return result


def resume(args, project):
    from workflow import finish
    # Commit intent before document writes. A killed process leaves 'applying',
    # including the exact reviewed packet, available to another process.
    with database(project, True) as db:
        config, current, active = project_row(db)
        run = run_row(db, args.run)
        if run['phase'] == 'completed':
            return completed_summary(project, run, config, current)
        if active != args.run:
            raise ValueError('RUN_NOT_ACTIVE: ' + args.run)
        if run['phase'] not in ('ready', 'applying'):
            return summary(project, run)
        immutable(project / 'runs' / args.run / run['attempt']['id'] / 'packet.json', run['attempt'])
        run['phase'] = 'applying'
        save_run(db, run)
    with database(project, True) as db:
        config, current, active = project_row(db)
        run = run_row(db, args.run)
        if run['phase'] == 'completed':
            return completed_summary(project, run, config, current)
        if active != args.run or current['snapshot']['id'] != run['before']['id']:
            raise ValueError('BASELINE_CHANGED: refusing out-of-order apply')
        receipt = finish(run['attempt'], run['review'], Path(config['repo']), Path(config['docs']),
                         project / 'runs' / args.run / 'complete.json')
        run.update(phase='completed', completion=receipt)
        save_run(db, run)
        db.execute('UPDATE project SET current=?, active=NULL WHERE id=1',
                   (dump({'snapshot': run['after'], 'bindings': receipt['next_bindings']}),))
        return summary(project, run)


def status(args, project):
    with database(project) as db:
        config, current, active = project_row(db)
        location = {'project': str(project), 'settings': config}
        if args.run:
            return {**location, **summary(project, run_row(db, args.run))}
        return {**location, 'baseline': current['snapshot']['commit'], 'active': active,
                'retirement': read(project / 'retired.json') if (project / 'retired.json').exists() else None,
                'runs': [summary(project, json.loads(row[0])) for row in db.execute('SELECT data FROM runs ORDER BY rowid')]}


def reason(path):
    value = path.read_text(encoding='utf-8').strip()
    if not value:
        raise ValueError('REASON: a nonblank explanation is required')
    return value


def terminate(args, project):
    explanation = reason(args.reason_file)
    with database(project, True) as db:
        _, _, active = project_row(db)
        run = run_row(db, args.run)
        if active != args.run or run['phase'] in ('applying', 'completed'):
            raise ValueError('RUN_PHASE: partial application requires project retirement and a reviewed successor baseline')
        run.update(phase='terminated', termination_reason=explanation)
        save_run(db, run)
        db.execute('UPDATE project SET active=NULL WHERE id=1')
        return summary(project, run)


def retire(args, project):
    successor = args.successor.resolve()
    if successor == project or successor.is_relative_to(project) or project.is_relative_to(successor):
        raise ValueError('SUCCESSOR: use a separate project directory outside the old project')
    record = {'reason': reason(args.reason_file), 'successor': str(successor),
              'effect': 'No rollback or baseline advancement. Inspect documents and initialize a reviewed successor.'}
    marker = project / 'retired.json'
    if marker.exists():
        immutable(marker, record)
    else:
        with database(project, True):
            immutable(marker, record)
    return {'project': str(project), 'phase': 'retired', **record}


def doctor():
    import subprocess
    if sys.version_info < (3, 10):
        raise ValueError('DEPENDENCY: Python 3.10+ required')
    version = importlib.metadata.version('jsonschema')
    if version != '4.26.0':
        raise ValueError('DEPENDENCY: install adjacent requirements.txt; jsonschema==4.26.0 required')
    executable = shutil.which('git')
    if not executable:
        raise ValueError('DEPENDENCY: Git is missing')
    git_version = subprocess.check_output([executable, '--version'], text=True).strip()
    skills = Path(__file__).resolve().parents[2]
    required = ['writing-for-humans/SKILL.md', 'writing-for-humans/references/backend.md',
                'writing-for-humans/references/document-shapes.md', 'review-knowledge/SKILL.md',
                'review-knowledge/references/rubric.md', 'review-knowledge/references/response.md',
                'review-knowledge/references/document-ac.md']
    missing = [p for p in required if not (skills / p).is_file()]
    if missing:
        raise ValueError('DEPENDENCY_UNREACHED: missing installed skill files: ' + ', '.join(missing))
    return {'python': sys.executable, 'python_version': sys.version.split()[0],
            'jsonschema': version, 'git': executable, 'git_version': git_version,
            'sqlite': sqlite3.sqlite_version, 'skill_files': required,
            'independent_agent': 'host capability must be checked by the orchestrator'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('doctor')
    init = commands.add_parser('init')
    for key in ('repo', 'docs', 'spec'):
        init.add_argument('--' + key, type=Path, required=True)
    for key in ('repository', 'baseline', 'audience', 'purpose'):
        init.add_argument('--' + key, required=True)
    init.add_argument('--path', action='append', required=True)
    start_command = commands.add_parser('start')
    start_command.add_argument('--rev', required=True)
    start_command.add_argument('--intake')
    commands.add_parser('intake').add_argument('--input', type=Path, required=True)
    commands.add_parser('intake-status').add_argument('--intake', required=True)
    commands.add_parser('status').add_argument('--run')
    end = commands.add_parser('terminate')
    end.add_argument('--run', required=True)
    end.add_argument('--reason-file', type=Path, required=True)
    retirement = commands.add_parser('retire')
    retirement.add_argument('--reason-file', type=Path, required=True)
    retirement.add_argument('--successor', type=Path, required=True)
    for name, field in [('prepare', 'decisions'), ('review', 'review'), ('resume', None)]:
        command = commands.add_parser(name)
        command.add_argument('--run', required=True)
        if field:
            command.add_argument('--' + field, type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'doctor':
            result = doctor()
        else:
            if args.project is None:
                raise ValueError('PROJECT_REQUIRED: supply --project')
            project = args.project.resolve()
            if args.command in ('init', 'start', 'prepare', 'review', 'resume'):
                doctor()
            if args.command == 'init' and (project / 'retired.json').exists():
                raise ValueError('PROJECT_RETIRED: initialize a separate successor')
            if args.command in ('intake', 'intake-status'):
                from intake import register, inspect
                result = (register if args.command == 'intake' else inspect)(args, project)
                print(dump(result))
                return 0
            result = {'init': initialize, 'start': start, 'prepare': prepare,
                      'review': review, 'resume': resume, 'status': status,
                      'terminate': terminate, 'retire': retire}[args.command](args, project)
        print(dump(result))
        return 0
    except Exception as error:
        print(dump({'error': str(error), 'command': args.command}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
