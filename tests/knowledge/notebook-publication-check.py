#!/usr/bin/env python3
"""Product-neutral publication and status contract checks through the public CLI."""
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
SOURCE = 'product-api'
OBJECT = 'orders'

class PublicationChecks(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='knowledge-publication-')
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name).resolve()
        self.project = self.base / 'notebook'
        self.inputs = 0
        self.collection = self.base / 'collection.json'
        self.collection.write_text(json.dumps({'source': SOURCE, 'ok': True}))

    def run_cli(self, *args, code=0, error=False, cli=CLI):
        result = subprocess.run([sys.executable, '-S', str(cli), '--project', str(self.project),
            'notebook', *map(str, args)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return json.loads(result.stderr if error else result.stdout)

    def append(self, kind, value):
        self.inputs += 1
        file = self.base / f'input-{self.inputs}.json'
        file.write_text(json.dumps(value))
        return self.run_cli(kind, '--input', file)

    def observation(self, day=1):
        return dict(source=SOURCE, object=OBJECT, revision=f'r{day}',
            observed_at=f'2026-09-{day:02d}T12:00:00Z', status='complete', title='Order API',
            body=f'API contract revision {day}', metadata={'producer': 'api-schema-exporter', 'scope': 'documented schema only'})

    def read(self):
        return self.run_cli('read', '--source', SOURCE)

    def seed(self):
        evidence = self.append('observe', self.observation())['id']
        doc = self.append('document', dict(key='usage', source=SOURCE, title='Order lookup',
            audience='user', area='usage', purpose='Read order API', product_version='v1',
            author='test-author', body='An explanation of the API contract.', evidence=[evidence], previous=None))['id']
        self.append('review', dict(document=doc, reviewer='synthetic-reviewer', verdict='pass', reason='Synthetic test acceptance'))
        note = self.append('note', dict(source=SOURCE, object=OBJECT, author='test', body='Retain this note', origin='synthetic'))['id']
        return evidence, doc, note

    @unittest.skipUnless(os.environ.get('WIKI_MARKDOWN_IT_MODULE'), 'markdown-it runtime not supplied')
    def test_publication_rechecks_the_exact_exported_documents(self):
        self.run_cli('init', '--source', SOURCE, '--audience', 'user')
        publication = self.base / 'reviewed-wiki'
        args = ('wiki', '--source', SOURCE, '--publish', publication, '--require-current',
                '--node', shutil.which('node'), '--markdown-it', os.environ['WIKI_MARKDOWN_IT_MODULE'])
        _, doc, _ = self.seed()
        self.assertEqual(self.run_cli('status', '--source', SOURCE, '--publication', publication)['stage'], 'publish')
        self.run_cli(*args, '--output', publication / 'reviewed')
        before = (publication / 'index.html').read_bytes()
        value = self.read()['documents'][0]['value']
        revised = self.append('document', dict(value, previous=doc, body='A new unreviewed revision'))['id']
        for verdict in (None, 'revise', 'blocked'):
            if verdict:
                self.append('review', dict(document=revised, reviewer='synthetic-reviewer',
                                          verdict=verdict, reason='Synthetic negative case'))
            target = publication / str(verdict)
            self.run_cli(*args, '--output', target, code=1, error=True)
            self.assertFalse(target.exists())
            self.assertEqual((publication / 'index.html').read_bytes(), before)
        self.append('review', dict(document=revised, reviewer='synthetic-reviewer',
                                  verdict='pass', reason='Synthetic acceptance'))
        self.append('observe', self.observation(2))
        self.run_cli(*args, '--output', publication / 'stale', code=1, error=True)
        self.assertFalse((publication / 'stale').exists())
        self.assertEqual((publication / 'index.html').read_bytes(), before)

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

    @unittest.skipUnless(os.environ.get('WIKI_MARKDOWN_IT_MODULE'), 'markdown-it runtime not supplied')
    def test_desktop_status_distinguishes_collection_writing_review_and_publication(self):
        self.run_cli('init', '--source', SOURCE, '--audience', 'user')
        publication = self.base / 'desktop-wiki'
        args = ('status', '--source', SOURCE, '--publication', publication)
        self.assertEqual(self.run_cli(*args)['stage'], 'empty')
        _, doc, _ = self.seed()
        self.assertEqual(self.run_cli(*args)['stage'], 'publish')
        self.run_cli('wiki', '--source', SOURCE, '--output', publication / 'first', '--publish', publication,
                     '--node', shutil.which('node'), '--markdown-it', os.environ['WIKI_MARKDOWN_IT_MODULE'])
        current = self.run_cli(*args)
        self.assertEqual(current['stage'], 'complete')
        self.assertTrue(current['has_wiki'])
        self.assertIsNotNone(current['last_published_at'])
        self.append('observe', self.observation(2))
        status = self.run_cli(*args, '--collection', self.collection)
        self.assertEqual(status['stage'], 'writing')
        self.assertTrue(status['has_wiki'])
        value = self.read()['documents'][0]['value']
        evidence = self.read()['observations'][0]['id']
        revised = self.append('document', {**value, 'previous': doc, 'evidence': [evidence]})['id']
        self.assertEqual(self.run_cli(*args)['stage'], 'review')
        self.append('review', dict(document=revised, reviewer='independent', verdict='pass', reason='Synthetic fixture only'))
        self.assertEqual(self.run_cli(*args)['stage'], 'publish')
        failure = self.base / 'failed-collection.json'
        failure.write_text(json.dumps(dict(source=SOURCE, ok=False)))
        self.assertEqual(self.run_cli(*args, '--collection', failure)['stage'], 'collection_failed')
        self.assertTrue(self.run_cli(*args, '--collection', failure)['has_wiki'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
