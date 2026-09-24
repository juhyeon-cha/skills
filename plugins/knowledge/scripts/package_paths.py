"""Resolve installed resources without assuming sibling plugin cache layouts."""
import os
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
CONTRACTS = PLUGIN_ROOT / 'contracts'
REFERENCES = PLUGIN_ROOT / 'references'
REVIEW_SKILL = PLUGIN_ROOT / 'skills/review'


def writer_skill():
    value = os.environ.get('KNOWLEDGE_WRITER_SKILL')
    if not value or not Path(value).is_absolute():
        raise ValueError('DEPENDENCY_UNREACHED: KNOWLEDGE_WRITER_SKILL must name an absolute writing-for-humans skill directory')
    return Path(value).resolve()


def review_files():
    return [REVIEW_SKILL / name for name in ('SKILL.md', 'references/rubric.md', 'references/response.md',
                                           'references/document-ac.md', 'references/reader-tasks.md')]


def require_files(required):
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise ValueError('DEPENDENCY_UNREACHED: missing installed skill files: ' + ', '.join(missing))
    return required


def authoring_files():
    writer = writer_skill()
    required = [writer / name for name in ('SKILL.md', 'references/backend.md', 'references/document-shapes.md')]
    return require_files(required + review_files())
