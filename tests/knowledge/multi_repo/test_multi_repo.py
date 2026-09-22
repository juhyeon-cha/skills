"""Synthetic receipts exercise contracts, never substitute for independent model observations."""
import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / 'plugins/toolkit/skills/refresh-knowledge/scripts'
if '--scripts' in sys.argv:
    SCRIPTS = Path(sys.argv[sys.argv.index('--scripts') + 1])
sys.path.insert(0, str(SCRIPTS))
from multi_repo import Store, canonical, digest, sha
from intake import classify
from project_service import initialize


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False))


class Fixture:
    def __init__(self):
        self.root = Path(tempfile.mkdtemp(prefix='knowledge-multi-')).resolve()
        self.host_path = self.root / 'host.json'
        self.host = {'version': 1, 'repositories': {}, 'principals': {
            'operator': {'manage': True, 'goals': ['contract'], 'repositories': {}},
            'reader': {'manage': False, 'goals': ['contract'], 'repositories': {}}}, 'checks': {}}
        self.revisions = {}
        for repository in ('producer', 'consumer'):
            repo = self.root / repository
            repo.mkdir()
            self.git(repo, 'init', '-q')
            self.git(repo, 'config', 'user.email', 'synthetic@example.invalid')
            self.git(repo, 'config', 'user.name', 'Synthetic fixture')
            self.host['repositories'][repository] = {'path': str(repo), 'url': 'https://' + repository + '.invalid',
                                                     'scope': ['app.py'], 'project': ''}
            for principal in self.host['principals'].values():
                principal['repositories'][repository] = ['source', 'query', 'publish']
            self.update(repository, 'amount')
            code = ("from app import value; assert value == 'total'" if repository == 'producer' else
                    "from app import value; assert value == 'total'")
            self.host['checks'][repository] = {'repositories': [repository],
                'argv': [sys.executable, '-B', '-c', code], 'cwd_repository': repository}
        self.host['checks']['exchange'] = {'repositories': ['producer', 'consumer'],
            'argv': [sys.executable, '-B', '-c',
                     "from pathlib import Path; assert \"'total'\" in Path('app.py').read_text(); "
                     "assert \"'total'\" in Path('../consumer/app.py').read_text()"], 'cwd_repository': 'producer'}
        self.persist()
        self.call('init', {}, initialize=True)
        self.goal = {'id': 'contract', 'version': 'v1', 'status': 'active',
                     'members': {r: {'target': r + '-secret total target', 'criteria': [r]}
                                 for r in self.host['repositories']}, 'integration': ['exchange'],
                     'origin': self.origin('user')}
        self.call('set_goal', self.goal)

    def git(self, path, *args):
        result = subprocess.run(['git', '-C', str(path), *args], capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stderr)
        return result.stdout.strip()

    def persist(self):
        write(self.host_path, self.host)

    def update(self, repository, value):
        repo = Path(self.host['repositories'][repository]['path'])
        (repo / 'app.py').write_text('# ' + repository + "\nvalue = '" + value + "'\n")
        self.git(repo, 'add', 'app.py')
        self.git(repo, 'commit', '-qm', value)
        revision = self.git(repo, 'rev-parse', 'HEAD')
        self.revisions[repository] = revision
        docs = self.root / (repository + '-docs-' + revision)
        docs.mkdir()
        text = repository + ' uses ' + value + '.'
        (docs / 'contract.md').write_text(text)
        spec = self.root / (repository + '-spec.json')
        write(spec, {'documents': [{'path': 'contract.md', 'claims': [
            {'id': 'field', 'text': text, 'evidence': ['app.py']}]}]})
        project = self.root / (repository + '-project-' + revision)
        initialize(SimpleNamespace(repo=repo, docs=docs, repository=repository, baseline=revision,
            path=['app.py'], spec=spec, audience='Synthetic reader', purpose='Synthetic contract fixture'), project)
        self.host['repositories'][repository]['project'] = str(project)
        self.persist()

    def origin(self, kind, status='confirmed'):
        code = 'Observed fixture amount source'
        request = 'Use total across both repositories'
        sources = [{'id': 'code', 'kind': 'code', 'authority': 'observed_implementation',
                    'version': self.revisions['producer'], 'locator': 'fixture:code', 'text': code, 'sha256': sha(code.encode())},
                   {'id': 'request', 'kind': 'user', 'authority': 'user_instruction',
                    'version': '1', 'locator': 'fixture:user', 'text': request, 'sha256': sha(request.encode())}]
        if kind == 'document':
            sources.append({'id': 'document', 'kind': 'document', 'authority': 'context', 'version': '1',
                            'locator': 'fixture:document', 'text': request, 'sha256': sha(request.encode())})
        record = classify({'version': 1, 'origin': kind, 'intent': 'behavior_change', 'sources': sources,
                           'current': {'code': 'code', 'description': 'amount'},
                           'target': {'sources': ['request'], 'description': 'total', 'acceptance': ['Both total'],
                                      'status': status},
                           'differences': [{'kind': 'behavior', 'description': 'amount to total', 'sources': ['code', 'request']}],
                           'rationale': 'Synthetic multi-repository test'})
        path = self.root / ('intake-' + record['id'] + '.json')
        write(path, record)
        return {'kind': kind, 'request': 'request-1', 'cause': 'rename-field',
                'intake': {'path': str(path), 'sha256': sha(path.read_bytes())}}

    def call(self, method, value, principal='operator', initialize=False):
        store = Store(self.root / 'state', self.host_path, principal)
        with store.locked(initialize):
            return getattr(store, method)(value)

    def review(self, members=None):
        selection = {'goal': 'contract'}
        if members:
            selection['repositories'] = members
        packet = self.call('review_packet', selection)
        response = {'packet': packet['packet'], 'verdict': 'pass', 'findings': [],
                    'implementation': 'pass', 'documents': 'pass'}
        stamp = datetime.now(timezone.utc).isoformat()
        receipt = {'goal': 'contract', 'packet': packet['packet'], 'author': 'synthetic-author',
                   'actor': 'synthetic-independent-reviewer', 'host_tool': 'synthetic-test-double',
                   'call_id': 'synthetic-' + packet['packet'], 'started_at': stamp, 'finished_at': stamp,
                   'prompt_sha256': packet['prompt_sha256'], 'raw_response': json.dumps(response),
                   'response': response, 'synthetic': True}
        return self.call('attest', receipt), receipt

    def complete(self):
        for repository in self.host['repositories']:
            self.update(repository, 'total')
        self.call('run_checks', {'goal': 'contract', 'checks': ['producer', 'consumer', 'exchange']})
        return self.review()


class Contracts(unittest.TestCase):
    def test_partial_then_complete_and_code_first(self):
        f = Fixture()
        f.update('producer', 'total')
        f.call('run_checks', {'goal': 'contract', 'checks': ['producer', 'exchange']})
        f.review(['producer'])
        partial = f.call('query', {'goal': 'contract'})
        self.assertEqual(partial['completion'], 'incomplete')
        members = {m['repository']: m for m in partial['members']}
        self.assertEqual(members['producer']['validation'], 'verified')
        self.assertEqual(members['consumer']['validation'], 'pending_or_stale')
        f.update('consumer', 'total')
        f.call('run_checks', {'goal': 'contract', 'checks': ['consumer', 'exchange']})
        f.review(['consumer'])
        self.assertEqual(f.call('publish', {'goal': 'contract'})['outcome'], 'partial')
        f.review()
        self.assertEqual(f.call('query', {'goal': 'contract'})['completion'], 'complete')

    def test_permissions_stale_index_and_wiki(self):
        f = Fixture()
        f.complete()
        f.call('refresh', {'goal': 'contract'})
        self.assertEqual(f.call('query', {'goal': 'contract'})['index'], 'current')
        self.assertEqual(f.call('publish', {'goal': 'contract'})['outcome'], 'published')
        self.assertEqual(f.call('wiki', {'goal': 'contract'})['served'], 'current')
        self.assertEqual(f.call('publish', {'goal': 'contract', 'audience': 'reader'})['outcome'], 'published')
        self.assertEqual(f.call('wiki', {'goal': 'contract'}, 'reader')['served'], 'current')
        f.host['principals']['operator']['repositories']['consumer'] = []
        f.persist()
        for method in ('query', 'wiki'):
            result = f.call(method, {'goal': 'contract'})
            public = json.dumps(result)
            self.assertNotIn('consumer', public)
            self.assertNotIn(str(f.root), public)
            self.assertEqual(result['withheld_count'], 1)
            self.assertEqual(result['required_count'], 2)
            self.assertEqual(result['completion'], 'incomplete')
        f.host['principals']['operator']['repositories']['consumer'] = ['source', 'publish']
        f.persist()
        self.assertNotIn('consumer', json.dumps(f.call('wiki', {'goal': 'contract'})))

    def test_removed_member_history_requires_current_full_scope(self):
        f = Fixture()
        old = f.call('predict', {'goal': 'contract', 'origin': f.origin('user'),
            'affected': ['producer'], 'rationale': 'Mixed historical scope'})['prediction']
        comparison = f.call('compare', {'goal': 'contract', 'prediction': old, 'feedback': [
            {'kind': 'decision', 'repositories': ['producer'], 'intake': f.origin('user')['intake'],
             'description': 'PRIVATE historical consumer feedback'}]})['comparison']
        f.goal['version'] = 'v2'
        del f.goal['members']['consumer']
        f.goal['integration'] = ['producer']
        f.call('set_goal', f.goal)
        visible = f.call('predict', {'goal': 'contract', 'origin': f.origin('user'),
            'affected': ['producer'], 'rationale': 'Visible history'})['prediction']
        visible_comparison = f.call('compare', {'goal': 'contract', 'prediction': visible,
            'feedback': []})['comparison']
        expected = {old, comparison, visible, visible_comparison}
        for method in ('refresh', 'query', 'wiki'):
            self.assertEqual({r['record'] for r in f.call(method, {'goal': 'contract'})['relations']}, expected)
        for rights in ([], ['source', 'publish'], ['source', 'query']):
            f.host['principals']['operator']['repositories']['consumer'] = rights
            f.persist()
            for method in ('refresh', 'query', 'wiki'):
                with self.subTest(rights=rights, method=method):
                    result = f.call(method, {'goal': 'contract'})
                    permitted = method != 'wiki' and 'query' in rights
                    self.assertEqual({r['record'] for r in result['relations']},
                        expected if permitted else {visible, visible_comparison})
                    if not permitted:
                        self.assertNotIn('consumer', json.dumps(result))
                        self.assertNotIn('PRIVATE', json.dumps(result))
                    self.assertEqual(result['withheld_count'], 0)
                    if method == 'refresh':
                        state = json.loads((f.root / 'state/state.json').read_text())
                        cached = json.loads((f.root / 'state/objects' / (state['index']['contract'] + '.json')).read_text())
                        self.assertEqual(cached, result)
        f.host['principals']['operator']['repositories']['consumer'] = ['source', 'query', 'publish']
        f.persist()
        self.assertEqual({r['record'] for r in f.call('wiki', {'goal': 'contract'})['relations']}, expected)

    def test_drift_missing_and_tampered_evidence(self):
        f = Fixture()
        _, receipt = f.complete()
        f.call('refresh', {'goal': 'contract'})
        f.update('producer', 'third')
        stale = f.call('query', {'goal': 'contract'})
        self.assertEqual(stale['index'], 'stale')
        self.assertEqual(stale['completion'], 'incomplete')
        with self.assertRaises(ValueError):
            f.call('attest', receipt)
        f2 = Fixture()
        review, _ = f2.complete()
        path = f2.root / 'state/objects' / (review['review'] + '.json')
        path.rename(path.with_suffix('.missing'))
        self.assertEqual(f2.call('query', {'goal': 'contract'})['completion'], 'incomplete')
        f3 = Fixture()
        _, receipt3 = f3.complete()
        path = f3.root / 'state/objects' / (receipt3['packet'] + '.json')
        path.write_text('{}')
        self.assertEqual(f3.call('query', {'goal': 'contract'})['completion'], 'incomplete')

    def test_goal_change_withdrawal_and_failed_publication(self):
        f = Fixture()
        f.complete()
        f.call('publish', {'goal': 'contract'})
        f.goal['version'] = 'v2'
        f.goal['members']['consumer']['target'] = 'another goal'
        f.call('set_goal', f.goal)
        self.assertEqual(f.call('query', {'goal': 'contract'})['completion'], 'incomplete')
        f.call('run_checks', {'goal': 'contract', 'checks': ['producer', 'consumer', 'exchange']})
        f.review()
        self.assertEqual(f.call('wiki', {'goal': 'contract'})['served'], 'unavailable_or_partial')
        consumer = Path(f.host['repositories']['consumer']['path'])
        consumer.rename(consumer.with_name('unavailable'))
        failed = f.call('publish', {'goal': 'contract'})
        self.assertEqual(failed['outcome'], 'partial')
        self.assertEqual(failed['members']['consumer'], 'failed')
        f.goal.update(version='v3', status='withdrawn', origin=f.origin('document', 'withdrawn'))
        f.call('set_goal', f.goal)
        self.assertEqual(f.call('publish', {'goal': 'contract'})['outcome'], 'withdrawn')
        wiki = f.call('wiki', {'goal': 'contract'})
        self.assertEqual([p['outcome'] for p in wiki['publication_history']], ['published', 'partial', 'withdrawn'])
        self.assertIn('total', (f.root / 'producer/app.py').read_text())

    def test_identity_move_prediction_feedback_all_origins(self):
        f = Fixture()
        predictions = []
        for kind in ('code', 'document', 'user'):
            predictions.append(f.call('predict', {'goal': 'contract', 'origin': f.origin(kind),
                'affected': ['producer'], 'rationale': 'Synthetic deliberately omitted consumer'})['prediction'])
        f.complete()
        result = f.call('compare', {'goal': 'contract', 'prediction': predictions[0], 'feedback': []})
        self.assertEqual(result['unresolved'], ['consumer'])
        fixed = f.call('compare', {'goal': 'contract', 'prediction': predictions[0], 'feedback': [
            {'kind': 'omission', 'repositories': ['consumer'], 'intake': f.origin('code')['intake'],
             'description': 'Synthetic actual consumer must follow producer'},
            {'kind': 'decision', 'repositories': ['producer', 'consumer'], 'intake': f.origin('user')['intake'],
             'description': 'Synthetic shared contract decision'}]})
        self.assertEqual(fixed['unresolved'], [])
        self.assertEqual(len(f.call('query', {'goal': 'contract'})['relations']), 5)
        original = f.root / 'producer'
        clone = f.root / 'relocated'
        f.git(f.root, 'clone', '-q', str(original), str(clone))
        f.host['repositories']['producer']['path'] = str(clone)
        f.persist()
        self.assertEqual(f.call('query', {'goal': 'contract'})['completion'], 'complete')
        f.host['repositories']['producer']['path'] = str(f.root / 'consumer')
        f.persist()
        members = {m['repository']: m for m in f.call('query', {'goal': 'contract'})['members']}
        self.assertEqual(members['producer']['validation'], 'source_unavailable')

    def test_fail_closed_input_and_cli(self):
        f = Fixture()
        f.complete()
        packet = f.call('review_packet', {'goal': 'contract'})
        evidence = json.loads(Path(packet['path']).read_text())
        self.assertIn('stdout', evidence['check_evidence']['exchange'])
        bad = copy.deepcopy(f.goal)
        bad['verified'] = True
        with self.assertRaises(Exception):
            f.call('set_goal', bad)
        _, receipt = f.review()
        receipt['actor'] = receipt['author']
        with self.assertRaises(ValueError):
            f.call('attest', receipt)
        f.host['principals']['reader']['repositories']['consumer'] = []
        f.persist()
        request = f.root / 'query.json'
        write(request, {'goal': 'contract'})
        command = [sys.executable, str(SCRIPTS / 'multi_repo.py'), '--state', str(f.root / 'state'),
                   '--host', str(f.host_path), '--principal', 'reader', 'query', '--input', str(request)]
        proc = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn('consumer', proc.stdout + proc.stderr)
        write(request, {'goal': 'PRIVATE-' + str(f.root)})
        proc = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertNotIn(str(f.root), proc.stdout + proc.stderr)

    def test_permission_negative_control(self):
        copied = Path(tempfile.mkdtemp(prefix='knowledge-permission-negative-')) / 'scripts'
        shutil.copytree(SCRIPTS, copied)
        path = copied / 'multi_repo.py'
        source = path.read_text()
        boundary = "return 'source' in rights and scope in rights  # PERMISSION_BOUNDARY"
        self.assertEqual(source.count(boundary), 1)
        path.write_text(source.replace(boundary, 'return True  # isolated negative control'))
        proc = subprocess.run([sys.executable, str(Path(__file__)), '--permission-probe', '--scripts', str(copied)],
                              capture_output=True, text=True)
        self.assertNotEqual(proc.returncode, 0, 'permission rule removal must break the probe')
        self.assertIn('PERMISSION_EXPOSURE', proc.stderr)
        print('Permission negative control: removed guard caused expected PERMISSION_EXPOSURE')


if __name__ == '__main__':
    if '--permission-probe' in sys.argv:
        fixture = Fixture()
        fixture.host['principals']['reader']['repositories']['consumer'] = []
        fixture.persist()
        output = json.dumps(fixture.call('query', {'goal': 'contract'}, 'reader'))
        assert 'consumer' not in output, 'PERMISSION_EXPOSURE'
    else:
        print('All model receipts in this regression are SYNTHETIC; live model quality is untested here.')
        unittest.main()
