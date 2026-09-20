"""Public transport, dependency-free identity and error classification."""
import ast
import importlib.util
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


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='public contract ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / 'toolkit'
        shutil.copytree(PLUGIN, self.package, ignore=shutil.ignore_patterns('__pycache__'))
        self.scripts = self.package / 'skills/refresh-knowledge/scripts'
        self.cli = self.scripts / 'knowledge.py'

    def call(self, *args, isolated=False):
        env = dict(os.environ, PATH='') if isolated else dict(os.environ)
        return subprocess.run([sys.executable, *(['-S'] if isolated else []), str(self.cli), *map(str,args)],
                              cwd=self.root, env=env, text=True, capture_output=True)

    def error(self, result, code, rc=1):
        self.assertEqual(result.returncode, rc, result.stderr)
        self.assertEqual(result.stdout, '')
        value = json.loads(result.stderr)
        self.assertEqual(value['code'], code)
        self.assertEqual(value['_meta'], {'cli_contract': 1})
        self.assertNotIn('Traceback', result.stderr)
        return value

    def test_version_without_runtime_and_content_identity(self):
        first = self.call('--version', isolated=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        value = json.loads(first.stdout)
        self.assertEqual(value['toolkit_version'], json.loads((self.package/'.claude-plugin/plugin.json').read_text())['version'])
        other = self.root/'second'; shutil.copytree(self.package, other)
        moved = subprocess.run([sys.executable,'-S',str(other/'skills/refresh-knowledge/scripts/knowledge.py'),'--version'], capture_output=True,text=True)
        self.assertEqual(first.stdout,moved.stdout)
        (self.scripts/'__pycache__').mkdir()
        (self.scripts/'__pycache__/ignored.pyc').write_bytes(b'ignored')
        (self.scripts/'__pycache__/ignored.py').write_bytes(b'ignored')
        self.assertEqual(first.stdout,self.call('--version',isolated=True).stdout)
        with (self.scripts/'project_store.py').open('a') as f: f.write('\n# identity test\n')
        self.assertNotEqual(value['implementation_id'],json.loads(self.call('--version',isolated=True).stdout)['implementation_id'])
        changed=json.loads(self.call('--version',isolated=True).stdout)['implementation_id']
        with (self.scripts/'schema.json').open('a') as f: f.write('\n')
        self.assertNotEqual(changed,json.loads(self.call('--version',isolated=True).stdout)['implementation_id'])
        (self.package/'.claude-plugin/plugin.json').write_text('{')
        self.error(self.call('--version',isolated=True),'INPUT_ERROR')

    def test_help_usage_dependency_and_missing_project(self):
        for args in [('--help',),('status','--help')]:
            p=self.call(*args,isolated=True); self.assertEqual(p.returncode,0); self.assertEqual(p.stderr,''); self.assertIn('usage:',p.stdout)
        for args in [(),('unknown',),('resume',),('status','--bogus')]:
            self.assertIsNone(self.error(self.call(*args,isolated=True),'USAGE_ERROR',2)['command'])
        self.error(self.call('status',isolated=True),'PROJECT_REQUIRED')
        self.error(self.call('--project',self.root/'project','status',isolated=True),'DEPENDENCY_UNREACHED')
        self.error(self.call('doctor',isolated=True),'DEPENDENCY_UNREACHED')

    def test_missing_sqlite_extension(self):
        wrapper = """import builtins, runpy, sys
original = builtins.__import__
def load(name, *args, **kwargs):
    if name == '_sqlite3': raise ModuleNotFoundError('No module named _sqlite3')
    return original(name, *args, **kwargs)
builtins.__import__ = load
sys.argv = sys.argv[1:]
sys.path.insert(0, str(__import__('pathlib').Path(sys.argv[0]).parent))
runpy.run_path(sys.argv[0], run_name='__main__')
"""
        for args in [('--version',), ('--help',), ('doctor',)]:
            p = subprocess.run([sys.executable, '-c', wrapper, str(self.cli), *args], text=True, capture_output=True)
            if args == ('doctor',): self.error(p, 'DEPENDENCY_UNREACHED')
            else: self.assertEqual(p.returncode, 0, p.stderr); self.assertEqual(p.stderr, '')

    def test_partial_dependency_import(self):
        (self.scripts/'jsonschema').mkdir()
        (self.scripts/'jsonschema/__init__.py').write_text('')
        self.error(self.call('--project',self.root/'project','status'),'DEPENDENCY_UNREACHED')

    def test_error_types_and_owned_prefixes(self):
        sys.path.insert(0,str(self.scripts)); self.addCleanup(sys.path.remove,str(self.scripts))
        import cli_contract as contract
        from jsonschema.exceptions import ValidationError
        cases=[(ValueError('RUN_PHASE: user text'),'INPUT_ERROR'),
               (ValidationError('RUN_PHASE: user text'),'VALIDATION_ERROR'),
               (RuntimeError('RUN_PHASE: external'),'INTERNAL_ERROR'),
               (FileNotFoundError('x'),'NOT_FOUND'),(PermissionError('x'),'PERMISSION_DENIED'),
               (OSError('x'),'IO_ERROR'),(sqlite3.OperationalError('database is locked'),'DATABASE_ERROR')]
        for error,expected in cases: self.assertEqual(contract.error_code(error),expected)
        try:
            exec(compile("raise ValueError('RUN_PHASE: invalid')",str(self.scripts/'project_service.py'),'exec'))
        except ValueError as error: self.assertEqual(contract.error_code(error),'RUN_PHASE')
        for path in self.scripts.glob('*.py'):
            for node in ast.walk(ast.parse(path.read_text())):
                if isinstance(node,ast.Raise) and isinstance(node.exc,ast.Call) and getattr(node.exc.func,'id',None)=='ValueError' and node.exc.args:
                    value=node.exc.args[0]
                    while isinstance(value,ast.BinOp): value=value.left
                    if isinstance(value,ast.Constant) and isinstance(value.value,str):
                        prefix=value.value.partition(':')[0]
                        if ':' in value.value and prefix.isupper(): self.assertIn(prefix,contract.DOMAIN_CODES)

    def test_runtime_failure_boundary(self):
        # Replace only the copied dispatcher dependency to exercise actual CLI transport.
        for expression, code in [("raise RuntimeError('unexpected')",'INTERNAL_ERROR'),
                                 ("raise FileNotFoundError('absent')",'NOT_FOUND'),
                                 ("raise PermissionError('denied')",'PERMISSION_DENIED'),
                                 ("from jsonschema.exceptions import ValidationError; raise ValidationError('RUN_PHASE: input')",'VALIDATION_ERROR')]:
            (self.scripts/'project_service.py').write_text(expression)
            self.error(self.call('--project',self.root/'project','status'),code)


if __name__ == '__main__': unittest.main()
