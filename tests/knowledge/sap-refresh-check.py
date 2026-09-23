#!/usr/bin/env python3
"""Offline public CLI checks for bounded SAP refresh and installed notebook wiki."""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / 'plugins/knowledge/scripts/knowledge.py'
FIXTURES = ROOT / 'tests/knowledge/observations-fixtures'
SOURCE = 'source-fixture-a'
OBJECT = 'object-fixture-1'


class SapRefreshChecks(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='knowledge-refresh-')
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name).resolve()
        self.project = self.base / 'notebook'
        self.output = self.base / 'refresh-result'
        self.db = self.base / 'sap.sqlite'
        self.db.write_bytes(b'dummy SAP database; fake CLI never opens this')
        self.before = json.loads((FIXTURES / 'sap-show-id-v1.json').read_text())
        self.after = copy.deepcopy(self.before)
        self.after['observation']['observed_at'] = '2026-09-24T08:00:00.000Z'
        self.fake = self.base / 'fake-sap.py'
        self.fake.write_text('''import json, pathlib, sys
base = pathlib.Path(__file__).parent
args = sys.argv[1:]
with (base / 'calls.jsonl').open('a') as log:
    log.write(json.dumps(args) + '\\n')
state = json.loads((base / 'state.json').read_text())
if args[1] == 'collect':
    (base / 'collected').touch()
    print('sensitive diagnostic that must not enter report')
    sys.exit(state['exit'])
print(json.dumps(state['after' if (base / 'collected').exists() else 'before']))
''')
        self.plan = dict(version=1, cli=[str(Path(sys.executable).resolve()), str(self.fake)],
                         producer_version='synthetic-test', db=str(self.db), source=SOURCE,
                         tenant='synthetic', level='structure',
                         objects=[dict(id=OBJECT, type='CLAS', name='CL_EXAMPLE')])
        self.inputs = 0
        self.set_state()

    def set_state(self, exit_code=0):
        (self.base / 'state.json').write_text(json.dumps(
            dict(before=self.before, after=self.after, exit=exit_code)))

    def run_cli(self, *args, code=0, error=False, cli=CLI):
        result = subprocess.run([sys.executable, '-S', str(cli), '--project',
                                 str(self.project), 'notebook', *map(str, args)],
                                cwd=self.base, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        self.assertEqual(result.stdout if error else result.stderr, '')
        value = json.loads(result.stderr if error else result.stdout)
        self.assertEqual(value['_meta']['cli_contract'], 1)
        return value

    def append(self, kind, value):
        self.inputs += 1
        file = self.base / f'input-{self.inputs}.json'
        file.write_text(json.dumps(value))
        return self.run_cli(kind, '--input', file)

    def refresh(self, **kwargs):
        file = self.base / 'plan.json'
        file.write_text(json.dumps(self.plan))
        return self.run_cli('refresh-sap', '--plan', file, '--output', self.output, **kwargs)

    def calls(self):
        path = self.base / 'calls.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def read(self):
        return self.run_cli('read', '--source', SOURCE)

    def seed(self):
        file = self.base / 'initial.json'
        file.write_text(json.dumps(self.before))
        evidence = self.run_cli('import-sap', '--input', file,
                                '--producer-version', 'synthetic-test')['id']
        doc = self.append('document', dict(key='usage', source=SOURCE, title='Synthetic usage',
                   audience='user', area='usage', purpose='Read collection state', product_version='test',
                   author='test-author', body='Synthetic structure observation only.',
                   evidence=[evidence], previous=None))['id']
        self.append('review', dict(document=doc, reviewer='synthetic-reviewer', verdict='pass',
                                  reason='Synthetic fixture acceptance, not real semantic review'))
        note = self.append('note', dict(source=SOURCE, object=OBJECT, author='test',
                                       body='Retain this note', origin='synthetic'))['id']
        return evidence, doc, note

    def test_identity_mismatch_preflight_never_collects_or_initializes(self):
        self.plan['objects'][0]['name'] = 'WRONG_NAME'
        self.refresh(code=1, error=True)
        self.assertEqual([args[1] for args in self.calls()], ['show-id'])
        self.assertFalse(self.project.exists())
        self.assertFalse(self.output.exists())

    def test_success_imports_new_evidence_and_preserves_document_and_note(self):
        evidence, doc, note = self.seed()
        result = self.refresh()
        self.assertTrue(result['ok'])
        self.assertEqual(result['pending_documents'], 1)
        self.assertEqual([args[1] for args in self.calls()], ['show-id', 'collect', 'show-id'])
        collect = self.calls()[1]
        self.assertEqual(collect, ['graph', 'collect', '--type', 'CLAS', '--objects', 'CL_EXAMPLE',
                                  '--source', SOURCE, '--tenant', 'synthetic', '--level', 'structure',
                                  '--db', str(self.db)])
        view = self.read()
        self.assertEqual(view['documents'][0]['status'], 'stale')
        self.assertEqual(view['documents'][0]['id'], doc)
        self.assertEqual(view['notes'][0]['id'], note)
        self.assertIn(evidence, {r['id'] for r in view['history']})
        handoff = json.loads((self.output / 'handoff.json').read_text())
        self.assertEqual(handoff['documents'][0]['id'], doc)
        self.assertTrue(handoff['collection_ok'])
        self.assertFalse((self.project / 'sap-refresh.lock').exists())

    def test_exporter_upgrade_preserves_old_provenance_and_attributes_new_capture(self):
        evidence, doc, note = self.seed()
        original = self.run_cli('get', '--source', SOURCE, '--id', evidence)
        self.plan['producer_version'] = 'synthetic-upgraded-exporter'
        result = self.refresh()
        self.assertTrue(result['ok'])
        self.assertEqual(self.run_cli('get', '--source', SOURCE, '--id', evidence), original)
        view = self.read()
        self.assertEqual(view['observations'][0]['value']['metadata']['producer_version'],
                         'synthetic-upgraded-exporter')
        self.assertEqual(original['value']['metadata']['producer_version'], 'synthetic-test')
        self.assertEqual(sum(r['kind'] == 'observation' for r in view['history']), 2)
        self.assertEqual(view['documents'][0]['id'], doc)
        self.assertEqual(view['documents'][0]['status'], 'stale')
        self.assertEqual(view['notes'][0]['id'], note)

    def test_exporter_upgrade_does_not_hide_changed_raw_body_at_same_timestamp(self):
        self.seed()
        original = self.read()
        self.plan['producer_version'] = 'synthetic-upgraded-exporter'
        self.before['collection'] = [{'diagnostic': 'changed payload, unchanged observation time'}]
        self.set_state()
        self.refresh(code=1, error=True)
        self.assertEqual(self.read(), original)
        self.assertNotIn('collect', [args[1] for args in self.calls()])
        self.assertFalse((self.project / 'sap-refresh.lock').exists())

    def test_partial_nonzero_is_imported_but_public_exit_is_failure(self):
        self.seed()
        self.after = json.loads((FIXTURES / 'sap-show-id-v2.json').read_text())
        self.set_state(exit_code=7)
        result = self.refresh(code=1)
        self.assertFalse(result['ok'])
        self.assertEqual(result['attempts'][0]['exit_code'], 7)
        self.assertEqual(result['attempts'][0]['status'], 'partial')
        self.assertEqual(self.read()['documents'][0]['status'], 'evidence_pending')
        self.assertNotIn('sensitive diagnostic', (self.output / 'collection.json').read_text())
        self.assertFalse(json.loads((self.output / 'handoff.json').read_text())['collection_ok'])

    def test_old_timestamp_cannot_claim_new_collection_success(self):
        self.seed()
        before = self.read()
        self.after = copy.deepcopy(self.before)
        self.set_state()
        result = self.refresh(code=1)
        self.assertFalse(result['ok'])
        self.assertEqual(result['attempts'][0]['status'], 'collection_unverified')
        self.assertEqual(self.read(), before)
        self.assertTrue((self.output / 'collection.json').is_file())

    def test_bad_plan_does_not_call_cli_or_mutate(self):
        for mutation in ({'version': 2}, {'objects': []}, {'db': 'relative.sqlite'},
                         {'cli': ['relative-executable']}):
            with self.subTest(mutation=mutation):
                original = self.plan
                self.plan = {**original, **mutation}
                self.refresh(code=1, error=True)
                self.plan = original
                self.assertFalse(self.project.exists())
                self.assertFalse(self.output.exists())
                self.assertEqual(self.calls(), [])

    def test_concurrent_lock_refuses_without_importing_or_collecting(self):
        self.project.mkdir()
        lock = self.project / 'sap-refresh.lock'
        lock.write_text('existing runner')
        self.refresh(code=1, error=True)
        self.assertEqual(lock.read_text(), 'existing runner')
        self.assertFalse((self.project / 'observations.sqlite').exists())
        self.assertNotIn('collect', [args[1] for args in self.calls()])
        self.assertFalse(self.output.exists())

    def test_existing_output_refuses_without_importing_or_collecting(self):
        self.output.mkdir()
        sentinel = self.output / 'keep.txt'
        sentinel.write_text('existing output')
        self.refresh(code=1, error=True)
        self.assertFalse((self.project / 'observations.sqlite').exists())
        self.assertEqual(sentinel.read_text(), 'existing output')
        self.assertNotIn('collect', [args[1] for args in self.calls()])

    @unittest.skipUnless(os.environ.get('WIKI_MARKDOWN_IT_MODULE'), 'markdown-it runtime not supplied')
    def test_installed_copy_builds_wiki_outside_source_checkout(self):
        self.run_cli('init', '--source', SOURCE, '--audience', 'user')
        _, doc, _ = self.seed()
        installed = self.base / 'installed-knowledge'
        shutil.copytree(CLI.parent.parent, installed)
        output = self.base / 'published'
        result = self.run_cli('wiki', '--source', SOURCE, '--output', output,
                              '--node', shutil.which('node'), '--markdown-it',
                              os.environ['WIKI_MARKDOWN_IT_MODULE'], cli=installed / 'scripts/knowledge.py')
        self.assertTrue(result['ok'])
        self.assertEqual(Path(result['index']), output / 'site/index.html')
        self.assertTrue(Path(result['index']).is_file())
        self.assertTrue((output / 'site' / ('p-' + doc) / 'index.html').is_file())
        self.assertIn('Retain this note', (output / 'site/notes/index.html').read_text())
        self.run_cli('wiki', '--source', SOURCE, '--output', output,
                     '--node', shutil.which('node'), '--markdown-it',
                     os.environ['WIKI_MARKDOWN_IT_MODULE'], code=1, error=True)

    @unittest.skipUnless(os.environ.get('WIKI_MARKDOWN_IT_MODULE'), 'markdown-it runtime not supplied')
    def test_stable_entry_keeps_last_success_on_build_failure_and_refuses_other_scope(self):
        self.run_cli('init', '--source', SOURCE, '--audience', 'user')
        self.seed()
        publication = self.base / 'wiki'
        args = ('wiki', '--source', SOURCE, '--publish', publication,
                '--node', shutil.which('node'), '--markdown-it', os.environ['WIKI_MARKDOWN_IT_MODULE'])
        self.run_cli(*args, '--output', publication / 'first')
        index = json.loads((publication / 'first/site/search-index.json').read_text())
        self.assertTrue(all(p['url'].startswith('/first/site/') for p in index['pages']))
        html = (publication / 'first/site/index.html').read_text()
        self.assertIn('href="/first/site/style.css"', html)
        self.assertIn('src="/first/site/search.js"', html)
        before = (publication / 'index.html').read_bytes()
        self.run_cli(*args, '--output', publication / '..' / 'outside', code=1, error=True)
        self.assertFalse((self.base / 'outside').exists())
        self.assertEqual((publication / 'index.html').read_bytes(), before)
        self.assertIn(b'first/site/index.html', before)
        self.run_cli(*args, '--output', publication / 'broken', '--node', sys.executable,
                     code=1, error=True)
        self.assertEqual((publication / 'index.html').read_bytes(), before)
        self.run_cli(*args, '--output', publication / 'second')
        self.assertIn(b'second/site/index.html', (publication / 'index.html').read_bytes())
        scope = publication / 'scope.json'
        scope.write_text(json.dumps(dict(version=1, source=SOURCE, audience='developer')))
        self.run_cli(*args, '--output', publication / 'foreign', code=1, error=True)
        self.assertFalse((publication / 'foreign').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
