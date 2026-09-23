"""Exercise only the copied plugin's public CLI from unrelated project directories."""
import json
from contextlib import closing
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest

PLUGIN = Path(__file__).resolve().parents[3] / 'plugins/knowledge'


class InstalledProjectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.package = tempfile.TemporaryDirectory(prefix='installed knowledge ')
        cls.addClassCleanup(cls.package.cleanup)
        cls.installed = Path(cls.package.name) / 'knowledge'
        shutil.copytree(PLUGIN, cls.installed, ignore=shutil.ignore_patterns('__pycache__'))
        cls.skill = cls.installed / 'skills/update'
        cls.cli_path = cls.installed / 'scripts/knowledge.py'
        cls.writer = (Path(cls.package.name) / 'external-writer').resolve()
        shutil.copytree(PLUGIN.parent / 'toolkit/skills/writing-for-humans', cls.writer)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='knowledge project ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.writer_path = self.writer
        self.repo = self.root / 'repo'; self.repo.mkdir()
        self.docs = self.root / 'docs'; self.docs.mkdir()
        self.project = self.root / 'project'
        self.git('init', '-q'); self.git('config', 'user.name', 'Installed Test')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.baseline = self.commit(1)
        (self.docs / 'guide.md').write_text('호출은 1회 시도한다.\n')
        self.spec = self.save('spec.json', {'documents': [{'path': 'guide.md', 'claims': [
            {'id': 'limit', 'text': '호출은 1회 시도한다.', 'evidence': ['service.py']}]}]})
        self.command('init', '--repo', self.repo, '--docs', self.docs, '--repository', 'fixture/service',
                     '--baseline', self.baseline, '--path', 'service.py', '--spec', self.spec,
                     '--audience', 'API 사용자', '--purpose', '호출 횟수를 판단한다')

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True).strip()

    def commit(self, count):
        (self.repo / 'service.py').write_text(f'ATTEMPTS = {count}\n')
        self.git('add', '.'); self.git('commit', '-qm', f'count {count}')
        return self.git('rev-parse', 'HEAD')

    def save(self, name, value):
        p = self.root / name; p.write_text(json.dumps(value, ensure_ascii=False)); return p

    def command(self, *args, ok=True):
        env = dict(os.environ); env.pop('PYTHONPATH', None); env.pop('KNOWLEDGE_RUNTIME', None)
        env['KNOWLEDGE_WRITER_SKILL'] = str(self.writer_path)
        result = subprocess.run([sys.executable, str(self.cli_path), '--project', str(self.project),
                                 *map(str, args)], cwd=self.root, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        if ok:
            return json.loads(result.stdout)
        return result

    def ready(self, revision, count, register=True):
        run = self.command('start', '--rev', revision)
        context = json.loads(Path(run['context']).read_text())
        decisions = {'impact': context['impact']['id'], 'claims': [{'path': 'guide.md', 'id': 'limit',
                     'action': 'replace', 'reason': 'Configured attempts changed.',
                     'text': f'호출은 {count}회 시도한다.', 'evidence': ['service.py']}], 'unlinked': []}
        result = self.command('prepare', '--run', run['run'], '--decisions', self.save(f'decisions-{count}.json', decisions))
        packet = json.loads(Path(result['packet']).read_text())
        review = {'packet': packet['id'], 'plan': packet['plan']['id'], 'verdict': 'pass',
                  'checks': {k: 'pass' for k in ['source_fidelity', 'decision_coverage', 'reader_action', 'uncertainty']}, 'findings': []}
        review_file = self.save(f'review-{count}.json', review)
        if register:
            result = self.command('review', '--run', run['run'], '--review', review_file)
            self.assertEqual(result['phase'], 'ready')
        return result, packet, review

    def without_authoring_skills(self):
        isolated = self.root / 'runtime-only-toolkit'
        shutil.copytree(self.installed, isolated)
        skill = isolated / 'skills/review'
        skill.rename(skill.with_name('review.held'))
        self.writer_path = self.root / 'absent-writer'
        self.cli_path = isolated / 'scripts/knowledge.py'

    def test_review_and_resume_without_authoring_skills_preserve_checks(self):
        revision = self.commit(2)
        run, _, review = self.ready(revision, 2, register=False)
        self.without_authoring_skills()
        self.assertIn('DEPENDENCY_UNREACHED', self.command('doctor', ok=False).stderr)
        self.assertEqual(self.command('resume', '--run', run['run'])['phase'], 'awaiting_review')
        stale = dict(review, packet='0' * 64)
        self.assertIn('REVIEW_STALE', self.command('review', '--run', run['run'], '--review',
                      self.save('stale.json', stale), ok=False).stderr)
        failed = dict(review, verdict='revise', findings=['Clarify caller action.'])
        self.assertEqual(self.command('review', '--run', run['run'], '--review',
                         self.save('failed.json', failed))['phase'], 'revise')
        self.assertEqual(self.command('resume', '--run', run['run'])['phase'], 'revise')
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 1회 시도한다.\n')
        self.assertEqual(self.command('status')['baseline'], self.baseline)
        self.assertEqual(self.command('review', '--run', run['run'], '--review',
                         self.root / 'review-2.json')['phase'], 'ready')
        original = (self.docs / 'guide.md').read_bytes()
        (self.docs / 'guide.md').write_text('Independent edit.')
        self.command('resume', '--run', run['run'], ok=False)
        self.assertEqual((self.docs / 'guide.md').read_text(), 'Independent edit.')
        self.assertEqual(self.command('status')['baseline'], self.baseline)
        (self.docs / 'guide.md').write_bytes(original)
        self.assertEqual(self.command('resume', '--run', run['run'])['phase'], 'completed')
        self.assertEqual(self.command('resume', '--run', run['run'])['phase'], 'completed')
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 2회 시도한다.\n')
        self.assertEqual(self.command('status')['baseline'], revision)

    def test_missing_runtime_blocks_review_and_resume_before_mutation(self):
        run, _, _ = self.ready(self.commit(2), 2)
        self.without_authoring_skills()
        before = {p.relative_to(self.project): p.read_bytes() for p in self.project.rglob('*') if p.is_file()}
        env = dict(os.environ, PATH=str(self.root / 'no-executables'))
        for args in [('review', '--review', self.root / 'review-2.json'), ('resume',)]:
            result = subprocess.run([sys.executable, str(self.cli_path), '--project', str(self.project),
                                     *map(str, args), '--run', run['run']], cwd=self.root,
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertEqual(json.loads(result.stderr)['code'], 'DEPENDENCY')
            self.assertIn('Git is missing', result.stderr)
            self.assertEqual(result.stdout, '')
        self.assertEqual({p.relative_to(self.project): p.read_bytes() for p in self.project.rglob('*') if p.is_file()}, before)
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 1회 시도한다.\n')

    def test_two_distinct_changes_advance_baseline_and_repeat(self):
        second = self.commit(2)
        run, packet, _ = self.ready(second, 2)
        self.assertEqual(self.command('start', '--rev', second)['run'], run['run'])
        self.assertEqual(self.command('resume', '--run', run['run'])['phase'], 'completed')
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 2회 시도한다.\n')
        self.assertEqual(self.command('status')['baseline'], second)
        self.assertEqual(self.command('start', '--rev', second)['phase'], 'unchanged')
        third = self.commit(3)
        next_run, next_packet, _ = self.ready(third, 3)
        self.assertEqual(next_packet['before'], packet['after'])
        self.assertEqual(next_packet['bindings'], packet['plan']['next_bindings'])
        self.command('resume', '--run', next_run['run'])
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 3회 시도한다.\n')
        self.assertEqual(self.command('status')['baseline'], third)
        self.command('resume', '--run', run['run'])
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 3회 시도한다.\n')
        self.assertEqual(len(self.command('status')['runs']), 2)

    def test_process_exit_after_apply_recovers_from_run_id(self):
        revision = self.commit(2)
        run, _, _ = self.ready(revision, 2)
        code = '''import sys, os
sys.path.insert(0, sys.argv[1])
import knowledge, workflow
original = workflow.finish
def interrupted(*args, **kwargs):
    original(*args, **kwargs)
    os._exit(91)
workflow.finish = interrupted
sys.argv = ['knowledge', '--project', sys.argv[2], 'resume', '--run', sys.argv[3]]
knowledge.main()
'''
        child = subprocess.run([sys.executable, '-c', code, str(self.cli_path.parent), str(self.project), run['run']], capture_output=True)
        self.assertEqual(child.returncode, 91, child.stderr)
        self.without_authoring_skills()
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 2회 시도한다.\n')
        self.assertEqual(self.command('status')['baseline'], self.baseline)
        self.assertEqual(self.command('status', '--run', run['run'])['phase'], 'applying')
        reason = self.root / 'stop.txt'; reason.write_text('Stop partial application.')
        self.assertIn('RUN_PHASE', self.command('terminate', '--run', run['run'], '--reason-file', reason, ok=False).stderr)
        self.assertEqual(self.command('resume', '--run', run['run'])['phase'], 'completed')
        self.assertEqual(self.command('status')['baseline'], revision)

    def test_handoff_locates_verified_documents_using_public_status(self):
        revision = self.commit(2)
        run, packet, _ = self.ready(revision, 2)
        settings = self.command('status')['settings']
        self.assertEqual(settings['repo'], str(self.repo.resolve()))
        self.assertEqual(settings['docs'], str(self.docs.resolve()))
        self.assertEqual(settings['audience'], 'API 사용자')
        self.assertEqual(settings['purpose'], '호출 횟수를 판단한다')
        handed = self.command('status', '--run', run['run'])
        self.assertEqual(handed['settings'], settings)
        self.assertEqual(handed['project'], str(self.project.resolve()))
        completed = self.command('resume', '--run', handed['run'])
        receipt = json.loads(Path(completed['completion']).read_text())
        for document in receipt['next_bindings']['documents']:
            actual = (Path(handed['settings']['docs']) / document['path']).read_text()
            self.assertEqual(actual, packet['plan']['documents'][0]['after_text'])
        self.assertEqual(self.command('status')['settings'], settings)

    def test_current_review_handoff_and_prepare_clear_previous_review(self):
        run, packet, review = self.ready(self.commit(2), 2)
        review['verdict'] = 'revise'
        for finding in ['Explain caller action.', 'Explain the failure condition.']:
            review['findings'] = [finding]
            self.command('review', '--run', run['run'], '--review', self.save('revision.json', review))
            status = self.command('status', '--run', run['run'])
            self.assertEqual(status['next_action'], 'prepare')
            self.assertEqual(json.loads(Path(status['review']['path']).read_text()), review)
            self.assertEqual(Path(status['review']['path']).name, 'review-' + status['review']['id'] + '.json')
        self.assertEqual(len(list(Path(run['packet']).parent.glob('review-*.json'))), 3)
        self.command('prepare', '--run', run['run'], '--decisions', self.root / 'decisions-2.json')
        handed = self.command('status', '--run', run['run'])
        self.assertNotIn('review', handed)
        self.assertEqual(handed['next_action'], 'review')
        self.assertEqual(handed['packet'], run['packet'])

    def test_handoff_refuses_damaged_current_review_without_repairing_it(self):
        run, _, _ = self.ready(self.commit(2), 2)
        review = Path(self.command('status', '--run', run['run'])['review']['path'])
        held = review.with_suffix('.held')
        for kind in ('malformed', 'changed', 'missing', 'symlink'):
            with self.subTest(kind=kind):
                review.rename(held)
                try:
                    if kind == 'malformed': review.write_bytes(b'{')
                    if kind == 'changed': review.write_text('{}')
                    if kind == 'symlink': review.symlink_to(held)
                    original = review.read_bytes() if review.exists() else None
                    self.assertIn('REVIEW_INVALID', self.command('status', '--run', run['run'], ok=False).stderr)
                    self.assertEqual(self.command('status')['runs'][0]['review_integrity'], 'unchecked')
                    inspected = self.command('status', '--deep')['runs'][0]
                    self.assertEqual(inspected['review_integrity'], 'invalid')
                    self.assertEqual(inspected['context_integrity'], 'verified')
                    self.assertEqual(review.read_bytes() if review.exists() else None, original)
                    self.assertEqual(review.is_symlink(), kind == 'symlink')
                finally:
                    if review.exists() or review.is_symlink(): review.rename(review.with_suffix('.damaged-' + kind))
                    held.rename(review)
        self.assertEqual(self.command('status', '--run', run['run'])['review_integrity'], 'verified')

    def test_command_scoped_git_capture_and_full_snapshot_comparison(self):
        revision = self.commit(2)
        run, _, _ = self.ready(revision, 2)
        code = r'''import copy,json,sys
sys.path.insert(0, sys.argv[1])
import knowledge,impact
from source_verification import command_sources,verify_source
from pathlib import Path
coordinates=sys.argv[:]
packet=json.loads(Path(coordinates[5]).read_text())
original=impact.capture
calls=[]
def capture(*args):
    calls.append(args[2])
    return original(*args)
impact.capture=capture
for argv in [ ['review','--review',coordinates[4]], ['resume'] ]:
    knowledge.sys.argv=['knowledge','--project',coordinates[2],*argv,'--run',coordinates[3]]
    assert knowledge.main()==0
    assert calls==[packet['before']['commit'],packet['after']['commit']], calls
    calls.clear()
packet=json.loads(Path(coordinates[5]).read_text())
with command_sources():
    verify_source(Path(coordinates[6]), packet['before'], capture)
    damaged=copy.deepcopy(packet['before'])
    damaged['files'][0]['text']='tampered while retaining ID'
    try:
        verify_source(Path(coordinates[6]), damaged, capture)
    except ValueError as error:
        assert 'SOURCE_MISMATCH' in str(error)
    else:
        raise AssertionError('cache trusted changed content')
assert len(calls)==1
'''
        result = subprocess.run([sys.executable, '-c', code, str(self.cli_path.parent), str(self.project),
                                 run['run'], str(self.root / 'review-2.json'), run['packet'], str(self.repo)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.command('status')['baseline'], revision)

    def test_listing_projects_state_without_loading_historical_bodies(self):
        first, _, _ = self.ready(self.commit(2), 2)
        self.command('resume', '--run', first['run'])
        second, _, _ = self.ready(self.commit(3), 3)
        Path(first['context']).write_bytes(b'{')
        code = r'''import sys
sys.path.insert(0, sys.argv[1])
import knowledge,project_store
original=project_store.json.loads
def loads(value,*args,**kwargs):
    assert '"files"' not in value and '"documents"' not in value, 'deserialized historical body'
    return original(value,*args,**kwargs)
project_store.json.loads=loads
def forbidden(*args,**kwargs):
    raise AssertionError('listing loaded full run or context')
project_store.run_row=forbidden
import project_service
project_service.run_row=forbidden
project_store.read=forbidden
sys.argv=['knowledge','--project',sys.argv[2],'status']
assert knowledge.main()==0
'''
        child = subprocess.run([sys.executable, '-c', code, str(self.cli_path.parent), str(self.project)],
                               capture_output=True, text=True)
        self.assertEqual(child.returncode, 0, child.stderr)
        self.assertEqual([r['context_integrity'] for r in json.loads(child.stdout)['runs']], ['unchecked', 'unchecked'])
        deep = self.command('status', '--deep')['runs']
        self.assertEqual([r['context_integrity'] for r in deep], ['invalid', 'verified'])
        self.assertEqual(Path(first['context']).read_bytes(), b'{')
        self.assertEqual(self.command('status', '--run', second['run'])['phase'], 'ready')
        self.command('status', '--run', first['run'], ok=False)

    def test_active_run_and_database_lock_block_competing_writes(self):
        second = self.commit(2)
        run = self.command('start', '--rev', second)
        third = self.commit(3)
        self.assertIn('RUN_ACTIVE', self.command('start', '--rev', third, ok=False).stderr)
        with closing(sqlite3.connect(self.project / 'project.sqlite3')) as db:
            db.execute('BEGIN IMMEDIATE')
            self.assertIn('locked', self.command('start', '--rev', second, ok=False).stderr)
        self.assertEqual(self.command('resume', '--run', run['run'])['phase'], 'awaiting_decisions')
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 1회 시도한다.\n')

    def test_stale_review_and_changed_documents_do_not_advance(self):
        second = self.commit(2)
        run, _, review = self.ready(second, 2)
        review['packet'] = '0' * 64
        self.assertIn('REVIEW_STALE', self.command('review', '--run', run['run'], '--review', self.save('wrong.json', review), ok=False).stderr)
        (self.docs / 'guide.md').write_text('Independent edit.')
        self.command('resume', '--run', run['run'], ok=False)
        self.assertEqual(self.command('status')['baseline'], self.baseline)
        self.assertEqual((self.docs / 'guide.md').read_text(), 'Independent edit.')

    def test_exported_packet_tampering_and_completed_document_drift_fail(self):
        revision = self.commit(2)
        run, packet, review = self.ready(revision, 2)
        packet_file = Path(run['packet'])
        original = packet_file.read_bytes()
        damaged = json.loads(original)
        damaged['plan']['documents'][0]['after_text'] = 'Unreviewed content.'
        packet_file.write_text(json.dumps(damaged))
        self.assertIn('ARTIFACT_CONFLICT', self.command('review', '--run', run['run'], '--review', self.save('review-again.json', review), ok=False).stderr)
        self.command('resume', '--run', run['run'], ok=False)
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 1회 시도한다.\n')
        packet_file.write_bytes(original)
        self.command('resume', '--run', run['run'])
        (self.docs / 'guide.md').write_text('Later independent edit.')
        self.command('resume', '--run', run['run'], ok=False)
        self.assertEqual((self.docs / 'guide.md').read_text(), 'Later independent edit.')

    def test_corrupt_artifacts_report_path_and_preserve_state(self):
        revision = self.commit(2)
        run, _, review = self.ready(revision, 2)
        packet = Path(run['packet'])
        original = packet.read_bytes()
        for damaged in (b'', b'{', b'\xff'):
            packet.write_bytes(damaged)
            result = self.command('review', '--run', run['run'], '--review',
                                  self.save('review-retry.json', review), ok=False)
            self.assertIn('ARTIFACT_CORRUPT: ' + str(packet), result.stderr)
            direct = subprocess.run([sys.executable, str(self.cli_path.parent / 'workflow.py'),
                                     'finish', '--packet', str(packet), '--review', str(self.root / 'review-retry.json'),
                                     '--repo', str(self.repo), '--docs-root', str(self.docs),
                                     '--out', str(self.root / 'unused.json')], capture_output=True, text=True)
            self.assertEqual(direct.returncode, 1)
            self.assertIn('ARTIFACT_CORRUPT: ' + str(packet), direct.stderr)
            self.assertFalse((self.root / 'unused.json').exists())
            self.assertEqual(packet.read_bytes(), damaged)
            self.assertEqual(self.command('status', '--run', run['run'])['phase'], 'ready')
        packet.write_bytes(original)
        code = '''import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import knowledge, workflow
def interrupted(path, value):
    Path(path).write_bytes(b'')
    raise OSError('simulated interrupted completion write')
workflow.write_new = interrupted
sys.argv = ['knowledge', '--project', sys.argv[2], 'resume', '--run', sys.argv[3]]
sys.exit(knowledge.main())
'''
        child = subprocess.run([sys.executable, '-c', code, str(self.cli_path.parent),
                                str(self.project), run['run']], capture_output=True)
        self.assertEqual(child.returncode, 1, child.stderr)
        receipt = self.project / 'runs' / run['run'] / 'complete.json'
        result = self.command('resume', '--run', run['run'], ok=False)
        self.assertIn('ARTIFACT_CORRUPT: ' + str(receipt.resolve()), result.stderr)
        self.assertIn('trusted original record', result.stderr)
        self.assertEqual(receipt.read_bytes(), b'')
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 2회 시도한다.\n')
        self.assertEqual(self.command('status')['baseline'], self.baseline)
        self.assertEqual(self.command('status', '--run', run['run'])['phase'], 'applying')

    def test_init_and_unknown_schema_preserve_existing_state(self):
        self.command('init', '--repo', self.repo, '--docs', self.docs, '--repository', 'fixture/service',
                     '--baseline', self.baseline, '--path', 'service.py', '--spec', self.spec,
                     '--audience', 'reader', '--purpose', 'purpose', ok=False)
        self.assertEqual(self.command('status')['baseline'], self.baseline)
        with closing(sqlite3.connect(self.project / 'project.sqlite3')) as db:
            db.execute('PRAGMA user_version=2')
        self.assertIn('PROJECT_VERSION', self.command('status', ok=False).stderr)

    def test_terminate_retire_and_successor_preserve_evidence(self):
        second = self.commit(2)
        run = self.command('start', '--rev', second)
        explanation = self.root / 'reason.txt'
        explanation.write_text('Scope changed; preserve old evidence.')
        context = Path(run['context']).read_bytes()
        self.assertEqual(self.command('terminate', '--run', run['run'], '--reason-file', explanation)['phase'], 'terminated')
        self.assertEqual(Path(run['context']).read_bytes(), context)
        self.assertIsNone(self.command('status')['active'])
        self.assertEqual(self.command('status')['baseline'], self.baseline)
        self.assertIn('RUN_TERMINATED', self.command('start', '--rev', second, ok=False).stderr)
        third = self.commit(3)
        run, _, _ = self.ready(third, 3)
        Path(run['packet']).write_bytes(b'{')
        self.command('resume', '--run', run['run'], ok=False)
        successor = self.root / 'successor'
        result = self.command('retire', '--reason-file', explanation, '--successor', successor)
        self.assertEqual(result['phase'], 'retired')
        self.assertEqual(Path(run['packet']).read_bytes(), b'{')
        self.assertIn('PROJECT_RETIRED', self.command('start', '--rev', third, ok=False).stderr)
        self.assertEqual(self.command('status')['baseline'], self.baseline)
        self.project = successor
        self.command('init', '--repo', self.repo, '--docs', self.docs, '--repository', 'fixture/service',
                     '--baseline', self.baseline, '--path', 'service.py', '--spec', self.spec,
                     '--audience', 'reader', '--purpose', 'reviewed successor')
        self.assertEqual(self.command('start', '--rev', third)['phase'], 'awaiting_decisions')

    def test_public_intake_handoff_and_code_route(self):
        from test_intake import fixture
        value = fixture()
        record = self.command('intake', '--input', self.save('request.json', value))
        self.assertEqual(record['phase'], 'pending_implementation')
        self.assertEqual(self.command('intake-status', '--intake', record['intake'])['input']['current']['code'], None)
        second = self.commit(2)
        self.assertIn('INTAKE_ROUTE', self.command('start', '--rev', second, '--intake', record['intake'], ok=False).stderr)
        value = fixture('current_behavior')
        value['sources'][0]['version'] = second
        record = self.command('intake', '--input', self.save('code-request.json', value))
        run = self.command('start', '--rev', second, '--intake', record['intake'])
        self.assertEqual(json.loads(Path(run['context']).read_text())['intake']['id'], record['intake'])
        self.assertEqual(self.command('start', '--rev', second, '--intake', record['intake'])['run'], run['run'])
        self.assertIn('INTAKE_CHANGED', self.command('start', '--rev', second, ok=False).stderr)
        value['target']['status'] = 'withdrawn'
        withdrawn = self.command('intake', '--input', self.save('withdrawn.json', value))
        self.assertIn('INTAKE_ROUTE', self.command('start', '--rev', second, '--intake', withdrawn['intake'], ok=False).stderr)
        with closing(sqlite3.connect(self.project / 'project.sqlite3')) as db:
            db.execute('BEGIN IMMEDIATE')
            self.assertIn('locked', self.command('intake', '--input', self.root / 'code-request.json', ok=False).stderr)

    def test_context_corruption_blocks_every_reentry_and_recovers(self):
        revision = self.commit(2)
        run, _, review = self.ready(revision, 2)
        context = Path(run['context'])
        original = context.read_bytes()
        commands = [('status', '--run', run['run']),
                    ('start', '--rev', revision), ('resume', '--run', run['run']),
                    ('prepare', '--run', run['run'], '--decisions', self.root / 'decisions-2.json'),
                    ('review', '--run', run['run'], '--review', self.root / 'review-2.json')]
        changed = json.loads(original); changed['purpose'] = 'Untrusted purpose'
        for kind in ['malformed', 'changed', 'missing', 'symlink']:
            with self.subTest(kind=kind):
                held = context.with_suffix('.held')
                context.rename(held)
                try:
                    if kind == 'malformed': context.write_bytes(b'{')
                    if kind == 'changed': context.write_text(json.dumps(changed))
                    if kind == 'symlink': context.symlink_to(held)
                    damaged = context.read_bytes() if context.exists() else None
                    listing = self.command('status')['runs'][0]
                    self.assertEqual(listing['context_integrity'], 'unchecked')
                    inspected = self.command('status', '--deep')['runs'][0]
                    self.assertEqual(inspected['context_integrity'], 'invalid')
                    self.assertIn('CONTEXT_INVALID', inspected['context_error'])
                    for command in commands:
                        result = self.command(*command, ok=False)
                        self.assertIn('CONTEXT_INVALID', result.stderr)
                        self.assertIn('terminate', result.stderr)
                        self.assertEqual(context.read_bytes() if context.exists() else None, damaged)
                        self.assertEqual(context.is_symlink(), kind == 'symlink')
                    with closing(sqlite3.connect(self.project / 'project.sqlite3')) as db:
                        self.assertEqual(json.loads(db.execute('SELECT current FROM project').fetchone()[0])['snapshot']['commit'], self.baseline)
                        self.assertEqual(json.loads(db.execute('SELECT data FROM runs').fetchone()[0])['phase'], 'ready')
                    self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 1회 시도한다.\n')
                finally:
                    if context.exists() or context.is_symlink(): context.rename(context.with_suffix('.damaged-' + kind))
                    held.rename(context)
                self.assertEqual(self.command('status', '--run', run['run'])['phase'], 'ready')
        self.assertEqual(self.command('resume', '--run', run['run'])['phase'], 'completed')

    def test_corrupt_context_allows_termination_and_retirement(self):
        run, _, _ = self.ready(self.commit(2), 2)
        context = Path(run['context']); context.write_bytes(b'{')
        reason = self.root / 'reason.txt'; reason.write_text('Preserve corrupted handoff.')
        self.assertEqual(self.command('terminate', '--run', run['run'], '--reason-file', reason)['phase'], 'terminated')
        self.assertEqual(context.read_bytes(), b'{')
        self.assertEqual(self.command('retire', '--reason-file', reason, '--successor', self.root / 'successor')['phase'], 'retired')
        self.assertEqual(context.read_bytes(), b'{')

    def test_intake_binds_packet_and_legacy_ready_cannot_apply(self):
        from test_intake import fixture, source
        revision = self.commit(2)
        original_project = self.project
        value = fixture('current_behavior'); value['sources'][0]['version'] = revision
        value['sources'].append(source('context', 'user', 'context', 'Explain the limit.'))
        packets = []; reviews = []
        for variant in ['original', 'acceptance', 'authority']:
            if variant == 'acceptance': value['target']['acceptance'].append('State the final failure.')
            if variant == 'authority': value['sources'][1]['authority'] = 'user_instruction'
            self.project = self.root / ('project-' + variant)
            shutil.copytree(original_project, self.project)
            intake = self.command('intake', '--input', self.save('intake-' + variant + '.json', value))
            run = self.command('start', '--rev', revision, '--intake', intake['intake'])
            context = json.loads(Path(run['context']).read_text())
            decisions = {'impact': context['impact']['id'], 'claims': [{'path': 'guide.md', 'id': 'limit',
                         'action': 'replace', 'reason': 'Limit changed.', 'text': '호출은 2회 시도한다.', 'evidence': ['service.py']}], 'unlinked': []}
            prepared = self.command('prepare', '--run', run['run'], '--decisions', self.save('bound-decisions.json', decisions))
            packet = json.loads(Path(prepared['packet']).read_text())
            self.assertEqual(packet['version'], 2)
            self.assertEqual(packet['intake'], context['intake'])
            if packets:
                self.assertEqual(packet['plan'], packets[0]['plan'])
                self.assertNotEqual(packet['id'], packets[-1]['id'])
                self.assertIn('REVIEW_STALE', self.command('review', '--run', run['run'], '--review', self.save('stale-intake.json', reviews[0]), ok=False).stderr)
            review = {'packet': packet['id'], 'plan': packet['plan']['id'], 'verdict': 'pass',
                      'checks': {k: 'pass' for k in ['source_fidelity', 'decision_coverage', 'reader_action', 'uncertainty']}, 'findings': []}
            packets.append(packet); reviews.append(review)
            self.command('review', '--run', run['run'], '--review', self.save('bound-review.json', review))
        # Simulate a real pre-upgrade intake run whose stored ready packet omitted intake.
        from cli import identify
        legacy = dict(packet); legacy.pop('intake'); legacy['version'] = 1; legacy['id'] = identify(legacy)
        review.update(packet=legacy['id'])
        legacy_path = self.project / 'runs' / run['run'] / legacy['id'] / 'packet.json'
        legacy_path.parent.mkdir(); legacy_path.write_text(json.dumps(legacy))
        for phase in ['awaiting_review', 'ready', 'applying']:
            with closing(sqlite3.connect(self.project / 'project.sqlite3')) as db:
                saved = json.loads(db.execute('SELECT data FROM runs').fetchone()[0])
                saved.update(attempt=legacy, review=review, phase=phase)
                db.execute('UPDATE runs SET data=?', (json.dumps(saved),)); db.commit()
            if phase == 'awaiting_review':
                result = self.command('review', '--run', run['run'], '--review', self.save('legacy-review.json', review), ok=False)
            else:
                result = self.command('resume', '--run', run['run'], ok=False)
            self.assertIn('INTAKE_REVIEW_REQUIRED', result.stderr)
            self.assertEqual(self.command('status')['baseline'], self.baseline)
            self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 1회 시도한다.\n')
        # Retire remains usable for a partially applied old contract.
        Path(run['context']).write_bytes(b'{')
        reason = self.root / 'old-contract.txt'; reason.write_text('Review contract is inadequate.')
        self.assertEqual(self.command('retire', '--reason-file', reason, '--successor', self.root / 'new-contract')['phase'], 'retired')

    def test_missing_skill_dependency_blocks_before_mutation(self):
        revision = self.commit(2)
        for relative in ('skills/review/SKILL.md', 'skills/review/references/reader-tasks.md'):
            with self.subTest(dependency=relative):
                isolated = self.root / ('incomplete-' + Path(relative).stem)
                shutil.copytree(self.installed, isolated)
                # Move, rather than destroy, a required fixture dependency.
                required = isolated / relative
                required.rename(required.with_suffix('.missing'))
                original = self.cli_path
                self.cli_path = isolated / 'scripts/knowledge.py'
                try:
                    self.assertIn('DEPENDENCY_UNREACHED', self.command('doctor', ok=False).stderr)
                    self.assertIn('DEPENDENCY_UNREACHED', self.command('start', '--rev', revision, ok=False).stderr)
                    self.assertEqual(self.command('status')['runs'], [])
                finally:
                    self.cli_path = original

    def test_sqlite_json_dependency_blocks_before_project_creation(self):
        self.assertEqual(self.command('doctor')['sqlite_json'], 'verified')
        for function in ('json', 'json_set', 'json_extract'):
            for command in ('doctor', 'init'):
                with self.subTest(function=function, command=command):
                    project = self.root / f'unsupported-{function}-{command}'
                    script = '''
import runpy, sqlite3, sys
from unittest.mock import patch
cli, denied, *args = sys.argv[1:]
sys.path.insert(0, str(__import__('pathlib').Path(cli).parent))
connect = sqlite3.connect
def without_function(*args, **kwargs):
    db = connect(*args, **kwargs)
    db.set_authorizer(lambda action, first, second, *rest:
        sqlite3.SQLITE_DENY if action == sqlite3.SQLITE_FUNCTION and second == denied
        else sqlite3.SQLITE_OK)
    return db
sys.argv = [cli, *args]
with patch.object(sqlite3, 'connect', without_function):
    runpy.run_path(cli, run_name='__main__')
'''
                    args = ['--project', str(project), command]
                    if command == 'init':
                        args += ['--repo', str(self.repo), '--docs', str(self.docs),
                                 '--repository', 'fixture/service', '--baseline', self.baseline,
                                 '--path', 'service.py', '--spec', str(self.spec),
                                 '--audience', 'reader', '--purpose', 'test']
                    result = subprocess.run([sys.executable, '-c', script, str(self.cli_path), function, *args],
                                            cwd=self.root, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertEqual(result.stdout, '')
                    error = json.loads(result.stderr)
                    self.assertEqual(error['command'], command)
                    self.assertIn('DEPENDENCY: SQLite JSON functions', error['error'])
                    self.assertIn('json, json_set, json_extract', error['error'])
                    self.assertFalse(project.exists())

    def test_explicit_writer_dependency_is_checked_before_mutation(self):
        original = self.writer_path
        revision = self.commit(2)
        for writer in ('', 'relative-writer', str(self.root / 'absent-writer'), str(self.root)):
            with self.subTest(writer=writer):
                self.writer_path = writer
                result = self.command('start', '--rev', revision, ok=False)
                self.assertEqual(json.loads(result.stderr)['code'], 'DEPENDENCY_UNREACHED')
                self.assertEqual(self.command('status')['runs'], [])
                self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 1회 시도한다.\n')
        self.writer_path = original
        doctor = self.command('doctor')
        self.assertIn(str(self.writer / 'SKILL.md'), doctor['skill_files'])
        self.assertFalse((self.installed / 'skills/writing-for-humans').exists())

    def test_skill_local_references_and_package_registration(self):
        import re
        manifest = json.loads((self.installed / '.claude-plugin/plugin.json').read_text())
        names = ['bootstrap', 'update', 'review', 'query', 'wiki', 'operate']
        self.assertEqual(set(manifest['skills']), {'./skills/' + name for name in names})
        self.assertEqual({p.name for p in (self.installed / 'skills').iterdir()}, set(names))
        for name in names:
            self.assertIn('./skills/' + name, manifest['skills'])
            skill = self.installed / 'skills' / name
            for file in skill.rglob('*.md'):
                for ref in re.findall(r'\]\(([^)]+)\)', file.read_text()):
                    if '://' in ref:
                        continue
                    ref = ref.replace('${CLAUDE_PLUGIN_ROOT}', str(self.installed))
                    target = (file.parent / ref.split('#')[0]).resolve()
                    self.assertTrue(target.is_relative_to(self.installed.resolve()), (file, ref))
                    self.assertTrue(target.exists(), (file, ref))
        self.assertFalse((self.installed / 'tests').exists())
        self.assertFalse((self.installed / '.claude/skills').exists())
        self.assertTrue(self.command('doctor')['jsonschema'])


if __name__ == '__main__':
    unittest.main()
