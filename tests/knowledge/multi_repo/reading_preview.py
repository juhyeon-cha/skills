"""Create an isolated repeatable preview and HTTP observations. Ctrl-C stops the owned server.

Run with the prepared Python and WIKI_MARKDOWN_IT_MODULE. Pass a new --output directory;
the printed URL uses an available loopback port. No operating repositories/accounts are read.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import http.client
import json
from pathlib import Path
import threading
import time

from reading_fixture import published_fixture, ReadingFixture
from reader import make_server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--observe-only', action='store_true')
    parser.add_argument('--case', choices=['complete', 'partial', 'revoked', 'drift', 'withdrawn'], default='complete')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    if args.case == 'partial':
        fixture = ReadingFixture()
        fixture.update('producer', 'total')
        fixture.call('run_checks', {'goal': 'contract', 'checks': ['producer']})
        fixture.review(['producer'])
        fixture.call('refresh', {'goal': 'contract'})
        fixture.call('publish', {'goal': 'contract', 'audience': 'reader'})
    else:
        fixture = published_fixture()
    if args.case == 'revoked':
        fixture.host['principals']['reader']['repositories']['consumer'] = []
        fixture.persist()
    elif args.case == 'drift':
        docs = fixture.root/('producer-reading-docs-' + fixture.revisions['producer'])
        (docs/'contract.md').write_text('Unreviewed replacement')
    elif args.case == 'withdrawn':
        fixture.goal.update(version='v2', status='withdrawn', origin=fixture.origin('user','withdrawn'))
        fixture.call('set_goal', fixture.goal)
    server = make_server(fixture.root/'state', fixture.host_path, 'reader', 'contract', 0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    records = []
    try:
        routes = ['/', '/repositories/producer/', '/documents/producer/contract.md/',
                  '/documents/producer/guide.md/', '/evidence/', '/api/read']
        for index, route in enumerate(routes):
            start = time.perf_counter()
            conn = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=15)
            try:
                conn.request('GET', route)
                response = conn.getresponse()
                body = response.read()
                name = str(index) + ('.json' if route == '/api/read' else '.html')
                (args.output/name).write_bytes(body)
                records.append({'route': route, 'status': response.status,
                    'elapsed_ms': (time.perf_counter()-start)*1000, 'file': name,
                    'sha256': hashlib.sha256(body).hexdigest()})
                expected = 404 if route.startswith('/documents/') and args.case != 'complete' else 200
                if response.status != expected:
                    raise RuntimeError('Preview request failed: ' + route)
            finally:
                conn.close()
        summary = {'case': args.case, 'created_at': datetime.now(timezone.utc).isoformat(), 'fixture': str(fixture.root),
            'url': 'http://127.0.0.1:' + str(server.server_port), 'requests': records,
            'review_receipts': 'synthetic test doubles', 'browser_observed': False,
            'independent_model_observed': False, 'model_tokens': None, 'model_cost': None,
            'scope': 'Local Git/HTTP execution only; browser and independent responses are separate evidence.'}
        (args.output/'observations.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
        print(json.dumps(summary, ensure_ascii=False), flush=True)
        if not args.observe_only:
            print('Preview ready; Ctrl-C stops this server. Fixture and evidence are retained.', flush=True)
            while True:
                time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
        thread.join(3)
        server.server_close()


if __name__ == '__main__':
    main()
