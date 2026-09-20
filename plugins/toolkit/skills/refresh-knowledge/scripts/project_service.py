"""Project commands and their durable state transitions."""
from pathlib import Path

from project_store import (database, immutable, project_row, read, run_row,
                           save_run, verify_context, project_summary, run_summaries, initialize_project,
                           has_run, insert_active_run, complete_run, clear_active,
                           review_artifact, verify_review)


def verify_attempt(run, repo):
    from workflow import verify_packet
    packet = run['attempt']
    if run.get('intake') is not None and (not packet or packet.get('version') != 2
                                          or packet.get('intake') != run['intake']):
        raise ValueError('INTAKE_REVIEW_REQUIRED: prepare and independently review a new intake-bound packet; '
                         'if already applying, retire to a reviewed successor')
    if packet:
        verify_packet(packet, repo)


NEXT_ACTION = {
    'awaiting_decisions': 'prepare', 'awaiting_review': 'review',
    'revise': 'prepare', 'blocked': 'resolve_review', 'ready': 'resume',
    'applying': 'resume', 'completed': 'start', 'terminated': 'review_new_baseline',
}
PREPARE_PHASES = ('awaiting_decisions', 'awaiting_review', 'revise', 'blocked', 'ready')
REVIEW_PHASES = ('awaiting_review', 'revise', 'blocked', 'ready')
APPLY_PHASES = ('ready', 'applying')


def summary(project, run):
    result = {'run': run['id'], 'phase': run['phase'],
              'before': run['before']['commit'], 'after': run['after']['commit'],
              'context': str(project / 'runs' / run['id'] / 'context.json'),
              'next_action': NEXT_ACTION[run['phase']]}
    if run.get('attempt'):
        result['packet'] = str(project / 'runs' / run['id'] / run['attempt']['id'] / 'packet.json')
    if run.get('review') and run.get('attempt'):
        result['review'] = review_artifact(project, run)
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
    initialize_project(project, config, {'snapshot': snapshot, 'bindings': bindings})
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
            verify_context(project, run)
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
        if has_run(db, run_id):
            raise ValueError('RUN_TERMINATED: this change was ended; use a new reviewed project for the same change')
        context = {'before': current['snapshot'], 'after': after, 'bindings': current['bindings'],
                   'impact': queue, 'intake': intake_record, 'audience': config['audience'], 'purpose': config['purpose'],
                   'documents': [{'path': d['path'], 'text': document_bytes(Path(config['docs']), d['path']).decode('utf-8')}
                                 for d in current['bindings']['documents']]}
        immutable(project / 'runs' / run_id / 'context.json', context)
        run = {'id': run_id, 'phase': 'awaiting_decisions', **context,
               'attempt': None, 'review': None, 'completion': None}
        insert_active_run(db, run)
        return summary(project, run)


def prepare(args, project):
    from update import prepare as prepare_plan
    from workflow import pack
    with database(project, True) as db:
        config, _, active = project_row(db)
        run = run_row(db, args.run)
        verify_context(project, run)
        if active != args.run or run['phase'] not in PREPARE_PHASES:
            raise ValueError('RUN_PHASE: cannot prepare in ' + run['phase'])
        decisions = read(args.decisions)
        plan = prepare_plan(decisions, run['bindings'], run['before'], run['after'], Path(config['docs']), Path(config['repo']))
        packet = pack(plan, run['bindings'], run['before'], run['after'], Path(config['repo']), config['audience'], config['purpose'], intake=run.get('intake'))
        immutable(project / 'runs' / args.run / packet['id'] / 'packet.json', packet)
        run.update(phase='awaiting_review', attempt=packet, review=None)
        save_run(db, run, 'phase', 'attempt', 'review')
        return summary(project, run)


def review(args, project):
    from workflow import shape
    with database(project, True) as db:
        config, _, active = project_row(db)
        run = run_row(db, args.run)
        verify_context(project, run)
        verify_attempt(run, Path(config['repo']))
        if active != args.run or run['phase'] not in REVIEW_PHASES:
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
        save_run(db, run, 'phase', 'review')
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
        verify_context(project, run)
        if run['phase'] == 'completed':
            return completed_summary(project, run, config, current)
        if active != args.run:
            raise ValueError('RUN_NOT_ACTIVE: ' + args.run)
        if run['phase'] not in APPLY_PHASES:
            return summary(project, run)
        verify_attempt(run, Path(config['repo']))
        immutable(project / 'runs' / args.run / run['attempt']['id'] / 'packet.json', run['attempt'])
        run['phase'] = 'applying'
        save_run(db, run, 'phase')
    with database(project, True) as db:
        config, current, active = project_row(db)
        run = run_row(db, args.run)
        verify_context(project, run)
        if run['phase'] == 'completed':
            return completed_summary(project, run, config, current)
        if active != args.run or current['snapshot']['id'] != run['before']['id']:
            raise ValueError('BASELINE_CHANGED: refusing out-of-order apply')
        verify_attempt(run, Path(config['repo']))
        receipt = finish(run['attempt'], run['review'], Path(config['repo']), Path(config['docs']),
                         project / 'runs' / args.run / 'complete.json')
        run.update(phase='completed', completion=receipt)
        save_run(db, run, 'phase', 'completion')
        complete_run(db, run['after'], receipt['next_bindings'])
        return summary(project, run)


def status(args, project):
    with database(project) as db:
        config, baseline, active = project_summary(db)
        location = {'project': str(project), 'settings': config}
        if args.run:
            run = run_row(db, args.run)
            verify_context(project, run)
            verify_review(project, run)
            result = {**location, **summary(project, run), 'context_integrity': 'verified'}
            if run.get('review'):
                result['review_integrity'] = 'verified'
            return result
        runs = []
        for run in run_summaries(db):
            result = summary(project, run)
            result['context_integrity'] = 'unchecked'
            if run.get('review'):
                result['review_integrity'] = 'unchecked'
            if args.deep:
                try:
                    verify_context(project, run_row(db, run['id']))
                    result['context_integrity'] = 'verified'
                except (ValueError, OSError) as error:
                    result['context_integrity'] = 'invalid'
                    result['context_error'] = str(error)
                if run.get('review'):
                    try:
                        verify_review(project, run)
                        result['review_integrity'] = 'verified'
                    except (ValueError, OSError) as error:
                        result['review_integrity'] = 'invalid'
                        result['review_error'] = str(error)
            runs.append(result)
        return {**location, 'baseline': baseline, 'active': active,
                'retirement': read(project / 'retired.json') if (project / 'retired.json').exists() else None,
                'runs': runs}


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
        save_run(db, run, 'phase', 'termination_reason')
        clear_active(db)
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


# Keep command lifetime explicit, including repeated calls in one interpreter.
def _command(function):
    from functools import wraps

    @wraps(function)
    def execute(*args, **kwargs):
        from source_verification import command_sources
        with command_sources():
            return function(*args, **kwargs)
    return execute


initialize = _command(initialize)
start = _command(start)
prepare = _command(prepare)
review = _command(review)
resume = _command(resume)
status = _command(status)
terminate = _command(terminate)
retire = _command(retire)
