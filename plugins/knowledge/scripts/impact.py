#!/usr/bin/env python3
"""Bind document excerpts to pinned files and derive conservative review candidates."""

import argparse
import json
from pathlib import Path
import sys

from cli import (Draft202012Validator, ValidationError, capture, compare, identify,
                 load, sha, valid_path, write_new)

ROOT = Path(__file__).resolve().parent.parent / "contracts"


def shape(value, definition):
    schema = json.loads((ROOT / 'impact-schema.json').read_text(encoding='utf-8'))
    Draft202012Validator({'$ref': '#/$defs/' + definition, '$defs': schema['$defs']}).validate(value)


def document_bytes(root, path):
    if not valid_path(path):
        raise ValueError('DOCUMENT_PATH: expected repository-relative path')
    root = root.resolve(strict=True)
    target = root / path
    for part in Path(path).parts:
        root = root / part
        if root.is_symlink():
            raise ValueError('DOCUMENT_PATH: symlink is unsupported')
    return target.read_bytes()


def bind(spec, snapshot, docs_root):
    shape(spec, 'spec')
    files = {f['path']: f for f in snapshot['files']}
    documents = []
    seen = set()
    for doc in sorted(spec['documents'], key=lambda d: d['path']):
        if doc['path'] in seen:
            raise ValueError('DOCUMENT: duplicate path')
        seen.add(doc['path'])
        data = document_bytes(docs_root, doc['path'])
        text = data.decode('utf-8')
        claims, ids = [], set()
        for claim in sorted(doc['claims'], key=lambda c: c['id']):
            if claim['id'] in ids:
                raise ValueError('CLAIM: duplicate ID within document')
            ids.add(claim['id'])
            if not claim['text'].strip() or claim['text'] not in text:
                raise ValueError('CLAIM: excerpt absent from document')
            for path in claim['evidence']:
                if path not in files:
                    raise ValueError('EVIDENCE: absent from snapshot: ' + path)
            claims.append({**claim, 'evidence': sorted(claim['evidence'])})
        documents.append({'path': doc['path'], 'sha256': sha(data), 'claims': claims})
    record = {'version': 1, 'kind': 'bindings', 'snapshot': snapshot['id'], 'documents': documents}
    record['id'] = identify(record)
    shape(record, 'bindings')
    return record


def verify_bindings(record, before, docs_root):
    shape(record, 'bindings')
    if record['id'] != identify(record) or record['snapshot'] != before['id']:
        raise ValueError('BINDINGS: hash or baseline snapshot mismatch')
    spec = {'documents': [{'path': d['path'], 'claims': d['claims']} for d in record['documents']]}
    if bind(spec, before, docs_root) != record:
        raise ValueError('BINDINGS: document content or canonical bindings changed')


def impact(record, before, after, docs_root, repo):
    # Rebuild both pinned sources before deriving any candidates.
    from source_verification import verify_source
    for snap in (before, after):
        verify_source(repo, snap, capture)
    verify_bindings(record, before, docs_root)
    change = compare(before, after)
    candidates, linked = [], set()
    for doc in record['documents']:
        affected = []
        for claim in doc['claims']:
            reasons = []
            for i, item in enumerate(change['changes']):
                if item.get('before') in claim['evidence']:
                    reasons.append(item)
                    linked.add(i)
            if reasons:
                affected.append({'id': claim['id'], 'text': claim['text'], 'changes': reasons})
        if affected:
            candidates.append({'path': doc['path'], 'sha256': doc['sha256'], 'claims': affected})
    result = {'version': 1, 'kind': 'impact', 'bindings': record['id'],
              'before': before['id'], 'after': after['id'], 'change': change['id'],
              'candidates': candidates,
              'unlinked_changes': [c for i, c in enumerate(change['changes']) if i not in linked]}
    result['id'] = identify(result)
    shape(result, 'impact')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    binding = commands.add_parser('bind')
    binding.add_argument('spec', type=Path)
    binding.add_argument('--snapshot', type=Path, required=True)
    run = commands.add_parser('impact')
    run.add_argument('bindings', type=Path)
    run.add_argument('--before', type=Path, required=True)
    run.add_argument('--after', type=Path, required=True)
    for command in (binding, run):
        command.add_argument('--docs-root', type=Path, required=True)
        command.add_argument('--repo', type=Path, required=True)
        command.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'bind':
            snapshot = load(args.snapshot, 'snapshot')
            if capture(args.repo, snapshot['repository'], snapshot['commit'], snapshot['scope']) != snapshot:
                raise ValueError('SOURCE_MISMATCH: pinned Git tree differs')
            result = bind(json.loads(args.spec.read_text(encoding='utf-8')), snapshot, args.docs_root)
        else:
            result = impact(json.loads(args.bindings.read_text(encoding='utf-8')),
                            load(args.before, 'snapshot'), load(args.after, 'snapshot'), args.docs_root, args.repo)
        write_new(args.out, result)
        print(result['kind'].upper() + ': ' + result['id'])
        return 0
    except (ValidationError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
