#!/usr/bin/env python3
"""Package an independent review and finish exactly that reviewed knowledge plan."""

import argparse
import json
from pathlib import Path
import sys

from cli import Draft202012Validator, ValidationError, identify, load, read_json, validate, write_new
from update import apply_plan, verify_plan

ROOT = Path(__file__).resolve().parent


def shape(value, definition):
    schema = json.loads((ROOT / 'workflow-schema.json').read_text(encoding='utf-8'))
    Draft202012Validator({'$ref': '#/$defs/' + definition, '$defs': schema['$defs']}).validate(value)


def verify_packet(packet, repo):
    shape(packet, 'packet')
    if packet['id'] != identify(packet):
        raise ValueError('PACKET_HASH: packet changed')
    for snapshot in (packet['before'], packet['after']):
        validate(snapshot)
        if snapshot['kind'] != 'snapshot':
            raise ValueError('PACKET: source snapshots required')
    verify_plan(packet['plan'], packet['bindings'], packet['before'], packet['after'], repo)


def pack(plan, bindings, before, after, repo, audience, purpose):
    if not audience.strip() or not purpose.strip():
        raise ValueError('CONTEXT: audience and purpose required')
    packet = {'version': 1, 'kind': 'review-packet', 'plan': plan, 'bindings': bindings,
              'before': before, 'after': after, 'audience': audience, 'purpose': purpose}
    packet['id'] = identify(packet)
    verify_packet(packet, repo)
    return packet


def finish(packet, review, repo, docs_root, out):
    verify_packet(packet, repo)
    shape(review, 'review')
    if review['packet'] != packet['id'] or review['plan'] != packet['plan']['id']:
        raise ValueError('REVIEW_STALE: review belongs to another packet or plan')
    if (review['verdict'] != 'pass' or review['findings']
            or any(value != 'pass' for value in review['checks'].values())):
        raise ValueError('REVIEW_NOT_PASSED: resolve findings and review a fresh packet')
    receipt = {'version': 1, 'kind': 'completion', 'status': 'applied',
               'packet': packet['id'], 'plan': packet['plan']['id'], 'review': identify(review),
               'next_bindings': packet['plan']['next_bindings']}
    receipt['id'] = identify(receipt)
    # A known output conflict must fail before applying any document. Completion
    # is repeatable, but an existing receipt never bypasses live document checks.
    if out.is_symlink():
        raise ValueError('OUTPUT: receipt symlink is unsupported')
    existing = out.exists()
    if existing and read_json(out) != receipt:
        raise ValueError('OUTPUT: existing receipt differs')
    if not out.parent.is_dir():
        raise ValueError('OUTPUT: receipt parent must exist')
    apply_plan(packet['plan'], packet['bindings'], packet['before'], packet['after'], docs_root, repo)
    if not existing:
        write_new(out, receipt)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    packet = commands.add_parser('packet')
    packet.add_argument('--plan', type=Path, required=True)
    packet.add_argument('--bindings', type=Path, required=True)
    packet.add_argument('--before', type=Path, required=True)
    packet.add_argument('--after', type=Path, required=True)
    packet.add_argument('--audience', required=True)
    packet.add_argument('--purpose', required=True)
    done = commands.add_parser('finish')
    done.add_argument('--packet', type=Path, required=True)
    done.add_argument('--review', type=Path, required=True)
    done.add_argument('--docs-root', type=Path, required=True)
    for command in (packet, done):
        command.add_argument('--repo', type=Path, required=True)
        command.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    read = read_json
    try:
        if args.command == 'packet':
            result = pack(read(args.plan), read(args.bindings), load(args.before, 'snapshot'),
                          load(args.after, 'snapshot'), args.repo, args.audience, args.purpose)
            write_new(args.out, result)
        else:
            result = finish(read(args.packet), read(args.review), args.repo, args.docs_root, args.out)
        print(result['kind'].upper() + ': ' + result['id'])
        return 0
    except (ValidationError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        if args.command == 'finish':
            print('Documents may be partially or fully applied; inspect state and retry the same reviewed packet.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
