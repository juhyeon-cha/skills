#!/usr/bin/env python3
"""Offline regression of notebook behavior through the public, stdlib-only CLI."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[2] / 'plugins/knowledge/scripts/knowledge.py'


class NotebookChecks(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='knowledge-observations-')
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.project = self.base / 'notebook'
        self.inputs = 0

    def run_cli(self, *args, project=None, success=True):
        # -S excludes site-packages: notebook must not require jsonschema.
        result = subprocess.run([sys.executable, '-S', str(CLI), '--project',
                                 str(project or self.project), 'notebook', *args],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0 if success else 1, result.stdout + result.stderr)
        self.assertEqual(result.stderr if success else result.stdout, '')
        value = json.loads(result.stdout if success else result.stderr)
        self.assertEqual(value['_meta']['cli_contract'], 1)
        return value

    def append(self, command, value, **kwargs):
        self.inputs += 1
        path = self.base / f'input-{self.inputs}.json'
        path.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')
        return self.run_cli(command, '--input', str(path), **kwargs)

    def observation(self, day=1, source='product:test', object='ORDER', status='complete'):
        return dict(source=source, object=object, revision=f'r{day}',
                    observed_at=f'2026-09-{day:02d}T10:00:00+00:00', status=status,
                    title='주문 API', body=f'주문 처리 근거 {day}', metadata={})

    def observe(self, **kwargs):
        return self.append('observe', self.observation(**kwargs))['id']

    def document(self, evidence, key='usage', audience='user', area='usage',
                 source='product:test', version='v1', previous=None):
        return dict(key=key, source=source, title='주문 사용 가이드', audience=audience,
                    area=area, purpose='주문 처리', product_version=version,
                    author='writer', body='주문 조회와 오류 처리 안내', evidence=evidence,
                    previous=previous)

    def review(self, doc, reviewer='independent', verdict='pass', **kwargs):
        return self.append('review', dict(document=doc, reviewer=reviewer,
                           verdict=verdict, reason='수집 근거와 문서 주장을 대조함'), **kwargs)

    def read(self, *args, source='product:test', **kwargs):
        return self.run_cli('read', '--source', source, *args, **kwargs)

    def test_handoff_identifies_changed_evidence_and_preserves_notes(self):
        self.run_cli('init', '--source', 'product:test', '--audience', 'user')
        empty = self.run_cli('handoff', '--source', 'product:test')
        self.assertEqual(empty['documents'], [])
        first = self.observe()
        unrelated = self.observe(object='CUSTOMER')
        doc = self.append('document', self.document([first]))['id']
        other = self.append('document', self.document([unrelated], key='customers'))['id']
        self.review(doc)
        self.review(other)
        self.append('note', dict(source='product:test', object='ORDER', author='owner', body='Keep this', origin='manual'))
        self.assertEqual(self.run_cli('handoff', '--source', 'product:test')['documents'], [])
        second = self.observe(day=2)
        packet = self.run_cli('handoff', '--source', 'product:test')
        self.assertEqual([d['id'] for d in packet['documents']], [doc])
        self.assertEqual(packet['evidence_changes'][0]['bound']['id'], first)
        self.assertEqual(packet['evidence_changes'][0]['latest']['id'], second)
        self.assertEqual(packet['notes'][0]['value']['body'], 'Keep this')
        self.assertIn({'id': first, 'kind': 'observation'}, packet['history'])
        self.assertEqual(self.run_cli('get', '--source', 'product:test', '--id', first)['id'], first)
        report = self.base / 'collection.json'
        report.write_text(json.dumps({'source': 'product:test', 'ok': False}))
        self.assertFalse(self.run_cli('handoff', '--source', 'product:test', '--collection', str(report))['collection_ok'])
        report.write_text(json.dumps({'source': 'foreign', 'ok': True}))
        self.run_cli('handoff', '--source', 'product:test', '--collection', str(report), success=False)

    def test_accumulation_preserves_notes_and_document_history(self):
        first = self.observe()
        usage = self.document([first])
        developer = self.document([first], key='implementation', audience='developer', area='development')
        user_id = self.append('document', usage)['id']
        dev_id = self.append('document', developer)['id']
        self.assertEqual({d['status'] for d in self.read()['documents']}, {'unreviewed'})
        self.review(user_id)
        self.review(dev_id)
        self.assertEqual({d['status'] for d in self.read()['documents']}, {'current'})
        note = dict(source='product:test', object='ORDER', author='owner',
                    body='관측 갱신 뒤에도 남아야 하는 메모', origin='manual')
        note_id = self.append('note', note)['id']
        second = self.observe(day=2)
        stale = self.read()
        self.assertEqual({d['status'] for d in stale['documents']}, {'stale'})
        self.assertEqual(stale['notes'][0]['value'], note)
        self.assertEqual(stale['observations'][0]['id'], second)
        updated = {**usage, 'previous': user_id, 'evidence': [second], 'body': '새 주문 처리 안내'}
        updated_id = self.append('document', updated)['id']
        self.review(updated_id)
        current = self.read('--audience', 'user')
        self.assertEqual([(d['id'], d['status']) for d in current['documents']], [(updated_id, 'current')])
        self.assertTrue({first, second, user_id, updated_id, dev_id, note_id} <=
                        {r['id'] for r in current['history']})
        for day, status in ((3, 'partial'), (4, 'failed'), (5, 'removed')):
            self.observe(day=day, status=status)
            pending = self.read()
            self.assertEqual({d['status'] for d in pending['documents']}, {'evidence_pending'})
            self.assertEqual(pending['notes'][0]['id'], note_id)
            self.assertEqual(pending['notes'][0]['value'], note)
        self.observe(day=6)
        self.assertEqual({d['status'] for d in self.read()['documents']}, {'stale'})

    def test_idempotence_time_order_and_conflicts(self):
        value = self.observation(day=2)
        first = self.append('observe', value)
        second = self.append('observe', value)
        self.assertTrue(first['created'])
        self.assertFalse(second['created'])
        self.assertEqual(first['id'], second['id'])
        self.observe(day=1)
        self.assertEqual(self.read()['observations'][0]['id'], first['id'])
        before = self.read()['history']
        for timestamp in ('2026-09-02T10:00:00+00:00', '2026-09-02T19:00:00+09:00'):
            self.append('observe', {**value, 'observed_at': timestamp, 'body': '충돌'}, success=False)
        self.assertEqual(self.read()['history'], before)
        doc = self.document([first['id']])
        doc_id = self.append('document', doc)['id']
        self.assertFalse(self.append('document', doc)['created'])
        self.review(doc_id)
        self.assertFalse(self.review(doc_id)['created'])
        note = dict(source='product:test', object='ORDER', author='owner', body='메모', origin='manual')
        self.append('note', note)
        self.assertFalse(self.append('note', note)['created'])

    def test_source_audience_area_version_and_query_filters(self):
        source_a = self.observe()
        source_b = self.observe(source='product:other')
        definitions = [self.document([source_a]),
                       self.document([source_a], key='developer', audience='developer', area='development'),
                       self.document([source_a], key='v2', version='v2'),
                       self.document([source_b], source='product:other')]
        for definition in definitions:
            self.append('document', definition)
        self.assertEqual(len(self.read()['documents']), 3)
        self.assertEqual(len(self.read(source='product:other')['documents']), 1)
        self.assertEqual({o['id'] for o in self.read()['observations']}, {source_a})
        selected = self.read('--audience', 'user', '--area', 'usage', '--product-version', 'v1')
        self.assertEqual([d['value']['key'] for d in selected['documents']], ['usage'])
        self.assertEqual(len(self.read('--query', '주문 오류')['documents']), 3)
        self.assertEqual(self.read('--query', '존재하지않는단어')['documents'], [])
        self.assertEqual(self.read('--product-version', 'v3')['documents'], [])
        self.assertEqual(self.read(source='unknown')['history'], [])
        self.append('document', self.document([source_b], key='cross-source'), success=False)

    def test_review_and_revision_guards(self):
        first = self.observe()
        document = self.document([first])
        doc_id = self.append('document', document)['id']
        self.review(doc_id, reviewer='writer', success=False)
        self.review('missing-document', success=False)
        self.review(doc_id, verdict='revise')
        self.assertEqual(self.read()['documents'][0]['status'], 'revise')
        self.review(doc_id, verdict='blocked')
        self.assertEqual(self.read()['documents'][0]['status'], 'blocked')
        self.observe(day=2)
        self.review(doc_id, success=False)
        self.observe(day=3, status='partial')
        self.review(doc_id, success=False)
        for changed in ({'previous': None, 'body': 'new'},
                        {'previous': doc_id, 'audience': 'developer'},
                        {'previous': doc_id, 'area': 'domain'},
                        {'previous': doc_id, 'product_version': 'v2'},
                        {'previous': doc_id, 'evidence': ['missing']}):
            self.append('document', {**document, **changed}, success=False)
        self.assertEqual(len(self.read()['documents']), 1)

    def test_missing_read_and_invalid_input_do_not_initialize(self):
        self.read(success=False)
        self.assertFalse(self.project.exists())
        self.append('note', dict(source='product:test', object='missing', author='owner',
                                 body='orphan note', origin='manual'), success=False)
        self.assertFalse(self.project.exists())
        for invalid in ({}, {**self.observation(), 'metadata': {'x': 1}},
                        {**self.observation(), 'observed_at': '2026-09-01'},
                        {**self.observation(), 'status': 'unknown'},
                        {**self.observation(), 'body': ''}):
            self.append('observe', invalid, success=False)
            self.assertFalse(self.project.exists())

    def test_tampered_record_rejects_read_and_append(self):
        self.observe()
        file = self.project / 'observations.sqlite'
        with sqlite3.connect(file) as db:
            db.execute("UPDATE records SET body='{}'")
        before = file.read_bytes()
        self.read(success=False)
        self.append('observe', self.observation(day=2), success=False)
        self.assertEqual(file.read_bytes(), before)
        with sqlite3.connect(file) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM records').fetchone()[0], 1)

    def test_hash_tampering_and_foreign_database_rejected(self):
        self.observe()
        with sqlite3.connect(self.project / 'observations.sqlite') as db:
            value = {**self.observation(), 'body': '변조'}
            db.execute('UPDATE records SET body=?', (json.dumps(value),))
        self.read(success=False)
        foreign = self.base / 'foreign'
        foreign.mkdir()
        with sqlite3.connect(foreign / 'observations.sqlite') as db:
            db.execute('CREATE TABLE existing (value TEXT)')
        before = (foreign / 'observations.sqlite').read_bytes()
        self.append('observe', self.observation(), project=foreign, success=False)
        self.assertEqual((foreign / 'observations.sqlite').read_bytes(), before)

    def test_symlink_root_and_database_rejected(self):
        self.observe()
        alias = self.base / 'alias'
        alias.symlink_to(self.project, target_is_directory=True)
        self.read(project=alias, success=False)
        self.append('observe', self.observation(day=2), project=alias, success=False)
        nested = self.base / 'nested'
        nested.mkdir()
        (nested / 'observations.sqlite').symlink_to(self.project / 'observations.sqlite')
        self.read(project=nested, success=False)
        self.append('observe', self.observation(day=2), project=nested, success=False)
        self.assertEqual(len(self.read()['history']), 1)

    def test_concurrent_writer_fails_busy_without_loss_and_can_retry(self):
        self.observe()
        connection = sqlite3.connect(self.project / 'observations.sqlite')
        try:
            connection.execute('BEGIN IMMEDIATE')
            error = self.append('observe', self.observation(day=2), success=False)
            self.assertIn(error['code'], ('SQLITE_BUSY', 'DATABASE_ERROR'))
            self.assertIn('locked', error['error'])
            self.assertEqual(len(self.read()['history']), 1)
        finally:
            connection.rollback()
            connection.close()
        self.observe(day=2)
        result = self.read()
        self.assertEqual(len(result['history']), 2)
        self.assertEqual(result['observations'][0]['value']['revision'], 'r2')

    def test_historical_get_requires_matching_source(self):
        first = self.observe()
        document = self.document([first])
        doc_id = self.append('document', document)['id']
        second = self.observe(day=2)
        self.append('document', {**document, 'previous': doc_id,
                                 'evidence': [second], 'body': '새 문서'})
        result = self.run_cli('get', '--id', first, '--source', 'product:test')
        self.assertEqual(result['value'], self.observation())
        old = self.run_cli('get', '--id', doc_id, '--source', 'product:test')
        self.assertEqual(old['value'], document)
        self.run_cli('get', '--id', first, '--source', 'product:other', success=False)
        self.run_cli('get', '--id', 'absent', '--source', 'product:test', success=False)

    def test_export_preserves_scope_and_refuses_overwrite(self):
        self.run_cli('init', '--source', 'product:test', '--audience', 'user')
        first = self.observe()
        doc = self.append('document', self.document([first]))['id']
        self.review(doc)
        self.append('observe', self.observation(source='product:other'), success=False)
        self.append('note', dict(source='product:test', object='ORDER', author='owner',
                                body='```\n<script>note</script>\n````', origin='manual'))
        output = self.base / 'wiki-inputs'
        before = self.read()
        result = self.run_cli('export', '--source', 'product:test', '--output', str(output))
        manifest = json.loads((output / 'manifest.json').read_text(encoding='utf-8'))
        self.assertEqual(result['revision'], manifest['revision'])
        self.assertEqual(result['pages'], len(manifest['pages']))
        self.assertEqual(manifest['home'], 'home')
        self.assertEqual(manifest['evidencePage'], 'evidence')
        files = {p.name: p.read_bytes() for p in output.iterdir()}
        self.assertEqual(set(files), {p['path'] for p in manifest['pages']} | {'manifest.json'})
        joined = '\n'.join(value.decode('utf-8') for value in files.values())
        self.assertNotIn('FOREIGN_SOURCE_SENTINEL', joined)
        self.assertIn('독립 검토 기록 있음', files['p-' + doc + '.md'].decode('utf-8'))
        self.assertIn('`````\n```\n<script>note</script>\n````\n`````',
                      files['notes.md'].decode('utf-8'))
        self.run_cli('export', '--source', 'product:test', '--output', str(output), success=False)
        self.assertEqual({p.name: p.read_bytes() for p in output.iterdir()}, files)
        self.assertEqual(self.read(), before)

    @unittest.skipUnless(os.environ.get('WIKI_MARKDOWN_IT_MODULE'),
                         'WIKI_MARKDOWN_IT_MODULE not supplied; actual wiki renderer not executed')
    def test_export_builds_real_wiki_with_inert_notes_and_document_visuals(self):
        self.run_cli('init', '--source', 'product:test', '--audience', 'user')
        first = self.observe()
        body = ('> [!FLOW] 순서\n>\n> 1. 관측\n> 2. 검토\n\n'
                '> [!CARDS] 독자\n>\n> - **사용자**: 제품 사용\n> - **개발자**: 제품 개발\n')
        doc = self.append('document', {**self.document([first]), 'body': body})['id']
        self.review(doc)
        hostile = '```\n<script>note</script>\n[bad](missing.md)\n````\n' + body
        self.append('note', dict(source='product:test', object='ORDER', author='owner',
                                body=hostile, origin='manual'))
        content, site = self.base / 'content', self.base / 'site'
        self.run_cli('export', '--source', 'product:test', '--output', str(content))
        scripts = CLI.parent / 'wiki'
        for script, arguments in (
                ('build.mjs', [content, site, os.environ['WIKI_MARKDOWN_IT_MODULE']]),
                ('check.mjs', [content / 'manifest.json', site])):
            result = subprocess.run(['node', str(scripts / script), *map(str, arguments)],
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        notes = (site / 'notes/index.html').read_text(encoding='utf-8')
        self.assertIn('&lt;script&gt;note&lt;/script&gt;', notes)
        self.assertNotIn('<script>note</script>', notes)
        self.assertNotIn('href="missing.md"', notes)
        self.assertNotIn('class="wiki-visual', notes)
        rendered = (site / ('p-' + doc) / 'index.html').read_text(encoding='utf-8')
        self.assertIn('wiki-flow', rendered)
        self.assertIn('wiki-cards', rendered)

    def test_scope_rejects_cross_purpose_source_and_rebinding_without_changing_records(self):
        self.run_cli('init', '--source', 'product:test', '--audience', 'user')
        self.assertFalse(self.run_cli('init', '--source', 'product:test', '--audience', 'user')['created'])
        first = self.observe()
        self.append('document', self.document([first]))
        before = (self.project / 'observations.sqlite').read_bytes()
        self.append('document', self.document([first], audience='developer'), success=False)
        self.append('observe', self.observation(source='other'), success=False)
        self.run_cli('init', '--source', 'product:test', '--audience', 'developer', success=False)
        self.read('--audience', 'developer', success=False)
        self.run_cli('get', '--source', 'other', '--id', first, success=False)
        self.assertEqual((self.project / 'observations.sqlite').read_bytes(), before)
        self.assertEqual(self.read()['audience'], 'user')

    def test_personal_notes_have_one_original_and_survive_recollection_and_export(self):
        personal = self.base / 'personal'
        self.run_cli('init', '--source', 'product:test', '--audience', 'user', '--notes', str(personal))
        self.run_cli('init', '--source', 'product:test', '--audience', 'developer', '--notes', str(personal),
                     project=self.base / 'developer', success=False)
        self.assertFalse((self.base / 'developer' / 'scope.json').exists())
        self.observe()
        note = dict(source='product:test', object='ORDER', author='owner', body='MY-PERSONAL-NOTE', origin='manual')
        identity = self.append('note', note)['id']
        self.assertFalse(self.append('note', note)['created'])
        original = personal / (identity + '.json')
        before = original.read_bytes()
        with sqlite3.connect(self.project / 'observations.sqlite') as db:
            self.assertEqual(db.execute("SELECT count(*) FROM records WHERE kind='note'").fetchone()[0], 0)
        self.observe(day=2)
        self.assertEqual(self.read()['notes'][0]['id'], identity)
        self.assertEqual(self.run_cli('get', '--source', 'product:test', '--id', identity)['value'], note)
        output = self.base / 'wiki'
        self.run_cli('export', '--source', 'product:test', '--output', str(output))
        self.assertIn('MY-PERSONAL-NOTE', (output / 'notes.md').read_text())
        self.assertEqual(original.read_bytes(), before)
        original.write_text(json.dumps({**note, 'source': 'other'}))
        self.read(success=False)

    def test_unscoped_notebook_cannot_be_relabelled_or_published(self):
        self.observe()
        self.run_cli('init', '--source', 'product:test', '--audience', 'user', success=False)
        output = self.base / 'mixed-wiki'
        self.run_cli('export', '--source', 'product:test', '--audience', 'user',
                     '--output', str(output), success=False)
        self.assertFalse(output.exists())

    def test_each_wiki_has_only_its_own_documents_notes_evidence_and_history(self):
        for audience in ('user', 'developer'):
            self.project = self.base / audience
            self.run_cli('init', '--source', 'product:test', '--audience', audience)
            observation = {**self.observation(), 'body': audience + '-EVIDENCE'}
            evidence = self.append('observe', observation)['id']
            self.append('document', {**self.document([evidence], audience=audience),
                                     'body': audience + '-DOCUMENT'})
            self.append('note', dict(source='product:test', object='ORDER', author='owner',
                                    body=audience + '-NOTE', origin='manual'))
            out = self.base / (audience + '-wiki')
            self.run_cli('export', '--source', 'product:test', '--output', str(out))
            text = '\n'.join(p.read_text() for p in out.iterdir())
            other = 'developer' if audience == 'user' else 'user'
            for kind in ('EVIDENCE', 'DOCUMENT', 'NOTE'):
                self.assertIn(audience + '-' + kind, text)
                self.assertNotIn(other + '-' + kind, text)
            self.assertFalse((out / (other + '.md')).exists())

    def test_legacy_markdown_note_is_preserved_and_repeat_import_is_idempotent(self):
        self.observe()
        legacy = self.base / 'legacy.md'
        body = '# 운영 메모\n\n수동 확인 필요.\n'
        legacy.write_text(body, encoding='utf-8')
        arguments = ('import-note', '--file', str(legacy), '--source', 'product:test',
                     '--object', 'ORDER', '--author', 'owner')
        self.assertTrue(self.run_cli(*arguments)['created'])
        self.assertFalse(self.run_cli(*arguments)['created'])
        self.observe(day=2)
        notes = self.read()['notes']
        self.assertEqual(len(notes), 1)
        self.assertEqual(notes[0]['value']['body'], body)
        self.assertTrue(notes[0]['value']['origin'].startswith('legacy-markdown:sha256:'))
        self.assertEqual(legacy.read_text(encoding='utf-8'), body)


if __name__ == '__main__':
    unittest.main(verbosity=2)
