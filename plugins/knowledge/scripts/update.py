#!/usr/bin/env python3
"""Prepare agent decisions and apply a checked document plan in an exclusive workspace."""

import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import stat
import sys
import tempfile

from cli import Draft202012Validator, ValidationError, canonical, identify, load, sha, valid_path, write_new
from impact import bind, document_bytes, impact

ROOT = Path(__file__).resolve().parent.parent / "contracts"


def shape(value, definition):
    schema = json.loads((ROOT / 'update-schema.json').read_text(encoding='utf-8'))
    Draft202012Validator({'$ref': '#/$defs/' + definition, '$defs': schema['$defs']}).validate(value)


@contextmanager
def document_copy(documents, field):
    with tempfile.TemporaryDirectory(prefix='knowledge-plan-') as directory:
        root = Path(directory)
        for doc in documents:
            if not valid_path(doc['path']):
                raise ValueError('DOCUMENT_PATH: invalid plan path')
            target = root / doc['path']
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('xb') as stream:
                stream.write(doc[field].encode('utf-8'))
        yield root


def prepare(decisions, bindings, before, after, docs_root, repo):
    shape(decisions, 'decisions')
    queue = impact(bindings, before, after, docs_root, repo)
    if decisions['impact'] != queue['id']:
        raise ValueError('DECISIONS: impact baseline mismatch')
    expected = {(d['path'], c['id']) for d in queue['candidates'] for c in d['claims']}
    chosen = {(d['path'], d['id']): d for d in decisions['claims']}
    if len(chosen) != len(decisions['claims']) or set(chosen) != expected:
        raise ValueError('DECISIONS: every candidate requires exactly one decision')
    unlinked = [canonical(d['change']) for d in decisions['unlinked']]
    if sorted(unlinked) != sorted(canonical(c) for c in queue['unlinked_changes']):
        raise ValueError('DECISIONS: every unlinked change requires exactly one disposition')
    for decision in decisions['claims'] + decisions['unlinked']:
        if not decision['reason'].strip():
            raise ValueError('DECISIONS: nonblank reason required')
    documents, next_docs = [], []
    for doc in bindings['documents']:
        original = document_bytes(docs_root, doc['path']).decode('utf-8')
        if sha(original.encode()) != doc['sha256']:
            raise ValueError('STALE_DOCUMENT: ' + doc['path'])
        edits, claims = [], []
        for claim in doc['claims']:
            decision = chosen.get((doc['path'], claim['id']))
            if not decision:
                claims.append(claim)
                continue
            action, text, evidence = decision['action'], decision['text'], decision['evidence']
            if action == 'remove':
                if text or evidence:
                    raise ValueError('DECISIONS: remove requires empty text and evidence')
            else:
                if not text.strip() or not evidence:
                    raise ValueError('DECISIONS: surviving claims require text and evidence')
                if (action == 'keep') != (text == claim['text']):
                    raise ValueError('DECISIONS: keep preserves text; replace changes it')
                claims.append({'id': claim['id'], 'text': text, 'evidence': sorted(evidence)})
            if action != 'keep':
                old = claim['text']
                start = original.find(old)
                if start < 0 or original.find(old, start + 1) >= 0:
                    raise ValueError('AMBIGUOUS_EDIT: excerpt must occur exactly once')
                edits.append((start, start + len(old), text))
        edits.sort()
        if any(left[1] > right[0] for left, right in zip(edits, edits[1:])):
            raise ValueError('AMBIGUOUS_EDIT: overlapping claim excerpts')
        revised = original
        for start, end, text in reversed(edits):
            revised = revised[:start] + text + revised[end:]
        documents.append({'path': doc['path'], 'before_text': original, 'after_text': revised,
                          'before_sha256': sha(original.encode()), 'after_sha256': sha(revised.encode())})
        if claims:
            next_docs.append({'path': doc['path'], 'claims': claims})
    # Validate all retained excerpts and evidence against the next snapshot, including
    # unaffected claims that an overlapping edit might accidentally damage.
    with document_copy(documents, 'after_text') as revised_root:
        next_bindings = bind({'documents': next_docs}, after, revised_root) if next_docs else None
    normalized = {'impact': decisions['impact'],
                  'claims': sorted([{**d, 'evidence': sorted(d['evidence'])} for d in decisions['claims']],
                                   key=lambda d: (d['path'], d['id'])),
                  'unlinked': sorted(decisions['unlinked'], key=lambda d: canonical(d['change']))}
    plan = {'version': 1, 'kind': 'update-plan', 'bindings': bindings['id'],
            'before': before['id'], 'after': after['id'], 'decisions': normalized,
            'documents': documents, 'next_bindings': next_bindings}
    plan['id'] = identify(plan)
    shape(plan, 'plan')
    return plan


def verify_plan(plan, bindings, before, after, repo):
    shape(plan, 'plan')
    if plan['id'] != identify(plan):
        raise ValueError('PLAN_HASH: plan changed')
    with document_copy(plan['documents'], 'before_text') as baseline:
        actual = prepare(plan['decisions'], bindings, before, after, baseline, repo)
    if actual != plan:
        raise ValueError('PLAN_MISMATCH: recomputed plan differs')


def current_bytes(root, doc):
    info = (root / doc['path']).lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise ValueError('DOCUMENT_TYPE: regular file with one link required')
    data = document_bytes(root, doc['path'])
    if data not in (doc['before_text'].encode(), doc['after_text'].encode()):
        raise ValueError('STALE_DOCUMENT: ' + doc['path'])
    return data, stat.S_IMODE(info.st_mode)


def replace_document(root, doc, mode):
    target = root / doc['path']
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix='.knowledge-update-', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(doc['after_text'].encode())
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        # Detect intervening edits before replacement. Caller must provide exclusive
        # access: an arbitrary editor can still race this check and os.replace.
        current_bytes(root, doc)
        os.replace(temporary, target)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def apply_plan(plan, bindings, before, after, docs_root, repo):
    verify_plan(plan, bindings, before, after, repo)
    docs_root = docs_root.resolve(strict=True)
    # Preflight the whole set; a known conflict changes nothing. A later I/O failure
    # may leave a prefix applied. Exact target bytes are accepted on retry.
    for doc in plan['documents']:
        current_bytes(docs_root, doc)
    for doc in plan['documents']:
        current, mode = current_bytes(docs_root, doc)
        if current != doc['after_text'].encode():
            replace_document(docs_root, doc, mode)
    for doc in plan['documents']:
        if document_bytes(docs_root, doc['path']) != doc['after_text'].encode():
            raise ValueError('APPLY_INCOMPLETE: ' + doc['path'])
    return {'status': 'applied', 'plan': plan['id'],
            'next_bindings': plan['next_bindings']['id'] if plan['next_bindings'] else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prep = commands.add_parser('prepare')
    prep.add_argument('decisions', type=Path)
    prep.add_argument('--out', type=Path, required=True)
    apply = commands.add_parser('apply')
    apply.add_argument('plan', type=Path)
    for command in (prep, apply):
        command.add_argument('--bindings', type=Path, required=True)
        command.add_argument('--before', type=Path, required=True)
        command.add_argument('--after', type=Path, required=True)
        command.add_argument('--repo', type=Path, required=True)
        command.add_argument('--docs-root', type=Path, required=True)
    args = parser.parse_args()
    try:
        bindings = json.loads(args.bindings.read_text(encoding='utf-8'))
        before, after = load(args.before, 'snapshot'), load(args.after, 'snapshot')
        if args.command == 'prepare':
            result = prepare(json.loads(args.decisions.read_text(encoding='utf-8')), bindings,
                             before, after, args.docs_root, args.repo)
            write_new(args.out, result)
            print('PREPARED: ' + result['id'])
        else:
            result = apply_plan(json.loads(args.plan.read_text(encoding='utf-8')), bindings,
                                before, after, args.docs_root, args.repo)
            print(json.dumps(result, sort_keys=True))
        return 0
    except (ValidationError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        if args.command == 'apply':
            print('Apply may be partial. Inspect documents; retry the same plan after resolving the cause.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
