"""Real HTTP and CLI on isolated repositories; model receipts here are synthetic."""
import copy
import http.client
import json
from pathlib import Path
import subprocess
import sys
import threading
import unittest
from unittest.mock import patch

from test_multi_repo import Fixture, SCRIPTS
from multi_repo import Store
from reader import make_server


class ReaderTests(unittest.TestCase):
    def serve(self, fixture):
        server = make_server(fixture.root/'state', fixture.host_path, 'reader', 'contract', 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 3)
        self.addCleanup(server.shutdown)
        return server.server_port

    def request(self, port, route='/', headers=None):
        conn = http.client.HTTPConnection('127.0.0.1', port, timeout=10)
        try:
            conn.request('GET', route, headers=headers or {})
            response = conn.getresponse()
            return response.status, dict(response.getheaders()), response.read().decode()
        finally:
            conn.close()

    def complete(self):
        f = Fixture(); f.complete()
        f.call('refresh', {'goal': 'contract'})
        f.call('publish', {'goal': 'contract', 'audience': 'reader'})
        return f

    def test_same_projection_cli_http_and_readonly_state(self):
        f = self.complete(); port = self.serve(f)
        state = f.root/'state/state.json'
        before = (state.read_bytes(), state.stat().st_mtime_ns)
        value = f.root/'read-input.json'; value.write_text('{"goal":"contract"}')
        result = subprocess.run([sys.executable, str(SCRIPTS/'multi_repo.py'), '--state', str(f.root/'state'),
            '--host', str(f.host_path), '--principal', 'reader', 'read', '--input', str(value)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        cli = json.loads(result.stdout)
        status, headers, body = self.request(port, '/api/read'); api = json.loads(body)
        self.assertEqual(status, 200)
        self.assertEqual(cli['projection_id'], api['projection_id'])
        self.assertEqual(api['completion'], 'complete')
        for route in ('/', '/repositories/producer/', '/repositories/consumer/', '/evidence/'):
            status, headers, body = self.request(port, route)
            self.assertEqual(status, 200)
            self.assertIn(api['projection_id'], body)
            self.assertEqual(headers['Cache-Control'], 'no-store')
            self.assertIn("frame-ancestors 'none'", headers['Content-Security-Policy'])
        self.assertEqual((state.read_bytes(), state.stat().st_mtime_ns), before)

    def test_six_states_and_live_reauthorization(self):
        for case in ('complete', 'partial', 'withdrawn', 'revoked', 'drift', 'check_failed'):
            with self.subTest(case=case):
                if case == 'partial':
                    f = Fixture(); f.update('producer', 'total')
                    f.call('run_checks', {'goal':'contract','checks':['producer']});f.review(['producer'])
                    f.call('refresh', {'goal':'contract'}); f.call('publish', {'goal':'contract','audience':'reader'})
                else:
                    f = self.complete()
                port = self.serve(f)
                self.request(port, '/')  # Same running server before and after changes.
                if case == 'withdrawn':
                    f.goal.update(version='v2',status='withdrawn',origin=f.origin('user','withdrawn')); f.call('set_goal',f.goal)
                elif case == 'revoked':
                    f.host['principals']['reader']['repositories']['consumer']=[]; f.persist()
                elif case == 'drift':
                    docs=f.root/('producer-docs-'+f.revisions['producer']); (docs/'contract.md').write_text('Unreviewed change')
                elif case == 'check_failed':
                    f.host['checks']['producer']['argv']=[sys.executable,'-c','raise SystemExit(1)']; f.persist()
                    f.call('run_checks', {'goal':'contract','checks':['producer']})
                status, _, raw = self.request(port, '/api/read'); self.assertEqual(status, 200)
                value=json.loads(raw)
                self.assertEqual(value['completion'], 'complete' if case == 'complete' else 'incomplete')
                self.assertEqual(value['served'], 'current' if case == 'complete' else 'unavailable_or_partial')
                page=self.request(port, '/')[2]
                self.assertIn(value['projection_id'],page)
                if case != 'complete':
                    self.assertTrue(all('documents' not in m for m in value['members']))
                if case == 'revoked':
                    self.assertNotIn('consumer', raw+page)
                    self.assertEqual(value['withheld_count'],1)
                    self.assertEqual(self.request(port,'/repositories/consumer/')[0],404)
                if case in ('withdrawn','drift','check_failed','revoked'):
                    self.assertEqual(value['index'],'stale')

    def test_single_permission_revocation_search_and_history(self):
        f=self.complete()
        f.call('predict',{'goal':'contract','origin':f.origin('user'),'affected':['consumer'],'rationale':'private'})
        port=self.serve(f)
        for rights in (['source','query'],['source','publish'],[]):
            f.host['principals']['reader']['repositories']['consumer']=rights; f.persist()
            for route in ('/api/read','/','/evidence/','/?q=consumer'):
                status, _, body=self.request(port,route)
                self.assertEqual(status,200)
                # Search text is reflected safely in its input, never as a result.
                if '?q=' not in route: self.assertNotIn('consumer',body)
                self.assertNotIn('consumer-secret',body)
                self.assertNotIn('https://consumer.invalid',body)
                self.assertNotIn('consumer uses total.',body)
            self.assertEqual(self.request(port,'/repositories/consumer/')[0],404)
        f.host['principals']['reader']['goals']=[]; f.persist()
        status, _, body=self.request(port,'/api/read')
        self.assertEqual(status,503);self.assertNotIn('consumer',body);self.assertNotIn(str(f.root),body)

    def test_transport_escape_and_no_request_authority(self):
        f=self.complete(); port=self.serve(f)
        for route in ('/?principal=operator','/?host=/private/file','/?goal=private','/?q=a&q=b'):
            self.assertEqual(self.request(port,route)[0],400)
        for route in ('/state.json','/objects/anything','/../host.json','/repositories/absent/'):
            self.assertEqual(self.request(port,route)[0],404)
        self.assertEqual(self.request(port,'/',{'Host':'evil.invalid'})[0],403)
        self.assertEqual(self.request(port,'/',{'Origin':'http://evil.invalid'})[0],403)
        raw=self.request(port,'/?q=%3Cscript%3Ealert(1)%3C/script%3E')[2]
        self.assertNotIn('<script>',raw); self.assertIn('&lt;script&gt;',raw)
        view=f.call('reading',{'goal':'contract'},'reader')
        next(m for m in view['members'] if m['repository']=='producer')['documents'][0]['text']='<img src=x onerror=alert(1)>'
        from reader import render
        html=render(view,'/repositories/producer/')
        self.assertNotIn('<img',html);self.assertIn('&lt;img',html)

    def test_change_during_read_fails_closed(self):
        f=self.complete(); store=Store(f.root/'state',f.host_path,'reader')
        original=Store.query
        def changed(instance,value):
            result=original(instance,value);result['members'][0]['current']['commit']='0'*40;return result
        with store.locked(readonly=True), patch.object(Store,'query',changed):
            with self.assertRaisesRegex(ValueError,'READ_CHANGED'):store.reading({'goal':'contract'})
        def changed_policy(instance,value):
            result=original(instance,value);f.host['principals']['reader']['repositories']['consumer']=[];f.persist();return result
        with store.locked(readonly=True), patch.object(Store,'query',changed_policy):
            with self.assertRaisesRegex(ValueError,'READ_CHANGED'):store.reading({'goal':'contract'})


if __name__ == '__main__':
    unittest.main()
