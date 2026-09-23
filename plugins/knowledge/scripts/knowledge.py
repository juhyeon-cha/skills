#!/usr/bin/env python3
"""Project-scoped knowledge updates: one durable run ID across agent handoffs."""
from contextlib import closing
import importlib.metadata
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True

from cli_contract import Parser, UsageError, encode, failure, version


def runtime_environment():
    import sqlite3
    import subprocess
    if sys.version_info < (3, 10):
        raise ValueError('DEPENDENCY: Python 3.10+ required')
    version = importlib.metadata.version('jsonschema')
    if version != '4.26.0':
        raise ValueError('DEPENDENCY: install adjacent requirements.txt; jsonschema==4.26.0 required')
    executable = shutil.which('git')
    if not executable:
        raise ValueError('DEPENDENCY: Git is missing')
    git_version = subprocess.check_output([executable, '--version'], text=True).strip()
    try:
        with closing(sqlite3.connect(':memory:')) as db:
            result = db.execute("SELECT json_extract(json_set(json('{}'), '$.probe', 1), '$.probe')").fetchone()
            if result != (1,):
                raise ValueError('unexpected SQLite JSON result')
    except (sqlite3.Error, ValueError) as error:
        raise ValueError('DEPENDENCY: SQLite JSON functions json, json_set, json_extract required; '
                         'use Python with a SQLite build supporting these functions') from error
    return {'python': sys.executable, 'python_version': sys.version.split()[0],
            'jsonschema': version, 'git': executable, 'git_version': git_version,
            'sqlite': sqlite3.sqlite_version, 'sqlite_json': 'verified'}


def doctor():
    environment = runtime_environment()
    from package_paths import authoring_files
    return {**environment, 'skill_files': list(map(str, authoring_files())),
            'independent_agent': 'host capability must be checked by the orchestrator'}


def main():
    parser = Parser(description=__doc__)
    parser.add_argument("--version", action="store_true")
    parser.add_argument('--project', type=Path)
    commands = parser.add_subparsers(dest='command')
    commands.add_parser('doctor')
    init = commands.add_parser('init')
    for key in ('repo', 'docs', 'spec'):
        init.add_argument('--' + key, type=Path, required=True)
    for key in ('repository', 'baseline', 'audience', 'purpose'):
        init.add_argument('--' + key, required=True)
    init.add_argument('--path', action='append', required=True)
    start_command = commands.add_parser('start')
    start_command.add_argument('--rev', required=True)
    start_command.add_argument('--intake')
    commands.add_parser('intake').add_argument('--input', type=Path, required=True)
    commands.add_parser('intake-status').add_argument('--intake', required=True)
    status_command = commands.add_parser('status')
    status_command.add_argument('--run')
    status_command.add_argument('--deep', action='store_true', help='check each run context and current review, reporting damage')
    end = commands.add_parser('terminate')
    end.add_argument('--run', required=True)
    end.add_argument('--reason-file', type=Path, required=True)
    retirement = commands.add_parser('retire')
    retirement.add_argument('--reason-file', type=Path, required=True)
    retirement.add_argument('--successor', type=Path, required=True)
    for name, field in [('prepare', 'decisions'), ('review', 'review'), ('resume', None)]:
        command = commands.add_parser(name)
        command.add_argument('--run', required=True)
        if field:
            command.add_argument('--' + field, type=Path, required=True)
    command = None
    try:
        args = parser.parse_args()
        command = args.command
        if args.version:
            if command is not None or args.project is not None:
                raise UsageError('--version must be used alone')
            print(encode(version()))
            return 0
        if command is None:
            raise UsageError('a command is required')
        if args.command == 'doctor':
            result = doctor()
        else:
            if args.project is None:
                raise ValueError('PROJECT_REQUIRED: supply --project')
            project = args.project.resolve()
            # Import inside the boundary so absent dependencies produce the public error contract.
            from jsonschema import Draft202012Validator
            from jsonschema.exceptions import ValidationError
            from project_service import initialize, start, prepare, review, resume, status, terminate, retire
            if args.command in ('init', 'start', 'prepare'):
                doctor()
            elif args.command in ('review', 'resume'):
                runtime_environment()
            if args.command == 'init' and (project / 'retired.json').exists():
                raise ValueError('PROJECT_RETIRED: initialize a separate successor')
            if args.command in ('intake', 'intake-status'):
                from intake import register, inspect
                result = (register if args.command == 'intake' else inspect)(args, project)
                print(encode(result))
                return 0
            result = {'init': initialize, 'start': start, 'prepare': prepare,
                      'review': review, 'resume': resume, 'status': status,
                      'terminate': terminate, 'retire': retire}[args.command](args, project)
        print(encode(result))
        return 0
    except Exception as error:
        print(failure(error, command), file=sys.stderr)
        return 2 if isinstance(error, UsageError) else 1


if __name__ == '__main__':
    sys.exit(main())
