"""Replay frozen historical data with only a copied current install and fixture history."""
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[3]
FIXTURE=ROOT/'tests/knowledge/legacy-v1'


class LegacyTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='legacy compatibility ')
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.manifest=json.loads((FIXTURE/'manifest.json').read_text())
        for name,digest in self.manifest['sha256'].items():
            self.assertEqual(hashlib.sha256((FIXTURE/name).read_bytes()).hexdigest(),digest,name)
        self.project=self.root/'project'; self.project.mkdir()
        shutil.copytree(FIXTURE/'runs',self.project/'runs')
        shutil.copytree(FIXTURE/'docs',self.root/'docs')
        self.repo=self.root/'repo'; self.repo.mkdir()
        subprocess.run(['git','-C',str(self.repo),'init','-q'],check=True)
        subprocess.run(['git','-C',str(self.repo),'fast-import','--quiet'],input=(ROOT/'tests/knowledge/foundation-observation/source-history.fi').read_bytes(),check=True)
        subprocess.run(['git','-C',str(self.repo),'reset','--hard',self.manifest['after']],check=True,capture_output=True)
        self.db=self.project/'project.sqlite3'
        frozen=json.loads((FIXTURE/'database.json').read_text())
        with sqlite3.connect(self.db) as db:
            db.executescript(frozen['sql']); db.execute('PRAGMA user_version='+str(frozen['user_version']))
            config=json.loads(db.execute('SELECT config FROM project').fetchone()[0])
            self.assertEqual({k:config[k] for k in ('repo','docs')},self.manifest['original_config'])
            config.update(repo=str(self.repo),docs=str(self.root/'docs'))
            db.execute('UPDATE project SET config=?',(json.dumps(config,ensure_ascii=False,sort_keys=True),))
        package=self.root/'toolkit'; shutil.copytree(ROOT/'plugins/toolkit',package,ignore=shutil.ignore_patterns('__pycache__'))
        self.cli=package/'skills/refresh-knowledge/scripts/knowledge.py'

    def state(self):
        with sqlite3.connect(self.db) as db:
            return {'version':db.execute('PRAGMA user_version').fetchone()[0],
                    'schema':db.execute("SELECT name,sql FROM sqlite_master WHERE type='table' ORDER BY name").fetchall(),
                    'run':json.loads(db.execute('SELECT data FROM runs').fetchone()[0]),
                    'project':db.execute('SELECT * FROM project').fetchall()}

    def files(self):
        return {str(p.relative_to(self.root)):p.read_bytes() for folder in (self.project/'runs',self.root/'docs') for p in folder.rglob('*') if p.is_file()}

    def resume(self):
        return subprocess.run([sys.executable,str(self.cli),'--project',str(self.project),'resume','--run',self.manifest['run']],cwd=self.root,capture_output=True,text=True)

    def test_real_applying_resume_and_repeat(self):
        before=self.state(); files=self.files()
        self.assertEqual(before['run']['phase'],'applying'); self.assertEqual(before['version'],1)
        self.assertEqual(json.loads(before['project'][0][2])['snapshot']['commit'],self.manifest['before'])
        p=self.resume(); self.assertEqual(p.returncode,0,p.stderr); self.assertEqual(json.loads(p.stdout)['phase'],'completed')
        after=self.state(); self.assertEqual(after['schema'],before['schema']); self.assertEqual(after['version'],1)
        self.assertEqual(json.loads(after['project'][0][2])['snapshot']['commit'],self.manifest['after'])
        for key,value in before['run'].items():
            if key not in ('phase','completion'): self.assertEqual(after['run'][key],value,key)
        self.assertEqual(self.files(),files)
        p=self.resume(); self.assertEqual(p.returncode,0,p.stderr); self.assertEqual(self.state(),after); self.assertEqual(self.files(),files)

    def test_unsupported_version_and_busy_writer(self):
        with sqlite3.connect(self.db) as db:
            db.execute('BEGIN IMMEDIATE')
            p=self.resume(); self.assertEqual(p.returncode,1); self.assertEqual(p.stdout,'')
            self.assertEqual(json.loads(p.stderr)['code'],'SQLITE_BUSY' if sys.version_info >= (3,11) else 'DATABASE_ERROR')
        with sqlite3.connect(self.db) as db: db.execute('PRAGMA user_version=999')
        raw=self.db.read_bytes(); files=self.files()
        p=self.resume(); self.assertEqual(p.returncode,1); self.assertEqual(json.loads(p.stderr)['code'],'PROJECT_VERSION')
        self.assertEqual(p.stdout,''); self.assertEqual(self.db.read_bytes(),raw); self.assertEqual(self.files(),files)


if __name__ == '__main__': unittest.main()
