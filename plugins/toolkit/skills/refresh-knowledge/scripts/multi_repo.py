#!/usr/bin/env python3
"""Local cross-repository evidence relations and freshly authorized projections."""
import argparse
from contextlib import contextmanager
from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sqlite3
import sys
import uuid

sys.dont_write_bytecode = True
from automation import digest, environment, goal_order, now
from cli import capture, canonical, compare as source_compare, sha
from impact import verify_bindings, document_bytes
from intake import classify, obj, array, NONEMPTY
from jsonschema import Draft202012Validator, ValidationError
from project_store import (database, project_row, run_summaries, run_row, verify_context,
                           verify_review)

HASH = {'type': 'string', 'pattern': '^[a-f0-9]{64}$'}
REF = obj({'path': NONEMPTY, 'sha256': HASH})
IDS = array(NONEMPTY)
IDS['uniqueItems'] = True
REPOSITORIES = {'type': 'object', 'minProperties': 1, 'additionalProperties': obj({
    'path': NONEMPTY, 'url': NONEMPTY, 'scope': IDS, 'project': NONEMPTY})}
HOST = obj({'version': {'const': 1}, 'repositories': REPOSITORIES,
    'principals': {'type': 'object', 'additionalProperties': obj({
        'manage': {'type': 'boolean'}, 'goals': array(NONEMPTY, 0),
        'repositories': {'type': 'object', 'additionalProperties': array(
            {'enum': ['source', 'query', 'publish']}, 0)}})},
    'checks': {'type': 'object', 'additionalProperties': obj({
        'repositories': IDS, 'argv': array(NONEMPTY), 'cwd_repository': NONEMPTY})}})
ORIGIN = obj({'kind': {'enum': ['user', 'document', 'code']}, 'request': NONEMPTY,
              'cause': NONEMPTY, 'intake': REF})
GOAL = obj({'id': NONEMPTY, 'version': NONEMPTY,
    'status': {'enum': ['active', 'withdrawn', 'deferred']},
    'members': {'type': 'object', 'minProperties': 1, 'additionalProperties': obj({
        'target': NONEMPTY, 'criteria': IDS})}, 'integration': IDS, 'origin': ORIGIN})
SELECT = obj({'goal': NONEMPTY, 'repositories': IDS}, ['goal'])
RESPONSE = obj({'packet': HASH, 'verdict': {'enum': ['pass', 'revise', 'blocked']},
    'findings': array(NONEMPTY, 0), 'implementation': {'enum': ['pass', 'fail']},
    'documents': {'enum': ['pass', 'fail']}})
ATTEST = obj({'goal': NONEMPTY, 'packet': HASH, 'author': NONEMPTY, 'actor': NONEMPTY,
    'host_tool': NONEMPTY, 'call_id': NONEMPTY, 'started_at': NONEMPTY, 'finished_at': NONEMPTY,
    'prompt_sha256': HASH, 'raw_response': NONEMPTY, 'response': RESPONSE,
    'synthetic': {'type': 'boolean'}})
PREDICT = obj({'goal': NONEMPTY, 'origin': ORIGIN, 'affected': IDS, 'rationale': NONEMPTY})
COMPARE = obj({'goal': NONEMPTY, 'prediction': HASH, 'feedback': array(obj({
    'kind': {'enum': ['omission', 'decision']}, 'repositories': IDS,
    'intake': REF, 'description': NONEMPTY}), 0)})


def shape(value, schema):
    Draft202012Validator(schema).validate(value)


def read(path):
    path = Path(path)
    if path.is_symlink():
        raise ValueError('UNSAFE_PATH')
    return json.loads(path.read_text(encoding='utf-8'))


def reference(ref):
    shape(ref, REF)
    path = Path(ref['path'])
    if not path.is_absolute() or path.is_symlink() or sha(path.read_bytes()) != ref['sha256']:
        raise ValueError('EVIDENCE_CHANGED')
    return read(path)


def intake_reference(ref):
    value = reference(ref)
    if classify(value['input']) != value:
        raise ValueError('INTAKE_CHANGED')
    return value


def git(path, *args):
    proc = subprocess.run(['git', '--no-replace-objects', '-C', str(path), *args],
                          env=environment(), capture_output=True, text=True)
    if proc.returncode:
        raise ValueError('SOURCE_UNAVAILABLE')
    return proc.stdout.strip()


def command_files(command):
    """Bind absolute executable/script arguments outside pinned source trees too."""
    return {arg: sha(Path(arg).read_bytes()) for arg in command['argv']
            if Path(arg).is_absolute() and Path(arg).is_file()}


class Store:
    def __init__(self, root, host, principal):
        self.root = Path(root).absolute()
        self.host_path = Path(host)
        self.principal = principal

    def policy(self):
        host = read(self.host_path)
        shape(host, HOST)
        if self.principal not in host['principals']:
            raise ValueError('ACCESS_DENIED')
        self.host = host
        self.actor = host['principals'][self.principal]

    def allowed(self, repository, scope):
        rights = self.actor['repositories'].get(repository, [])
        return 'source' in rights and scope in rights  # PERMISSION_BOUNDARY

    def authorize(self, repository, scope='source'):
        self.policy()
        if not self.allowed(repository, scope):
            raise ValueError('ACCESS_DENIED')

    @contextmanager
    def locked(self, initialize=False):
        import fcntl
        self.policy()
        if self.root.is_symlink():
            raise ValueError('UNSAFE_PATH')
        if initialize:
            if not self.actor['manage']:
                raise ValueError('ACCESS_DENIED')
            self.root.mkdir(parents=True, exist_ok=True)
        lock_path = self.root / 'command.lock'
        if lock_path.is_symlink():
            raise ValueError('UNSAFE_PATH')
        with lock_path.open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise ValueError('BUSY') from error
            state_path = self.root / 'state.json'
            if initialize:
                if state_path.exists():
                    raise ValueError('ALREADY_INITIALIZED')
                self.state = {'version': 1, 'bindings': {}, 'goals': {}, 'checks': {},
                              'reviews': [], 'index': {}, 'publications': [], 'events': []}
            else:
                self.state = read(state_path)
                if self.state.get('version') != 1:
                    raise ValueError('STATE_VERSION')
            yield self
            if state_path.is_symlink():
                raise ValueError('UNSAFE_PATH')
            temporary = self.root / ('state-' + uuid.uuid4().hex + '.tmp')
            temporary.write_bytes(canonical(self.state))
            os.replace(temporary, state_path)

    def save(self, value):
        identity = digest(value)
        path = self.root / 'objects' / (identity + '.json')
        path.parent.mkdir(exist_ok=True)
        if path.exists():
            if self.object(identity) != value:
                raise ValueError('OBJECT_CHANGED')
        else:
            with path.open('xb') as stream:
                stream.write(canonical(value))
        return identity

    def object(self, identity):
        shape(identity, HASH)
        value = read(self.root / 'objects' / (identity + '.json'))
        if digest(value) != identity:
            raise ValueError('OBJECT_CHANGED')
        return value

    def event(self, kind, **details):
        event = {'kind': kind, 'time': now(), **details}
        self.state['events'].append(self.save(event))
        return event

    def source(self, repository):
        self.authorize(repository)
        config = self.host['repositories'][repository]
        path = Path(config['path'])
        if not path.is_absolute() or path.is_symlink():
            raise ValueError('SOURCE_UNAVAILABLE')
        anchor_id = self.state['bindings'].get(repository)
        if anchor_id:
            anchor = self.object(anchor_id)
            if capture(path, repository, anchor['commit'], anchor['scope']) != anchor:
                raise ValueError('REPOSITORY_IDENTITY_CHANGED')
            if config['scope'] != anchor['scope']:
                raise ValueError('SCOPE_CHANGED')
        snapshot = capture(path, repository, 'HEAD', config['scope'])
        if git(path, 'status', '--porcelain', '--untracked-files=all'):
            raise ValueError('SOURCE_DIRTY')
        if not snapshot['files']:
            raise ValueError('SOURCE_EMPTY')
        if not anchor_id:
            self.state['bindings'][repository] = self.save(snapshot)
        return snapshot

    def documents(self, repository, snapshot):
        self.authorize(repository)
        config = self.host['repositories'][repository]
        project = Path(config['project'])
        if (project / 'retired.json').exists():
            raise ValueError('PROJECT_RETIRED')
        with database(project) as db:
            settings, current, active = project_row(db)
            for summary in run_summaries(db):
                if summary['phase'] == 'completed' and summary['after']['commit'] == snapshot['commit']:
                    run = run_row(db, summary['id'])
                    verify_context(project, run)
                    verify_review(project, run)
                    if read(project / 'runs' / run['id'] / 'complete.json') != run['completion']:
                        raise ValueError('COMPLETION_CHANGED')
        if (settings['repository'] != repository or settings['scope'] != snapshot['scope']
                or current['snapshot'] != snapshot or active):
            raise ValueError('DOCUMENTS_PENDING')
        # Existing project settings retain their historical location after a clone/move.
        # The logical ID, anchor and exact capture establish the new source identity.
        docs = Path(settings['docs'])
        bindings = current['bindings']
        if not bindings:
            raise ValueError('DOCUMENTS_PENDING')
        verify_bindings(bindings, snapshot, docs)
        return {'bindings': bindings, 'documents': [
            {'path': d['path'], 'text': document_bytes(docs, d['path']).decode('utf-8'),
             'sha256': d['sha256']} for d in bindings['documents']]}

    def goal(self, name):
        self.policy()
        if name not in self.actor['goals']:
            raise ValueError('ACCESS_DENIED')
        value = self.object(self.state['goals'][name])
        shape(value, GOAL)
        intake = intake_reference(value['origin']['intake'])
        if intake['input']['origin'] != value['origin']['kind']:
            raise ValueError('ORIGIN_CHANGED')
        return value

    def init(self, value):
        for repository in self.host['repositories']:
            self.source(repository)
        self.event('initialized')
        return {'status': 'initialized'}

    def set_goal(self, value):
        shape(value, GOAL)
        if value['id'] not in self.actor['goals']:
            raise ValueError('ACCESS_DENIED')
        intake = intake_reference(value['origin']['intake'])
        if intake['input']['origin'] != value['origin']['kind']:
            raise ValueError('ORIGIN_CHANGED')
        expected_status = {'active': 'confirmed', 'deferred': 'deferred', 'withdrawn': 'withdrawn'}
        if intake['input']['target']['status'] != expected_status[value['status']]:
            raise ValueError('GOAL_INTAKE_STATUS')
        members = set(value['members'])
        for repository, member in value['members'].items():
            if repository not in self.state['bindings']:
                self.source(repository)
            for check in member['criteria']:
                if self.host['checks'][check]['repositories'] != [repository]:
                    raise ValueError('MEMBER_CHECK_SCOPE')
        for check in value['integration']:
            if set(self.host['checks'][check]['repositories']) != members:
                raise ValueError('INTEGRATION_SCOPE')
        previous = self.state['goals'].get(value['id'])
        if previous:
            old = self.object(previous)
            order = goal_order(old['version'], value['version'])
            if order < 0 or (order == 0 and old != value):
                raise ValueError('GOAL_VERSION_CONFLICT')
            if old == value:
                return {'goal': value['id'], 'goal_hash': previous, 'status': 'unchanged'}
        identity = self.save(value)
        self.state['goals'][value['id']] = identity
        self.event('goal', goal=identity, previous=previous)
        return {'goal': value['id'], 'goal_hash': identity, 'status': value['status']}

    def selected(self, value, goal):
        members = value.get('repositories', list(goal['members']))
        if not members or not set(members) <= set(goal['members']):
            raise ValueError('MEMBER_SCOPE')
        return sorted(members)

    def run_checks(self, value):
        shape(value, obj({'goal': NONEMPTY, 'checks': IDS}))
        goal = self.goal(value['goal'])
        if goal['status'] != 'active':
            raise ValueError('GOAL_INACTIVE')
        required = set(goal['integration']) | {c for m in goal['members'].values() for c in m['criteria']}
        if not set(value['checks']) <= required:
            raise ValueError('CHECK_SCOPE')
        results = []
        for name in value['checks']:
            command = self.host['checks'][name]
            repositories = command['repositories']
            if command['cwd_repository'] not in repositories:
                raise ValueError('CHECK_CWD')
            sources = {r: self.source(r) for r in repositories}
            for r in repositories:
                if git(self.host['repositories'][r]['path'], 'status', '--porcelain', '--untracked-files=all'):
                    raise ValueError('CHECK_DIRTY_SOURCE')
            cwd = self.host['repositories'][command['cwd_repository']]['path']
            started = now()
            inputs = command_files(command)
            try:
                proc = subprocess.run(command['argv'], cwd=cwd, env=environment(), capture_output=True,
                                      text=True, timeout=120)
                exit_code, stdout, stderr = proc.returncode, proc.stdout, proc.stderr
            except (subprocess.TimeoutExpired, OSError):
                exit_code, stdout, stderr = 124, '', 'CHECK_EXECUTION_UNAVAILABLE'
            try:
                after = {r: self.source(r) for r in repositories}
                clean = all(not git(self.host['repositories'][r]['path'], 'status', '--porcelain',
                                    '--untracked-files=all') for r in repositories)
            except (ValueError, OSError):
                after, clean = {}, False
            record = {'kind': 'check', 'name': name, 'goal_hash': digest(goal), 'command': command,
                      'sources': sources, 'started_at': started, 'finished_at': now(),
                      'exit_code': exit_code, 'stdout': stdout, 'stderr': stderr,
                      'input_files': inputs,
                      'source_unchanged': after == sources and clean and inputs == command_files(command)}
            identity = self.save(record)
            self.state['checks'][goal['id'] + '/' + name] = identity
            self.event('check', check=identity)
            results.append({'check': name, 'evidence': identity, 'exit_code': exit_code,
                            'source_unchanged': record['source_unchanged']})
        return {'goal': goal['id'], 'checks': results}

    def checked(self, goal, names, sources):
        results = {}
        for name in names:
            identity = self.state['checks'].get(goal['id'] + '/' + name)
            if not identity:
                raise ValueError('CHECK_PENDING')
            record = self.object(identity)
            if (record['goal_hash'] != digest(goal) or record['exit_code'] != 0 or
                    not record['source_unchanged'] or record['command'] != self.host['checks'][name] or
                    record['input_files'] != command_files(self.host['checks'][name]) or
                    any(sources.get(r) != s for r, s in record['sources'].items())):
                raise ValueError('CHECK_STALE_OR_FAILED')
            results[name] = identity
        return results

    def packet(self, goal, members):
        sources = {r: self.source(r) for r in members}
        documents = {r: self.documents(r, sources[r]) for r in members}
        names = sorted({c for r in members for c in goal['members'][r]['criteria']})
        if set(members) == set(goal['members']):
            names = sorted(set(names) | set(goal['integration']))
        checks = self.checked(goal, names, sources)
        return {'kind': 'multi-repo-review', 'goal_hash': digest(goal), 'goal': goal,
                'sources': sources, 'documents': documents, 'checks': checks,
                'check_evidence': {c: self.object(identity) for c, identity in checks.items()}}

    def review_packet(self, value):
        shape(value, SELECT)
        goal = self.goal(value['goal'])
        packet = self.packet(goal, self.selected(value, goal))
        identity = self.save(packet)
        return {'packet': identity, 'path': str(self.root / 'objects' / (identity + '.json')),
                'prompt_sha256': sha(canonical(packet))}

    def attest(self, value):
        shape(value, ATTEST)
        goal = self.goal(value['goal'])
        packet = self.object(value['packet'])
        if packet != self.packet(goal, sorted(packet['sources'])):
            raise ValueError('REVIEW_STALE')
        start, end = (datetime.fromisoformat(value[k]) for k in ('started_at', 'finished_at'))
        if not start.tzinfo or not end.tzinfo or end < start:
            raise ValueError('REVIEW_TIME')
        if any(start < datetime.fromisoformat(check['finished_at']) for check in packet['check_evidence'].values()):
            raise ValueError('REVIEW_PRECEDES_EVIDENCE')
        response = value['response']
        if (value['actor'] == value['author'] or response['packet'] != value['packet'] or
                value['prompt_sha256'] != sha(canonical(packet)) or
                json.loads(value['raw_response']) != response):
            raise ValueError('REVIEW_BINDING')
        if response['verdict'] == 'pass' and (response['findings'] or
                response['implementation'] != 'pass' or response['documents'] != 'pass'):
            raise ValueError('REVIEW_INCONSISTENT')
        identity = self.save(value)
        self.state['reviews'].append(identity)
        self.event('review', review=identity)
        return {'review': identity, 'verdict': response['verdict'], 'synthetic': value['synthetic']}

    def reviewed(self, goal, repository, snapshot, docs, checks):
        for identity in reversed(self.state['reviews']):
            review = self.object(identity)
            packet = self.object(review['packet'])
            if (packet['goal_hash'] == digest(goal) and review['response']['verdict'] == 'pass'
                    and packet['sources'].get(repository) == snapshot
                    and packet['documents'].get(repository) == docs
                    and all(packet['checks'].get(c) == i for c, i in checks.items())):
                return identity
        raise ValueError('REVIEW_PENDING')

    def member(self, goal, repository, scope):
        self.authorize(repository, scope)
        snapshot = self.source(repository)
        result = {'repository': repository, 'current': {'commit': snapshot['commit'],
                  'snapshot': snapshot['id'], 'files': snapshot['files']},
                  'target': goal['members'][repository]['target'], 'validation': 'pending',
                  'source_url': self.host['repositories'][repository]['url']}
        try:
            docs = self.documents(repository, snapshot)
            checks = self.checked(goal, goal['members'][repository]['criteria'], {repository: snapshot})
            review = self.reviewed(goal, repository, snapshot, docs, checks)
            result.update(validation='verified', evidence={'checks': checks, 'review': review,
                          'review_synthetic': self.object(review)['synthetic'],
                          'bindings': docs['bindings']['id']}, documents=docs['documents'])
        except (ValueError, OSError, KeyError, ValidationError, sqlite3.Error):
            result['validation'] = 'pending_or_stale'
        return result

    def relation_allowed(self, record, scope):
        # Authorize the entire historical record, including mixed feedback text.
        # Current goal membership can be narrower than the recorded evidence.
        if record['kind'] == 'prediction':
            repositories = set(record['before']) | set(record['before_documents']) | set(record['affected'])
        else:
            prediction = self.object(record['prediction'])
            if not self.relation_allowed(prediction, scope):
                return False
            repositories = (set(record['changes']) | set(record['documents']) |
                            set(record['omissions']) | set(record['unresolved']) |
                            {r for feedback in record['feedback'] for r in feedback['repositories']})
        self.policy()
        return all(self.allowed(r, scope) for r in repositories)

    def view(self, name, scope='query'):
        goal = self.goal(name)
        members, hidden = [], 0
        for repository in goal['members']:
            self.policy()
            if not self.allowed(repository, scope):
                hidden += 1
                continue
            try:
                members.append(self.member(goal, repository, scope))
            except (ValueError, OSError, KeyError, ValidationError, sqlite3.Error):
                members.append({'repository': repository, 'validation': 'source_unavailable'})
        integration = 'pending'
        if not hidden and all(m.get('validation') == 'verified' for m in members):
            try:
                sources = {r: self.source(r) for r in goal['members']}
                checks = self.checked(goal, goal['integration'], sources)
                for repository in goal['members']:
                    docs = self.documents(repository, sources[repository])
                    self.reviewed(goal, repository, sources[repository], docs, checks)
                integration = 'verified'
            except (ValueError, OSError, KeyError, ValidationError, sqlite3.Error):
                integration = 'pending_or_stale'
        complete = integration == 'verified' and goal['status'] == 'active'
        result = {'goal': name, 'version': goal['version'], 'goal_hash': digest(goal),
                  'status': goal['status'], 'completion': 'complete' if complete else 'incomplete',
                  'required_count': len(goal['members']), 'withheld_count': hidden,
                  'members': members, 'integration': integration}
        # Origins and predictions may contain names or excerpts from hidden members.
        if not hidden:
            result['origin'] = {'kind': goal['origin']['kind'], 'request': goal['origin']['request'],
                                'cause': goal['origin']['cause']}
            relations = []
            for event_id in self.state['events']:
                event = self.object(event_id)
                if event['kind'] not in ('prediction', 'comparison'):
                    continue
                record_id = event[event['kind']]
                record = self.object(record_id)
                if record['goal'] != name or not self.relation_allowed(record, scope):
                    continue
                relation = {'kind': event['kind'], 'record': record_id, 'time': record['time']}
                if event['kind'] == 'prediction':
                    relation.update(affected=record['affected'], origin=record['origin']['kind'])
                else:
                    relation.update(prediction=record['prediction'], omissions=record['omissions'],
                                    feedback=[{'kind': f['kind'], 'repositories': f['repositories'],
                                               'description': f['description'], 'intake_sha256': f['intake']['sha256']}
                                              for f in record['feedback']], unresolved=record['unresolved'])
                relations.append(relation)
            result['relations'] = relations
        return result

    def refresh(self, value):
        shape(value, obj({'goal': NONEMPTY}))
        view = self.view(value['goal'])
        self.state['index'][value['goal']] = self.save(view)
        self.event('refresh', goal=value['goal'], projection=self.state['index'][value['goal']])
        return view

    def query(self, value):
        shape(value, obj({'goal': NONEMPTY, 'text': {'type': 'string'}}, ['goal']))
        view = self.view(value['goal'])
        cached = self.state['index'].get(value['goal'])
        view['index'] = 'absent' if not cached else ('current' if cached == digest(view) else 'stale')
        if value.get('text'):
            needle = value['text'].casefold()
            view['matches'] = [m['repository'] for m in view['members']
                               if needle in json.dumps(m, ensure_ascii=False).casefold()]
        return view

    def publish(self, value):
        shape(value, obj({'goal': NONEMPTY, 'audience': NONEMPTY}, ['goal']))
        view = self.view(value['goal'], 'publish')
        audience = value.get('audience', self.principal)
        if audience != self.principal:
            publisher = self.principal
            permitted = {m['repository'] for m in view['members']}
            try:
                self.principal = audience
                view = self.view(value['goal'], 'publish')
                if any(m['repository'] not in permitted for m in view['members']):
                    raise ValueError('PUBLICATION_SCOPE')
            finally:
                self.principal = publisher
                self.policy()
        statuses = {m['repository']: ('published' if m['validation'] == 'verified'
                                     and view['status'] == 'active' else 'failed') for m in view['members']}
        if view['status'] != 'active':
            outcome = 'withdrawn' if view['status'] == 'withdrawn' else 'deferred'
        elif view['completion'] != 'complete' or any(s != 'published' for s in statuses.values()):
            outcome = 'partial' if 'published' in statuses.values() else 'failed'
        else:
            outcome = 'published'
        publication = {'goal': value['goal'], 'principal': audience, 'time': now(),
                       'outcome': outcome, 'members': statuses, 'view': self.save(view)}
        self.state['publications'].append(self.save(publication))
        self.event('publication', publication=self.state['publications'][-1])
        return {'outcome': outcome, 'members': statuses, 'withheld_count': view['withheld_count']}

    def wiki(self, value):
        shape(value, obj({'goal': NONEMPTY}))
        # Both query and publication access are required at serving time.
        self.policy()
        view = self.view(value['goal'], 'publish')
        publication_view = digest(view)
        hidden = [m for m in view['members'] if not self.allowed(m['repository'], 'query')]
        view['members'] = [m for m in view['members'] if self.allowed(m['repository'], 'query')]
        if hidden:
            view['withheld_count'] += len(hidden)
            view['completion'] = 'incomplete'
            view['integration'] = 'pending'
            view.pop('origin', None)
            view.pop('relations', None)
        if 'relations' in view:
            view['relations'] = [r for r in view['relations']
                                 if self.relation_allowed(self.object(r['record']), 'query')]
        history, latest = [], None
        for identity in self.state['publications']:
            publication = self.object(identity)
            if publication['goal'] == value['goal'] and publication['principal'] == self.principal:
                history.append({'time': publication['time'], 'outcome': publication['outcome']})
                latest = publication
        view['publication_history'] = history
        view['served'] = ('current' if history and history[-1]['outcome'] == 'published'
                          and latest['view'] == publication_view
                          and view['completion'] == 'complete' else 'unavailable_or_partial')
        if view['served'] != 'current':
            for member in view['members']:
                member.pop('documents', None)
        lines = ['# ' + view['goal'], '', 'Target version: ' + view['version'],
                 'Completion: ' + view['completion'], 'Publication: ' + view['served'], '']
        for member in view['members']:
            lines.extend(['## ' + member['repository'], 'Validation: ' + member['validation']])
            if 'current' in member:
                lines.extend(['Current commit: ' + member['current']['commit'], 'Target: ' + member['target']])
            for document in member.get('documents', []):
                lines.extend(['', document['path'], document['text']])
        if view['withheld_count']:
            lines.append('Required evidence withheld: ' + str(view['withheld_count']))
        view['markdown'] = '\n'.join(lines) + '\n'
        return view

    def predict(self, value):
        shape(value, PREDICT)
        goal = self.goal(value['goal'])
        if (value['origin']['request'] != goal['origin']['request'] or
                value['origin']['cause'] != goal['origin']['cause'] or
                not set(value['affected']) <= set(goal['members'])):
            raise ValueError('PREDICTION_CAUSE')
        intake = intake_reference(value['origin']['intake'])
        if intake['input']['origin'] != value['origin']['kind']:
            raise ValueError('ORIGIN_CHANGED')
        record = {**value, 'kind': 'prediction', 'goal_hash': digest(goal), 'time': now(),
                  'before': {r: self.source(r) for r in goal['members']}}
        record['before_documents'] = {r: self.documents(r, snapshot)
                                      for r, snapshot in record['before'].items()}
        identity = self.save(record)
        self.event('prediction', prediction=identity)
        return {'prediction': identity}

    def compare(self, value):
        shape(value, COMPARE)
        goal = self.goal(value['goal'])
        prediction = self.object(value['prediction'])
        if prediction['goal_hash'] != digest(goal):
            raise ValueError('PREDICTION_STALE')
        changes, documents = {}, {}
        for r, before in prediction['before'].items():
            actual = self.source(r)
            if capture(Path(self.host['repositories'][r]['path']), r, before['commit'], before['scope']) != before:
                raise ValueError('PREDICTION_SOURCE_CHANGED')
            changes[r] = source_compare(before, actual)
            current = self.documents(r, actual)
            documents[r] = {'before': prediction['before_documents'][r]['bindings']['id'],
                            'after': current['bindings']['id'],
                            'changed': prediction['before_documents'][r] != current}
        changed = [r for r, change in changes.items() if change['changes'] or documents[r]['changed']]
        omissions = sorted(set(changed) - set(prediction['affected']))
        for feedback in value['feedback']:
            intake_reference(feedback['intake'])
            if not set(feedback['repositories']) <= set(goal['members']):
                raise ValueError('FEEDBACK_SCOPE')
        covered = {r for f in value['feedback'] if f['kind'] == 'omission' for r in f['repositories']}
        record = {**value, 'kind': 'comparison', 'time': now(), 'changes': changes, 'documents': documents,
                  'omissions': omissions, 'request': prediction['origin']['request'],
                  'cause': prediction['origin']['cause'], 'unresolved': sorted(set(omissions) - covered),
                  'validation': self.view(goal['id'])}
        identity = self.save(record)
        self.event('comparison', comparison=identity)
        return {'comparison': identity, 'omissions': omissions,
                'unresolved': record['unresolved'], 'feedback_count': len(value['feedback']),
                'path': str(self.root / 'objects' / (identity + '.json'))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state', required=True, type=Path)
    parser.add_argument('--host', required=True, type=Path)
    parser.add_argument('--principal', required=True)
    parser.add_argument('action', choices=['init', 'goal', 'check', 'review-packet', 'attest',
                        'predict', 'compare', 'refresh', 'query', 'publish', 'wiki'])
    parser.add_argument('--input', type=Path)
    args = parser.parse_args()
    try:
        store = Store(args.state, args.host, args.principal)
        with store.locked(args.action == 'init'):
            if args.action not in ('query', 'wiki') and not store.actor['manage']:
                raise ValueError('ACCESS_DENIED')
            value = read(args.input) if args.input else {}
            method = {'goal': 'set_goal', 'check': 'run_checks', 'review-packet': 'review_packet'}.get(args.action, args.action)
            result = getattr(store, method)(value)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, TypeError, ValidationError, sqlite3.Error, subprocess.SubprocessError):
        # Raw provider errors can contain repository paths, excerpts and URLs.
        print(json.dumps({'error': 'REQUEST_UNAVAILABLE', 'action': args.action}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
