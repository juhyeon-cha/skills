#!/usr/bin/env python3
"""Project-scoped knowledge updates: one durable run ID across agent handoffs."""
import argparse
import importlib.metadata
from pathlib import Path
import shutil
import sqlite3
import sys

sys.dont_write_bytecode = True

from project_store import dump
from project_service import initialize, start, prepare, review, resume, status, terminate, retire


def doctor():
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
    skills = Path(__file__).resolve().parents[2]
    required = ['writing-for-humans/SKILL.md', 'writing-for-humans/references/backend.md',
                'writing-for-humans/references/document-shapes.md', 'review-knowledge/SKILL.md',
                'review-knowledge/references/rubric.md', 'review-knowledge/references/response.md',
                'review-knowledge/references/document-ac.md']
    missing = [p for p in required if not (skills / p).is_file()]
    if missing:
        raise ValueError('DEPENDENCY_UNREACHED: missing installed skill files: ' + ', '.join(missing))
    return {'python': sys.executable, 'python_version': sys.version.split()[0],
            'jsonschema': version, 'git': executable, 'git_version': git_version,
            'sqlite': sqlite3.sqlite_version, 'skill_files': required,
            'independent_agent': 'host capability must be checked by the orchestrator'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path)
    commands = parser.add_subparsers(dest='command', required=True)
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
    args = parser.parse_args()
    try:
        if args.command == 'doctor':
            result = doctor()
        else:
            if args.project is None:
                raise ValueError('PROJECT_REQUIRED: supply --project')
            project = args.project.resolve()
            if args.command in ('init', 'start', 'prepare', 'review', 'resume'):
                doctor()
            if args.command == 'init' and (project / 'retired.json').exists():
                raise ValueError('PROJECT_RETIRED: initialize a separate successor')
            if args.command in ('intake', 'intake-status'):
                from intake import register, inspect
                result = (register if args.command == 'intake' else inspect)(args, project)
                print(dump(result))
                return 0
            result = {'init': initialize, 'start': start, 'prepare': prepare,
                      'review': review, 'resume': resume, 'status': status,
                      'terminate': terminate, 'retire': retire}[args.command](args, project)
        print(dump(result))
        return 0
    except Exception as error:
        print(dump({'error': str(error), 'command': args.command}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
