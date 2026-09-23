"""Public CLI transport contract; independent of project and schema dependencies."""
import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import sys

CONTRACT = 1
DOMAIN_CODES = frozenset("""
AMBIGUOUS_EDIT APPLY_INCOMPLETE ARTIFACT_CONFLICT ARTIFACT_CORRUPT ARTIFACT_SYMLINK
BASELINE_CHANGED BINDINGS CHANGE_MISMATCH CLAIM COMPLETED_DOCUMENT_CHANGED CONTENT_HASH
CONTEXT CONTEXT_INVALID DECISIONS DEPENDENCY DEPENDENCY_UNREACHED DOCUMENT DOCUMENT_PATH
DOCUMENT_TYPE EVIDENCE FILES INCOMPARABLE INPUT INTAKE INTAKE_CHANGED INTAKE_REVIEW_REQUIRED
INTAKE_ROUTE INTAKE_VERSION KIND NO_TRACKED_CLAIMS OUTPUT PACKET PACKET_HASH PATH PLAN_HASH
PLAN_MISMATCH PROJECT_REQUIRED PROJECT_RETIRED PROJECT_SYMLINK PROJECT_VERSION REASON
RECORD_HASH REVIEW_INCONSISTENT REVIEW_INVALID REVIEW_NOT_PASSED REVIEW_STALE RUN_ACTIVE
RUN_NOT_ACTIVE RUN_NOT_FOUND RUN_PHASE RUN_TERMINATED SCOPE SOURCE_MISMATCH SOURCE_UNREACHED
STALE_DOCUMENT SUCCESSOR UNSUPPORTED_FILE
""".split())
OWNERS = frozenset(('knowledge.py', 'cli.py', 'impact.py', 'intake.py', 'project_service.py',
                    'project_store.py', 'source_verification.py', 'update.py', 'workflow.py', 'package_paths.py',
                    'observations.py', 'sap_observations.py', 'observation_wiki.py', 'sap_refresh.py'))


def encode(value):
    return json.dumps({**value, '_meta': {'cli_contract': CONTRACT}}, ensure_ascii=False, sort_keys=True)


class UsageError(Exception):
    pass


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise UsageError(message)


def error_code(error):
    if isinstance(error, UsageError):
        return 'USAGE_ERROR'
    schema_errors = sys.modules.get('jsonschema.exceptions')
    validation_error = getattr(schema_errors, 'ValidationError', ())
    if isinstance(error, validation_error):
        return 'VALIDATION_ERROR'
    if isinstance(error, (ImportError, importlib.metadata.PackageNotFoundError)):
        return 'DEPENDENCY_UNREACHED'
    sqlite = sys.modules.get('sqlite3')
    if isinstance(error, getattr(sqlite, 'Error', ())):
        # sqlite_errorcode is supplied by Python 3.11+; older hosts use the general code.
        code = getattr(error, 'sqlite_errorcode', None)
        return 'SQLITE_BUSY' if code is not None and code & 255 in (5, 6) else 'DATABASE_ERROR'
    if isinstance(error, FileNotFoundError):
        return 'NOT_FOUND'
    if isinstance(error, PermissionError):
        return 'PERMISSION_DENIED'
    if isinstance(error, OSError):
        return 'IO_ERROR'
    if isinstance(error, ValueError):
        tb = error.__traceback__
        while tb and tb.tb_next:
            tb = tb.tb_next
        origin = Path(tb.tb_frame.f_code.co_filename).resolve() if tb else None
        prefix = str(error).partition(':')[0]
        if (type(error) is ValueError and origin and origin.parent == Path(__file__).resolve().parent
                and origin.name in OWNERS and prefix in DOMAIN_CODES):
            return prefix
        return 'INPUT_ERROR'
    return 'INTERNAL_ERROR'


def failure(error, command):
    return encode({'error': str(error), 'command': command, 'code': error_code(error)})


def version():
    root = Path(__file__).resolve().parent.parent
    manifest = json.loads((root / '.claude-plugin/plugin.json').read_text())
    release = manifest['version']
    if not isinstance(release, str) or not release.strip():
        raise ValueError('invalid plugin manifest version')
    digest = hashlib.sha256()
    files = sorted(p for folder in ('scripts', 'contracts') for p in (root / folder).rglob('*')
                   if p.is_file() and '__pycache__' not in p.relative_to(root).parts
                   and (p.suffix in ('.py', '.json', '.mjs', '.js', '.css') or p.name == 'requirements.txt'))
    for path in files:
        for part in (path.relative_to(root).as_posix().encode(), path.read_bytes()):
            digest.update(len(part).to_bytes(8, 'big'))
            digest.update(part)
    # Retain the legacy transport field; new callers use plugin_name/plugin_version.
    return {'plugin_name': manifest['name'], 'plugin_version': release,
            'toolkit_version': release, 'implementation_id': digest.hexdigest()}
