#!/usr/bin/env python3
"""Configured/shared SQLite, preservation and history transfer through the public CLI."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[2] / 'plugins/knowledge/scripts/knowledge.py'
SOURCE = 'example:source'


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()


class StorageChecks(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='knowledge-storage-')
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name).resolve()
        self.database = self.base / 'host.sqlite'
        self.config = self.configure('users')
        self.inputs = 0

    def configure(self, notebook, db=None, notes=None):
        value = dict(version=1, database=str(db or self.database), notebook=notebook,
                     artifacts=str(self.base / notebook / 'artifacts'),
                     publication=str(self.base / notebook / 'wiki'))
        if notes:
            value['notes'] = str(notes)
        file = self.base / (notebook + '.json')
        file.write_text(json.dumps(value))
        return file

    def cli(self, *args, config=None, success=True):
        result = subprocess.run([sys.executable, '-S', str(CLI), '--project', str(config or self.config),
                                 'notebook', *map(str, args)], cwd=self.base, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0 if success else 1, result.stdout + result.stderr)
        return json.loads(result.stdout if success else result.stderr)

    def init(self, config=None, attach=False, audience='user', **kwargs):
        return self.cli('init', '--source', SOURCE, '--audience', audience,
                        *(['--attach'] if attach else []), config=config, **kwargs)

    def append(self, kind, value, **kwargs):
        self.inputs += 1
        file = self.base / f'input-{self.inputs}.json'
        file.write_text(json.dumps(value))
        return self.cli(kind, '--input', file, **kwargs)

    def observation(self, day=1, body=None):
        return dict(source=SOURCE, object='object-1', revision=str(day),
                    observed_at=f'2026-09-{day:02d}T00:00:00Z', status='complete',
                    title='Evidence', body=body or f'Evidence {day}', metadata={'producer': 'fixture'})

    def document(self, evidence, audience='user', previous=None, body='Explanation'):
        return dict(key='guide', source=SOURCE, title='Guide', audience=audience, area='usage',
                    purpose='Use the product', product_version='1', author='writer', body=body,
                    evidence=[evidence], previous=previous)

    def seed(self, config=None, audience='user'):
        evidence = self.append('observe', self.observation(), config=config)['id']
        doc = self.append('document', self.document(evidence, audience), config=config)['id']
        self.append('review', dict(document=doc, reviewer='fixture-reviewer', verdict='pass',
                                   reason='Synthetic acceptance'), config=config)
        self.append('note', dict(source=SOURCE, object='object-1', author='owner',
                                body='Retain me', origin='fixture'), config=config)
        return evidence, doc

    def read(self, **kwargs):
        return self.cli('read', '--source', SOURCE, **kwargs)

    def test_inspect_reconfirmation_and_separate_audiences(self):
        self.init()
        first, document = self.seed()
        before = self.database.read_bytes()
        report = self.cli('inspect', '--source', SOURCE)
        self.assertEqual(self.database.read_bytes(), before)
        self.assertEqual(report['storage']['database'], str(self.database))
        self.assertEqual(report['storage']['notebook'], 'users')
        self.assertEqual(report['history_counts']['review'], 1)
        self.assertEqual(report['document_counts'], {'current': 1})
        second = self.append('observe', {**self.observation(), 'observed_at': '2026-09-02T00:00:00Z'})['id']
        report = self.cli('inspect', '--source', SOURCE)
        self.assertEqual(report['document_counts'], {'current': 1})
        self.assertEqual(report['reconfirmed_dependencies'], 1)
        self.assertEqual(report['history_counts']['observation'], 2)
        self.assertEqual(self.read()['documents'][0]['value']['evidence'], [first])
        self.assertNotEqual(first, second)
        self.cli('inspect', '--source', 'foreign', success=False)
        shared = self.configure('shared-developer')
        self.init(config=shared, audience='developer', attach=True)
        self.seed(config=shared, audience='developer')
        self.assertEqual(self.cli('inspect', '--source', SOURCE)['history_counts']['observation'], 2)
        self.assertEqual(self.cli('inspect', '--source', SOURCE, config=shared)['history_counts']['observation'], 1)
        separate = self.configure('developers', db=self.base / 'developer.sqlite')
        self.init(config=separate, audience='developer')
        self.assertEqual(self.cli('inspect', '--source', SOURCE, config=separate)['audience'], 'developer')
        missing = self.configure('missing', db=self.base / 'missing.sqlite')
        self.cli('inspect', '--source', SOURCE, config=missing, success=False)
        self.assertFalse((self.base / 'missing.sqlite').exists())

    def host(self, wal=False):
        with sqlite3.connect(self.database) as db:
            db.executescript('CREATE TABLE host_objects(id TEXT PRIMARY KEY, body TEXT);'
                             "INSERT INTO host_objects VALUES('one','original');"
                             'CREATE INDEX host_index ON host_objects(body);'
                             'PRAGMA user_version=73; PRAGMA application_id=9876;')
            if wal:
                db.execute('PRAGMA journal_mode=WAL')

    def host_state(self):
        with sqlite3.connect(self.database) as db:
            return (db.execute('SELECT * FROM host_objects').fetchall(),
                    db.execute("SELECT type,name,sql FROM sqlite_schema WHERE name LIKE 'host_%' ORDER BY name").fetchall(),
                    db.execute('PRAGMA user_version').fetchone(), db.execute('PRAGMA application_id').fetchone(),
                    db.execute('PRAGMA journal_mode').fetchone())

    def test_attach_preserves_host_objects_headers_and_journal(self):
        self.host(wal=True)
        before = self.host_state()
        self.init(attach=True)
        evidence, doc = self.seed()
        self.append('observe', self.observation(2))
        self.assertEqual(self.read()['documents'][0]['status'], 'stale')
        self.assertEqual(self.host_state(), before)
        with sqlite3.connect(self.database) as db:
            self.assertEqual(db.execute('SELECT document,evidence FROM knowledge_dependencies').fetchall(), [(doc, evidence)])
            self.assertEqual(db.execute('PRAGMA integrity_check').fetchone(), ('ok',))
            self.assertEqual(db.execute('PRAGMA foreign_key_check').fetchall(), [])
        self.assertFalse(self.init(attach=True)['created'])

    def test_explicit_create_attach_and_no_implicit_initialization(self):
        self.read(success=False)
        self.append('observe', self.observation(), success=False)
        self.init(attach=True, success=False)
        self.assertFalse(self.database.exists())
        self.init()
        before = self.database.read_bytes()
        self.init(success=False)
        self.assertEqual(self.database.read_bytes(), before)
        self.assertEqual(self.cli('status', '--source', SOURCE)['stage'], 'empty')
        self.assertEqual(self.cli('handoff', '--source', SOURCE)['documents'], [])
        other = self.configure('not-initialized')
        self.append('observe', self.observation(), config=other, success=False)
        self.assertEqual(self.database.read_bytes(), before)

    def test_multiple_notebooks_in_one_file_isolate_history_and_references(self):
        self.init()
        evidence, doc = self.seed()
        other = self.configure('other')
        self.init(config=other, attach=True)
        self.append('document', self.document(evidence), config=other, success=False)
        self.append('review', dict(document=doc, reviewer='reviewer', verdict='pass', reason='Test'), config=other, success=False)
        other_evidence = self.append('observe', self.observation(body='OTHER EVIDENCE'), config=other)['id']
        self.append('document', self.document(other_evidence), config=other)
        self.assertEqual(len(self.read()['history']), 3)  # reviews are separate from this public list
        self.assertEqual(len(self.read(config=other)['history']), 2)
        self.assertEqual(self.read()['observations'][0]['id'], evidence)
        self.assertEqual(self.read(config=other)['observations'][0]['id'], other_evidence)
        self.cli('get', '--source', SOURCE, '--id', evidence, config=other, success=False)
        self.init(config=other, attach=True, audience='developer', success=False)

    def test_user_and_developer_use_separate_files(self):
        self.init()
        other_db = self.base / 'developer.sqlite'
        other = self.configure('developer', db=other_db)
        self.init(config=other, audience='developer')
        self.seed()
        self.seed(config=other, audience='developer')
        self.assertEqual(self.read()['documents'][0]['value']['audience'], 'user')
        self.assertEqual(self.read(config=other)['documents'][0]['value']['audience'], 'developer')
        self.assertTrue(other_db.exists())

    def test_conflicting_schema_and_unknown_version_are_preserved(self):
        self.host()
        with sqlite3.connect(self.database) as db:
            db.execute('CREATE TABLE knowledge_records(host_data TEXT)')
            db.execute("INSERT INTO knowledge_records VALUES('preserve')")
        before = self.database.read_bytes()
        self.init(attach=True, success=False)
        self.assertEqual(self.database.read_bytes(), before)
        second = self.configure('second', db=self.base / 'second.sqlite')
        self.init(config=second)
        with sqlite3.connect(self.base / 'second.sqlite') as db:
            db.execute('UPDATE knowledge_schema SET version=999')
        before = (self.base / 'second.sqlite').read_bytes()
        self.read(config=second, success=False)
        self.init(config=second, attach=True, success=False)
        self.assertEqual((self.base / 'second.sqlite').read_bytes(), before)

    def test_failed_attach_rolls_back_all_schema_and_preserves_host(self):
        self.host()
        before = self.host_state()
        notes = self.base / 'foreign-notes'
        notes.mkdir()
        (notes / 'existing.json').write_text('{"unowned":true}')
        config = self.configure('bad-notes', notes=notes)
        self.init(config=config, attach=True, success=False)
        self.assertEqual(self.host_state(), before)
        with sqlite3.connect(self.database) as db:
            self.assertEqual(db.execute("SELECT name FROM sqlite_schema WHERE name GLOB 'knowledge_*'").fetchall(), [])
        self.init(attach=True)
        self.seed()

    def test_commit_busy_does_not_leave_an_unrecoverable_note_owner(self):
        self.host()
        notes = self.base / 'notes'
        self.config = self.configure('users', notes=notes)
        reader = sqlite3.connect(self.database)
        try:
            reader.execute('BEGIN')
            reader.execute('SELECT * FROM host_objects').fetchall()
            failure = self.init(attach=True, success=False)
            self.assertEqual(failure['code'], 'SQLITE_BUSY' if sys.version_info >= (3, 11) else 'DATABASE_ERROR')
            self.assertFalse((notes / '.notebook-scope').exists())
        finally:
            reader.rollback()
            reader.close()
        with sqlite3.connect(self.database) as db:
            self.assertEqual(db.execute("SELECT name FROM sqlite_schema WHERE name GLOB 'knowledge_*'").fetchall(), [])
        self.init(attach=True)
        self.seed()
        self.assertEqual(len(self.read()['notes']), 1)

    def test_busy_write_is_retryable_and_idempotent(self):
        self.host(wal=True)
        self.init(attach=True)
        db = sqlite3.connect(self.database)
        try:
            db.execute('BEGIN IMMEDIATE')
            failure = self.append('observe', self.observation(), success=False)
            self.assertEqual(failure['code'], 'SQLITE_BUSY' if sys.version_info >= (3, 11) else 'DATABASE_ERROR')
            self.assertEqual(self.read()['history'], [])
        finally:
            db.rollback()
            db.close()
        self.assertTrue(self.append('observe', self.observation())['created'])
        self.assertFalse(self.append('observe', self.observation())['created'])
        self.assertEqual(len(self.read()['history']), 1)

    def test_external_notes_and_artifact_location(self):
        self.config = self.configure('users', notes=self.base / 'personal')
        self.init()
        self.seed()
        files = list((self.base / 'personal').glob('*.json'))
        self.assertEqual(len(files), 1)
        before = files[0].read_bytes()
        with sqlite3.connect(self.database) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM knowledge_records WHERE kind='note'").fetchone(), (0,))
        self.append('observe', self.observation(2))
        packet = self.cli('handoff', '--source', SOURCE, '--save')
        artifact = Path(packet['artifact'])
        self.assertEqual(artifact.parent, self.base / 'users/artifacts/handoffs')
        saved = json.loads(artifact.read_text())
        self.assertEqual(saved['evidence_changes'][0]['reason'], 'new_observation')
        self.assertEqual(packet, self.cli('handoff', '--source', SOURCE, '--save'))
        self.assertEqual(files[0].read_bytes(), before)
        config = json.loads(self.config.read_text())
        config.pop('notes')
        self.config.write_text(json.dumps(config))
        self.read(success=False)

    def test_note_directories_cannot_be_shared_by_distinct_notebooks(self):
        notes = self.base / 'notes'
        self.config = self.configure('users', notes=notes)
        self.init()
        self.seed()
        before = {p.name: p.read_bytes() for p in notes.iterdir()}
        other = self.configure('other', notes=notes)
        self.init(config=other, attach=True, success=False)
        self.assertEqual({p.name: p.read_bytes() for p in notes.iterdir()}, before)
        with sqlite3.connect(self.database) as db:
            self.assertEqual(db.execute('SELECT id FROM knowledge_notebooks').fetchall(), [('users',)])

    def test_backup_restore_preserves_ids_reviews_and_stale_history(self):
        legacy = self.base / 'legacy'
        self.init(config=legacy)
        evidence, doc = self.seed(config=legacy)
        self.append('observe', self.observation(2), config=legacy)
        before = (legacy / 'observations.sqlite').read_bytes()
        bundle = self.base / 'backup.json'
        self.cli('backup', '--output', bundle, config=legacy)
        self.host()
        host_before = self.host_state()
        self.init(attach=True)
        self.assertTrue(self.cli('restore', '--input', bundle)['created'])
        self.assertFalse(self.cli('restore', '--input', bundle)['created'])
        original, restored = self.read(config=legacy), self.read()
        for field in ('documents', 'observations', 'notes', 'history'):
            self.assertEqual(original[field], restored[field])
        self.assertEqual(restored['documents'][0]['status'], 'stale')
        self.assertEqual(restored['documents'][0]['id'], doc)
        self.assertEqual(self.host_state(), host_before)
        self.assertEqual((legacy / 'observations.sqlite').read_bytes(), before)
        self.cli('backup', '--output', bundle, success=False)

    def test_restore_late_invalid_record_rolls_back_every_insert(self):
        legacy = self.base / 'legacy'
        self.init(config=legacy)
        self.seed(config=legacy)
        bundle = self.base / 'backup.json'
        self.cli('backup', '--output', bundle, config=legacy)
        value = json.loads(bundle.read_text())
        # Hash-valid but semantically invalid late review tests transaction rollback.
        bad = {'document': value['records'][1]['id'], 'reviewer': 'writer', 'verdict': 'pass', 'reason': 'self review'}
        record = {'kind': 'review', 'value': bad}
        value['records'].append({'id': digest(record), **record})
        value['digest'] = digest({k: v for k, v in value.items() if k != 'digest'})
        bundle.write_text(json.dumps(value))
        self.init()
        self.cli('restore', '--input', bundle, success=False)
        self.assertEqual(self.read()['history'], [])
        with sqlite3.connect(self.database) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM knowledge_dependencies').fetchone(), (0,))

    def test_backup_includes_external_notes_and_restore_uses_one_db_original(self):
        legacy = self.base / 'legacy'
        self.cli('init', '--source', SOURCE, '--audience', 'user', '--notes', self.base / 'legacy-notes', config=legacy)
        self.seed(config=legacy)
        bundle = self.base / 'notes-backup.json'
        self.cli('backup', '--output', bundle, config=legacy)
        self.init()
        self.cli('restore', '--input', bundle)
        self.assertEqual(self.read()['notes'], self.read(config=legacy)['notes'])
        self.assertEqual(len(list((self.base / 'legacy-notes').glob('*.json'))), 1)

    def test_invalid_config_and_symlinks_fail_before_db_creation(self):
        config = json.loads(self.config.read_text())
        for changed in ({'database': 'relative.sqlite'}, {'version': 2}, {'database': str(self.base / 'x/../bad')},
                        {'publication': str(self.base)}, {'publication': config['artifacts']}):
            self.config.write_text(json.dumps({**config, **changed}))
            self.init(success=False)
            self.assertFalse(self.database.exists())
        self.config.write_text(json.dumps(config))
        self.host()
        alias = self.base / 'alias.sqlite'
        alias.symlink_to(self.database)
        self.config.write_text(json.dumps({**config, 'database': str(alias)}))
        before = self.database.read_bytes()
        self.init(attach=True, success=False)
        self.assertEqual(self.database.read_bytes(), before)

    @unittest.skipUnless(os.environ.get('WIKI_MARKDOWN_IT_MODULE'), 'markdown-it runtime not supplied')
    def test_configured_wiki_and_status_keep_private_storage_outside_publication(self):
        self.init()
        self.seed()
        publication = self.base / 'users/wiki'
        args = ('wiki', '--source', SOURCE, '--require-current', '--node', shutil.which('node'),
                '--markdown-it', os.environ['WIKI_MARKDOWN_IT_MODULE'])
        self.cli(*args, '--output', publication / 'first')
        self.assertEqual(self.cli('status', '--source', SOURCE)['stage'], 'complete')
        self.assertTrue((publication / 'index.html').exists())
        self.assertFalse(list(publication.rglob('*.sqlite')))
        before = (publication / 'index.html').read_bytes()
        self.cli(*args, '--output', publication / 'outside', '--publish', self.base, success=False)
        self.assertEqual((publication / 'index.html').read_bytes(), before)
        self.append('observe', self.observation(2))
        self.assertEqual(self.cli('status', '--source', SOURCE)['stage'], 'writing')


if __name__ == '__main__':
    unittest.main(verbosity=2)
