"""Exercise only the copied plugin's public CLI from unrelated project directories."""
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest

PLUGIN = Path(__file__).resolve().parents[3] / 'plugins/toolkit'


class InstalledProjectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.package = tempfile.TemporaryDirectory(prefix='installed toolkit ')
        cls.addClassCleanup(cls.package.cleanup)
        cls.installed = Path(cls.package.name) / 'toolkit'
        shutil.copytree(PLUGIN, cls.installed, ignore=shutil.ignore_patterns('__pycache__'))
        cls.skill = cls.installed / 'skills/refresh-knowledge'
        cls.cli_path = cls.skill / 'scripts/knowledge.py'

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='knowledge project ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
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
        result = subprocess.run([sys.executable, str(self.cli_path), '--project', str(self.project),
                                 *map(str, args)], cwd=self.root, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        if ok:
            return json.loads(result.stdout)
        return result

    def ready(self, revision, count):
        run = self.command('start', '--rev', revision)
        context = json.loads(Path(run['context']).read_text())
        decisions = {'impact': context['impact']['id'], 'claims': [{'path': 'guide.md', 'id': 'limit',
                     'action': 'replace', 'reason': 'Configured attempts changed.',
                     'text': f'호출은 {count}회 시도한다.', 'evidence': ['service.py']}], 'unlinked': []}
        result = self.command('prepare', '--run', run['run'], '--decisions', self.save(f'decisions-{count}.json', decisions))
        packet = json.loads(Path(result['packet']).read_text())
        review = {'packet': packet['id'], 'plan': packet['plan']['id'], 'verdict': 'pass',
                  'checks': {k: 'pass' for k in ['source_fidelity', 'decision_coverage', 'reader_action', 'uncertainty']}, 'findings': []}
        result = self.command('review', '--run', run['run'], '--review', self.save(f'review-{count}.json', review))
        self.assertEqual(result['phase'], 'ready')
        return result, packet, review

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
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 2회 시도한다.\n')
        self.assertEqual(self.command('status')['baseline'], self.baseline)
        self.assertEqual(self.command('status', '--run', run['run'])['phase'], 'applying')
        self.assertEqual(self.command('resume', '--run', run['run'])['phase'], 'completed')
        self.assertEqual(self.command('status')['baseline'], revision)

    def test_active_run_and_database_lock_block_competing_writes(self):
        second = self.commit(2)
        run = self.command('start', '--rev', second)
        third = self.commit(3)
        self.assertIn('RUN_ACTIVE', self.command('start', '--rev', third, ok=False).stderr)
        with sqlite3.connect(self.project / 'project.sqlite3') as db:
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

    def test_init_and_unknown_schema_preserve_existing_state(self):
        self.command('init', '--repo', self.repo, '--docs', self.docs, '--repository', 'fixture/service',
                     '--baseline', self.baseline, '--path', 'service.py', '--spec', self.spec,
                     '--audience', 'reader', '--purpose', 'purpose', ok=False)
        self.assertEqual(self.command('status')['baseline'], self.baseline)
        with sqlite3.connect(self.project / 'project.sqlite3') as db:
            db.execute('PRAGMA user_version=2')
        self.assertIn('PROJECT_VERSION', self.command('status', ok=False).stderr)

    def test_skill_local_references_and_package_registration(self):
        import re
        manifest = json.loads((self.installed / '.claude-plugin/plugin.json').read_text())
        for name in ['refresh-knowledge', 'review-knowledge']:
            self.assertIn('./skills/' + name, manifest['skills'])
            skill = self.installed / 'skills' / name
            for file in skill.rglob('*.md'):
                for ref in re.findall(r'\]\(([^)]+)\)', file.read_text()):
                    if '://' in ref:
                        continue
                    target = (file.parent / ref.split('#')[0]).resolve()
                    self.assertTrue(target.is_relative_to(skill.resolve()), (file, ref))
                    self.assertTrue(target.exists(), (file, ref))
        self.assertFalse((self.installed / 'tests').exists())
        self.assertFalse((self.installed / '.claude/skills').exists())
        self.assertTrue(self.command('doctor')['jsonschema'])


if __name__ == '__main__':
    unittest.main()
