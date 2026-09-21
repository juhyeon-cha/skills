"""Public local automation contracts. Model receipts here are explicitly synthetic."""
from datetime import datetime, timezone
import concurrent.futures
import json
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[3] / 'plugins/toolkit/skills/refresh-knowledge/scripts'
sys.path.insert(0, str(SCRIPTS))
import automation


class AutomationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='automation contract ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'; self.repo.mkdir()
        self.docs = self.root / 'docs'; self.docs.mkdir()
        self.project = self.root / 'project'
        self.state = self.root / 'automation'
        self.git('init', '-q'); self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.baseline = self.commit(1)
        (self.docs / 'guide.md').write_text('호출은 1회 시도한다.\n')
        spec = self.save('spec.json', {'documents': [{'path': 'guide.md', 'claims': [
            {'id': 'limit', 'text': '호출은 1회 시도한다.', 'evidence': ['service.py']}]}]})
        self.knowledge('init', '--repo', self.repo, '--docs', self.docs, '--repository', 'fixture/service',
                       '--baseline', self.baseline, '--path', 'service.py', '--spec', spec,
                       '--audience', '호출자', '--purpose', '시도 횟수를 판단한다')
        authority = {'reference': 'Synthetic local test grant', 'document_updates': True, 'implementation': True,
                     'checks': [[sys.executable, '-B', '-c', "assert 'ATTEMPTS = 3' in open('service.py').read()"]]}
        self.auto('init', '--project', self.project, '--authority', self.save('authority.json', authority))

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True).strip()

    def commit(self, count):
        (self.repo / 'service.py').write_text(f'ATTEMPTS = {count}\n')
        self.git('add', '.'); self.git('commit', '-qm', f'attempts {count}')
        return self.git('rev-parse', 'HEAD')

    def save(self, name, data):
        path = self.root / name
        path.write_text(json.dumps(data, ensure_ascii=False))
        return path

    def command(self, script, option, root, args, ok=True):
        proc = subprocess.run([sys.executable, str(SCRIPTS / script), option, str(root), *map(str, args)],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode == 0, ok, proc.stderr)
        return json.loads(proc.stdout if ok else proc.stderr)

    def auto(self, *args, ok=True):
        return self.command('automation.py', '--state', self.state, args, ok)

    def knowledge(self, *args, ok=True):
        return self.command('knowledge.py', '--project', self.project, args, ok)

    def event(self, revision, name='event', **extra):
        value = {'event_id': name, 'request_id': name, 'cause_id': name, 'kind': 'code', 'revision': revision, **extra}
        return self.auto('submit', '--input', self.save(name + '.json', value))

    def receipt(self, pending, response, actor=None):
        timestamp = datetime.now(timezone.utc).isoformat()
        return {'task_id': pending['id'], 'actor': actor or ('synthetic-' + pending['role']),
                'host_tool': 'synthetic-fixture', 'call_id': pending['id'], 'started_at': timestamp,
                'finished_at': timestamp, 'prompt_sha256': pending['prompt_sha256'],
                'raw_response': json.dumps(response, ensure_ascii=False), 'response': response}

    def accept(self, pending, response, actor=None, ok=True):
        return self.auto('accept', '--input', self.save('receipt-' + pending['id'] + '.json', self.receipt(pending, response, actor)), ok=ok)

    def author(self, count):
        pending = self.auto('next')['pending']
        self.assertEqual(pending['role'], 'author')
        e = self.auto('status')['executions'][pending['execution']]
        context = json.loads(Path(self.knowledge('status', '--run', e['run'])['context']).read_text())
        response = {'impact': context['impact']['id'], 'claims': [{'path': 'guide.md', 'id': 'limit',
                    'action': 'replace', 'reason': 'Pinned source changed.', 'text': f'호출은 {count}회 시도한다.',
                    'evidence': ['service.py']}], 'unlinked': []}
        self.accept(pending, response)
        return pending

    def review(self, verdict='pass'):
        pending = self.auto('next')['pending']
        self.assertEqual(pending['role'], 'reviewer')
        e = self.auto('status')['executions'][pending['execution']]
        packet = json.loads(Path(self.knowledge('status', '--run', e['run'])['packet']).read_text())
        review = {'packet': packet['id'], 'plan': packet['plan']['id'], 'verdict': verdict,
                  'checks': {k: 'pass' for k in ('source_fidelity', 'decision_coverage', 'reader_action', 'uncertainty')},
                  'findings': [] if verdict == 'pass' else ['Resolve ownership policy.']}
        self.accept(pending, review)
        return pending

    def complete(self, revision, count, name='event'):
        e = self.event(revision, name)
        self.author(count); self.review()
        self.assertEqual(self.auto('next')['phase'], 'completed')
        return e['execution']

    def test_code_duplicate_new_request_and_unchanged_effect(self):
        rev = self.commit(2)
        execution = self.complete(rev, 2)
        before = {p: p.read_bytes() for p in self.project.rglob('*') if p.is_file()}
        self.assertTrue(self.auto('submit', '--input', self.root / 'event.json')['duplicate'])
        new = self.event(rev, 'new-request')
        self.assertNotEqual(new['execution'], execution)
        self.assertEqual(self.auto('next')['phase'], 'completed')
        self.assertEqual(before, {p: p.read_bytes() for p in self.project.rglob('*') if p.is_file()})
        self.assertEqual(len([h for h in self.auto('status')['history'] if h['kind'] == 'model_result']), 2)

    def test_out_of_order_and_late_response_preserve_newer_source(self):
        second = self.commit(2)
        self.event(second)
        pending = self.auto('next')['pending']
        third = self.commit(3)
        self.event(third, 'newer')
        late = self.accept(pending, {'impact': 'old', 'claims': [], 'unlinked': []})
        self.assertEqual(late['phase'], 'late_result_preserved')
        self.author(3); self.review(); self.auto('next')
        self.assertEqual(self.event(second, 'old')['phase'], 'stale')
        self.assertEqual(self.knowledge('status')['baseline'], third)
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 3회 시도한다.\n')

    def test_lost_response_reconciles_real_completed_command(self):
        rev = self.commit(2); execution = self.event(rev)['execution']
        self.author(2); self.review()
        # Drop only the automation response to a real successful knowledge resume.
        original = automation.invoke
        dropped = False
        def lose(project, *args):
            nonlocal dropped
            evidence = original(project, *args)
            if args[0] == 'resume' and not dropped:
                dropped = True
                raise OSError('Injected response loss after actual apply')
            return evidence
        from unittest.mock import patch
        with automation.Store(self.state).locked() as store, patch.object(automation, 'invoke', lose):
            self.assertEqual(store.next()['phase'], 'failure_wait')
        self.assertEqual(self.knowledge('status')['baseline'], rev)
        artifacts = {p: p.read_bytes() for p in self.project.rglob('*') if p.is_file()}
        self.auto('resume', '--execution', execution)
        self.assertEqual(self.auto('next')['phase'], 'completed')
        self.assertEqual(artifacts, {p: p.read_bytes() for p in self.project.rglob('*') if p.is_file()})

    def test_superseded_implementer_waits_for_valid_host_result(self):
        goal = {'id': 'goal', 'version': 'v1', 'text': 'Use three attempts.', 'acceptance': ['Three attempts']}
        old = self.event(self.baseline, 'v1', kind='goal', goal=goal)['execution']
        pending = self.auto('next')['pending']
        newer = self.event(self.baseline, 'v2', kind='goal', goal=dict(goal, version='v2'))['execution']
        self.assertEqual(self.auto('next')['pending']['id'], pending['id'])
        self.auto('fail', '--input', self.save('unknown.json', {'task_id': pending['id'],
            'class': 'transport', 'evidence': 'Synthetic host outcome unknown', 'outcome': 'unknown'}))
        self.auto('resume', '--execution', old)
        self.assertEqual(self.auto('next')['pending']['id'], pending['id'])
        revision = self.commit(3)
        for key, value in [('prompt_sha256', 'wrong'), ('raw_response', '{}'),
                           ('finished_at', 'not-a-time'), ('response', {})]:
            malformed = dict(self.receipt(pending, {'revision': revision}), **{key: value})
            self.auto('accept', '--input', self.save('invalid.json', malformed), ok=False)
            self.assertEqual(self.auto('next')['pending']['id'], pending['id'])
        self.accept(pending, {'revision': 'HEAD'}, ok=False)
        self.assertEqual(self.auto('next')['pending']['id'], pending['id'])
        self.assertEqual(self.accept(pending, {'revision': revision})['phase'], 'late_result_preserved')
        state = self.auto('status')
        self.assertEqual(state['executions'][old]['phase'], 'superseded')
        self.assertEqual(state['executions'][old]['receipts'][0]['response']['revision'], revision)
        self.assertEqual(state['executions'][old]['document_status'], 'not_started')
        self.assertEqual(state['executions'][old]['implementation_status'], 'pending')
        self.assertEqual(self.knowledge('status')['baseline'], self.baseline)
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 1회 시도한다.\n')
        self.auto('tick')
        observed = self.auto('status')
        self.assertEqual(observed['poll_links']['poll:' + revision], [{'execution': old, 'cause_id': 'v1'}])
        self.assertEqual(len(observed['executions']), 2)
        successor = self.auto('next')['pending']
        self.assertEqual((successor['execution'], successor['role']), (newer, 'implementer'))

    def test_superseded_implementer_releases_after_confirmed_nonexecution(self):
        goal = {'id': 'goal', 'version': 'v1', 'text': 'Use three attempts.', 'acceptance': ['Three attempts']}
        old = self.event(self.baseline, 'v1', kind='goal', goal=goal)['execution']
        pending = self.auto('next')['pending']
        newer = self.event(self.baseline, 'v2', kind='goal', goal=dict(goal, version='v2'))['execution']
        self.assertEqual(self.auto('next')['pending']['id'], pending['id'])
        self.auto('fail', '--input', self.save('not-executed.json', {'task_id': pending['id'],
            'class': 'transport', 'evidence': 'Synthetic host confirmed dispatch did not execute',
            'outcome': 'not_executed'}))
        self.assertEqual(self.auto('next')['pending']['execution'], newer)
        self.assertEqual(self.auto('status')['executions'][old]['phase'], 'superseded')

    def test_lost_terminate_response_reconciles_public_reason_without_repetition(self):
        old = self.event(self.commit(2))['execution']
        self.auto('next')
        old_run = self.auto('status')['executions'][old]['run']
        newer = self.event(self.commit(3), 'newer')['execution']
        original = automation.invoke
        def lose(project, *args):
            evidence = original(project, *args)
            if args[0] == 'terminate':
                self.assertEqual(evidence['exit_code'], 0, evidence)
                raise OSError('Injected response loss after actual termination')
            return evidence
        from unittest.mock import patch
        with automation.Store(self.state).locked() as store, patch.object(automation, 'invoke', lose):
            with self.assertRaisesRegex(OSError, 'actual termination'):
                store.next()
        status = self.knowledge('status', '--run', old_run)
        self.assertEqual(status['phase'], 'terminated')
        self.assertEqual(self.knowledge('status')['baseline'], self.baseline)
        artifacts = {p: p.read_bytes() for p in (self.project / 'runs' / old_run).rglob('*') if p.is_file()}
        self.auto('resume', '--execution', old)
        self.assertEqual(self.auto('next')['pending']['execution'], newer)
        self.assertEqual(status['termination_reason'], 'A newer accepted input superseded this run before application.')
        history = self.auto('status')['history']
        self.assertEqual(len([h for h in history if h['kind'] == 'command_intent' and h['argv'][0] == 'terminate']), 1)
        self.assertEqual(artifacts, {p: p.read_bytes() for p in (self.project / 'runs' / old_run).rglob('*') if p.is_file()})
        self.author(3); self.review(); self.assertEqual(self.auto('next')['phase'], 'completed')

    def test_supersession_preserves_different_public_termination_reason(self):
        old = self.event(self.commit(2))['execution']
        pending = self.auto('next')['pending']
        run = self.auto('status')['executions'][old]['run']
        reason = self.root / 'operator-reason.txt'; reason.write_text('Operator investigation')
        ended = self.knowledge('terminate', '--run', run, '--reason-file', reason)
        self.assertEqual(ended['termination_reason'], 'Operator investigation')
        self.event(self.commit(3), 'newer')
        self.assertIn('TERMINATION_CONFLICT', self.auto('next', ok=False)['error'])
        self.assertEqual(self.auto('status')['pending']['id'], pending['id'])
        self.assertEqual(self.knowledge('status', '--run', run)['termination_reason'], 'Operator investigation')
        self.assertEqual(self.knowledge('status')['baseline'], self.baseline)

    def test_policy_stop_resume_and_independence(self):
        execution = self.event(self.commit(2))['execution']
        pending = self.auto('next')['pending']
        self.auto('stop')
        self.assertEqual(self.auto('next')['phase'], 'stopped')
        self.auto('resume')
        self.assertEqual(self.auto('next')['pending']['id'], pending['id'])
        self.author(2); self.review('blocked')
        question = self.auto('next')
        self.assertEqual(question['phase'], 'policy_wait')
        self.assertEqual(set(question['question']), {'reason', 'evidence', 'impact', 'options'})
        self.auto('decision', '--execution', execution, '--input', self.save('decision.json', {
            'reference': 'Synthetic decision', 'choice': 'provide_evidence_or_decision', 'answer': 'Use pinned source.'}))
        pending = self.auto('next')['pending']
        self.assertIn('INDEPENDENCE', self.accept(pending, {'packet': 'x', 'plan': 'x', 'verdict': 'pass',
            'checks': {}, 'findings': []}, actor='synthetic-author', ok=False)['error'])
        self.review(); self.assertEqual(self.auto('next')['phase'], 'completed')

    def test_model_and_transport_failures_are_bounded_and_unknown_keeps_task(self):
        execution = self.event(self.commit(2))['execution']
        for attempt in range(1, 4):
            pending = self.auto('next')['pending']
            self.assertEqual(pending['attempt'], attempt)
            result = self.auto('fail', '--input', self.save('failure.json', {'task_id': pending['id'],
                'class': 'transport', 'evidence': 'Injected dispatch outage', 'outcome': 'not_executed'}))
            self.assertEqual(result['failure']['retry'], attempt < 3)
            self.auto('resume', '--execution', execution)
        self.assertEqual(self.auto('next')['phase'], 'failure_wait')
        self.assertEqual(self.knowledge('status')['baseline'], self.baseline)

    def test_unknown_outcome_requires_same_task_reconciliation(self):
        self.event(self.commit(2)); pending = self.auto('next')['pending']
        self.auto('fail', '--input', self.save('failure.json', {'task_id': pending['id'],
                  'class': 'transport', 'evidence': 'Injected lost model response', 'outcome': 'unknown'}))
        self.assertEqual(self.auto('next')['pending']['id'], pending['id'])
        self.author(2); self.review(); self.assertEqual(self.auto('next')['phase'], 'completed')

    def test_ownership_external_edit_and_concurrent_duplicate(self):
        other = self.root / 'other-automation'
        response = self.command('automation.py', '--state', other, ('init', '--project', self.project,
                        '--authority', self.root / 'authority.json'), ok=False)
        self.assertIn('OWNERSHIP', response['error'])
        rev = self.commit(2)
        self.event(rev)
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            processes = list(pool.map(lambda _: subprocess.run([sys.executable, str(SCRIPTS / 'automation.py'),
                 '--state', str(self.state), 'submit', '--input', str(self.root / 'event.json')], capture_output=True, text=True), range(2)))
        self.assertTrue(all(p.returncode == 0 or 'BUSY' in p.stderr for p in processes))
        self.assertEqual(len(self.auto('status')['executions']), 1)
        self.author(2); self.review()
        (self.docs / 'guide.md').write_text('Outside editor bytes\n')
        self.assertEqual(self.auto('next')['phase'], 'failure_wait')
        self.assertEqual((self.docs / 'guide.md').read_text(), 'Outside editor bytes\n')
        self.assertEqual(self.knowledge('status')['baseline'], self.baseline)

    def test_real_timer_discovers_gap_and_quiet_has_no_models_or_rewrites(self):
        self.commit(2)
        proc = subprocess.run([sys.executable, str(SCRIPTS / 'automation.py'), '--state', str(self.state),
                               'watch', '--ticks', '3', '--interval', '.02'], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        ticks = [json.loads(line) for line in proc.stdout.splitlines()]
        self.assertEqual(len(ticks), 3)
        self.assertEqual(ticks[0]['notifications'][0]['kind'], 'missed_event')
        self.assertEqual(ticks[-1]['notifications'], [])
        state = self.auto('status')
        self.assertEqual(len(state['executions']), 1)
        self.assertFalse(any(h['kind'] == 'task' for h in state['history']))
        self.assertEqual((self.docs / 'guide.md').read_text(), '호출은 1회 시도한다.\n')

    def test_drift_source_loss_and_pending_goal_are_distinct(self):
        goal = {'id': 'goal', 'version': 'v1', 'text': 'Use three attempts.', 'acceptance': ['Three attempts']}
        self.event(self.baseline, 'goal', kind='goal', goal=goal)
        (self.docs / 'guide.md').write_text('Outside edit\n')
        (self.repo / 'service.py').rename(self.repo / 'lost.py')
        self.git('add', '-A'); self.git('commit', '-qm', 'source lost')
        result = self.auto('tick')
        kinds = {f['kind'] for f in result['notifications']}
        self.assertTrue({'document_drift', 'source_missing', 'pending_goal'} <= kinds)
        self.assertEqual(next(e for e in self.auto('status')['executions'].values() if e['input']['kind'] == 'goal')['input']['goal'], goal)

    def test_goal_checks_independent_review_and_feedback_reuse(self):
        goal = {'id': 'goal', 'version': 'v1', 'text': 'Use three attempts.', 'acceptance': ['Three attempts']}
        execution = self.event(self.baseline, 'goal', kind='goal', goal=goal)['execution']
        pending = self.auto('next')['pending']; self.assertEqual(pending['role'], 'implementer')
        revision = self.commit(3)
        self.accept(pending, {'revision': revision})
        pending = self.auto('next')['pending']; self.assertEqual(pending['role'], 'implementation_reviewer')
        e = self.auto('status')['executions'][execution]
        self.accept(pending, {'verdict': 'pass', 'revision': revision, 'goal_hash': e['input']['goal_hash'], 'findings': []})
        self.author(3); self.review(); self.assertEqual(self.auto('next')['phase'], 'completed')
        e = self.auto('status')['executions'][execution]
        self.assertEqual(e['implementation_status'], 'verified')
        self.assertEqual(e['document_status'], 'applied')
        self.assertEqual(e['checks'][0]['exit_code'], 0)
        self.event(revision, 'feedback-code', cause_id='goal')
        self.assertEqual(self.auto('next')['phase'], 'completed')
        self.event(revision, 'feedback-goal', kind='goal', goal=goal, cause_id='goal')
        self.assertEqual(self.auto('next')['phase'], 'completed')
        self.assertEqual(len([h for h in self.auto('status')['history'] if h['kind'] == 'model_result']), 4)

    def test_goal_versions_never_regress_and_ambiguous_intake_is_atomic(self):
        goal = {'id': 'goal', 'version': '2', 'text': 'Use three attempts.', 'acceptance': ['Three attempts']}
        newer = self.event(self.baseline, 'newer', kind='goal', goal=goal)['execution']
        older = self.event(self.baseline, 'older', kind='goal', goal=dict(goal, version='1'))['execution']
        self.assertEqual(self.auto('status')['executions'][older]['phase'], 'stale')
        self.assertEqual(self.auto('next')['pending']['execution'], newer)
        for version, content in [('2', 'Conflicting content'), ('v3', goal['text']), ('release-next', goal['text'])]:
            before = self.auto('status')
            event = {'event_id': 'ambiguous', 'request_id': 'ambiguous', 'cause_id': 'ambiguous',
                     'kind': 'goal', 'revision': self.baseline, 'goal': dict(goal, version=version, text=content)}
            self.assertIn('GOAL_VERSION', self.auto('submit', '--input', self.save('ambiguous.json', event), ok=False)['error'])
            self.assertEqual(self.auto('status'), before)
        same = self.event(self.baseline, 'same-content', kind='goal', goal=goal)['execution']
        self.assertNotEqual(same, newer)
        self.assertNotIn('superseded_by', self.auto('status')['executions'][newer])
        # Terminal goals still establish the version high-water mark.
        pending = self.auto('next')['pending']
        self.accept(pending, {'revision': self.commit(3)})
        pending = self.auto('next')['pending']
        self.accept(pending, {'verdict': 'pass', 'revision': self.git('rev-parse', 'HEAD'),
                             'goal_hash': self.auto('status')['executions'][newer]['input']['goal_hash'], 'findings': []})
        self.author(3); self.review(); self.auto('next')
        late = self.event(self.git('rev-parse', 'HEAD'), 'late-after-completion', kind='goal', goal=dict(goal, version='1'))['execution']
        self.assertEqual(self.auto('status')['executions'][late]['phase'], 'stale')
        self.assertEqual(self.auto('status')['executions'][newer]['phase'], 'completed')

    def test_poll_links_accepted_implementation_before_checks_without_duplicate_work(self):
        goal = {'id': 'goal', 'version': '1', 'text': 'Use three attempts.', 'acceptance': ['Three attempts']}
        execution = self.event(self.baseline, 'goal', cause_id='origin-cause', kind='goal', goal=goal)['execution']
        pending = self.auto('next')['pending']
        revision = self.commit(3)
        self.auto('tick')
        self.assertEqual(len(self.auto('status')['executions']), 1)
        self.accept(pending, {'revision': revision})
        self.auto('tick')
        state = self.auto('status')
        self.assertEqual(state['poll_links']['poll:' + revision], [{'execution': execution, 'cause_id': 'origin-cause'}])
        self.assertEqual(len(state['executions']), 1)
        self.assertEqual(state['executions'][execution]['implementation_status'], 'pending')
        self.assertEqual(state['executions'][execution]['document_status'], 'not_started')
        self.assertEqual(self.knowledge('status')['baseline'], self.baseline)
        reviewer = self.auto('next')['pending']
        self.assertEqual(reviewer['role'], 'implementation_reviewer')
        self.auto('tick')
        self.assertEqual(self.auto('next')['pending']['id'], reviewer['id'])
        self.accept(reviewer, {'verdict': 'pass', 'revision': revision,
                              'goal_hash': state['executions'][execution]['input']['goal_hash'], 'findings': []})
        self.author(3); self.review(); self.auto('next'); self.auto('tick')
        self.assertEqual(len(self.auto('status')['executions']), 1)
        self.assertEqual(len([h for h in self.auto('status')['history'] if h['kind'] == 'implementation_feedback']), 1)
        unrelated = self.commit(4)
        self.auto('tick')
        state = self.auto('status')
        self.assertNotIn('poll:' + unrelated, state['poll_links'])
        other = next(e for e in state['executions'].values() if e['id'] != execution)
        self.assertEqual(other['input']['cause_id'], 'poll:' + unrelated)
        self.author(4); self.review(); self.auto('next')
        self.assertEqual(self.knowledge('status')['baseline'], unrelated)

    def test_real_watch_distinguishes_external_baseline_document_source_drift(self):
        # A direct public CLI caller is an external writer outside automation ownership.
        # Its reviewed effect changes the baseline without modifying either database directly.
        revision = self.commit(2)
        run = self.knowledge('start', '--rev', revision)['run']
        context = json.loads(Path(self.knowledge('status', '--run', run)['context']).read_text())
        decisions = {'impact': context['impact']['id'], 'claims': [{'path': 'guide.md', 'id': 'limit',
            'action': 'replace', 'reason': 'External fixture source change', 'text': '호출은 2회 시도한다.',
            'evidence': ['service.py']}], 'unlinked': []}
        prepared = self.knowledge('prepare', '--run', run, '--decisions', self.save('external-decisions.json', decisions))
        packet = json.loads(Path(prepared['packet']).read_text())
        review = {'packet': packet['id'], 'plan': packet['plan']['id'], 'verdict': 'pass',
                  'checks': {k: 'pass' for k in ('source_fidelity', 'decision_coverage', 'reader_action', 'uncertainty')}, 'findings': []}
        self.knowledge('review', '--run', run, '--review', self.save('external-review.json', review))
        self.knowledge('resume', '--run', run)
        goal = {'id': 'goal', 'version': '1', 'text': 'Use three attempts.', 'acceptance': ['Three attempts']}
        execution = self.event(revision, 'goal', kind='goal', goal=goal)['execution']
        pending = self.auto('next')['pending']
        (self.docs / 'guide.md').write_text('Preserved external document bytes\n')
        (self.repo / 'service.py').rename(self.repo / 'lost.py')
        self.git('add', '-A'); self.git('commit', '-qm', 'external source loss')
        import hashlib
        def hashes():
            return {str(p.relative_to(self.root)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for root in (self.project, self.docs) for p in root.rglob('*') if p.is_file()}
        before, state = hashes(), self.auto('status')
        proc = subprocess.run([sys.executable, str(SCRIPTS / 'automation.py'), '--state', str(self.state),
                               'watch', '--ticks', '4', '--interval', '.02'], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        ticks = [json.loads(line) for line in proc.stdout.splitlines()]
        self.assertEqual(len(ticks), 4)
        self.assertTrue({'baseline_drift', 'document_drift', 'source_missing', 'pending_goal'} <=
                        {f['kind'] for f in ticks[0]['notifications']})
        self.assertTrue(all(t['notifications'] == [] and not t['changed'] for t in ticks[1:]))
        after = self.auto('status')
        self.assertEqual(hashes(), before)
        self.assertEqual(after['executions'], state['executions'])
        self.assertEqual(after['pending']['id'], pending['id'])
        self.assertEqual(after['executions'][execution]['input']['goal'], goal)
        self.assertEqual(len([h for h in after['history'] if h['kind'] in ('task', 'model_result')]),
                         len([h for h in state['history'] if h['kind'] in ('task', 'model_result')]))
        self.assertEqual(self.knowledge('status')['baseline'], revision)
        self.watch_evidence = {'before_hashes': before, 'after_hashes': hashes(),
                              'before_goal': state['executions'][execution]['input']['goal'],
                              'after_goal': after['executions'][execution]['input']['goal'],
                              'before_pending_id': state['pending']['id'], 'after_pending_id': after['pending']['id'],
                              'before_counts': {kind: sum(h['kind'] == kind for h in state['history']) for kind in ('task', 'model_result')},
                              'after_counts': {kind: sum(h['kind'] == kind for h in after['history']) for kind in ('task', 'model_result')}}

    def test_authority_config_cannot_grant_remote_or_implementation(self):
        bad = {'event_id': 'bad', 'request_id': 'bad', 'cause_id': 'bad', 'kind': 'code',
               'revision': self.baseline, 'implementation_authorized': True}
        self.assertIn('AUTHORITY', self.auto('submit', '--input', self.save('bad.json', bad), ok=False)['error'])
        with automation.Store(self.state).locked() as store:
            store.state['authority']['implementation'] = False
            store.save()
        goal = {'id': 'goal', 'version': 'v1', 'text': 'Use three attempts.', 'acceptance': ['Three attempts']}
        self.event(self.baseline, 'goal', kind='goal', goal=goal)
        self.assertEqual(self.auto('next')['phase'], 'authority_wait')
        self.assertIsNone(self.auto('status')['pending'])

    def test_authority_guard_negative_control(self):
        event = {'event_id': 'remote', 'request_id': 'remote', 'cause_id': 'remote', 'kind': 'code',
                 'revision': self.baseline, 'remote': True}
        path = self.save('remote.json', event)
        self.assertIn('AUTHORITY', self.auto('submit', '--input', path, ok=False)['error'])
        copied = self.root / 'mutated-scripts'
        shutil.copytree(SCRIPTS, copied)
        script = copied / 'automation.py'
        original = script.read_text()
        changed = original.replace("if event.get('remote') or event.get('implementation_authorized'):", 'if False:')
        self.assertNotEqual(original, changed)
        script.write_text(changed)
        proc = subprocess.run([sys.executable, str(script), '--state', str(self.state), 'submit', '--input', str(path)],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout)['phase'], 'queued')
        # The disabled input guard permits intake, never any actual remote operation.

    def test_permission_service_failures_and_malformed_model_are_not_success(self):
        execution = self.event(self.commit(2))['execution']
        pending = self.auto('next')['pending']
        self.accept(pending, {'wrong': 'shape'}, ok=False)
        self.assertEqual(self.auto('status')['pending']['id'], pending['id'])
        for category in ('permission', 'service'):
            self.auto('fail', '--input', self.save('failed-' + category + '.json', {
                'task_id': pending['id'], 'class': category, 'evidence': 'Injected ' + category + ' boundary failure',
                'outcome': 'not_executed'}))
            self.assertEqual(self.auto('next')['phase'], 'failure_wait')
            self.assertEqual(self.knowledge('status')['baseline'], self.baseline)
            self.auto('resume', '--execution', execution)
            pending = self.auto('next')['pending']
        self.assertEqual(len([h for h in self.auto('status')['history'] if h['kind'] == 'host_failure']), 2)

    def test_failed_implementation_check_never_completes_goal(self):
        goal = {'id': 'goal', 'version': 'v1', 'text': 'Use three attempts.', 'acceptance': ['Three attempts']}
        execution = self.event(self.baseline, 'goal', kind='goal', goal=goal)['execution']
        pending = self.auto('next')['pending']
        self.accept(pending, {'revision': self.commit(2)})
        result = self.auto('next')
        self.assertEqual(result['pending']['role'], 'implementer')
        self.assertEqual(result['pending']['attempt'], 2)
        state = self.auto('status')
        self.assertEqual(state['executions'][execution]['implementation_status'], 'pending')
        self.assertEqual(state['executions'][execution]['document_status'], 'not_started')
        self.assertEqual(state['pending']['id'], result['pending']['id'])
        self.assertEqual(self.knowledge('status')['baseline'], self.baseline)
        self.assertTrue(any(h['kind'] == 'check_result' and h['exit_code'] != 0 for h in state['history']))

    def test_explicit_rollback_waits_and_resumes_same_execution(self):
        self.complete(self.commit(2), 2)
        execution = self.event(self.baseline, 'rollback', rollback=True)['execution']
        self.assertEqual(self.auto('next')['phase'], 'policy_wait')
        self.auto('decision', '--execution', execution, '--input', self.save('rollback-decision.json', {
            'reference': 'Synthetic explicit rollback decision', 'choice': 'accept_revision'}))
        self.author(1); self.review(); self.assertEqual(self.auto('next')['phase'], 'completed')
        self.assertEqual(self.knowledge('status')['baseline'], self.baseline)

    def test_semantic_model_error_repairs_without_policy_approval(self):
        self.event(self.commit(2))
        pending = self.auto('next')['pending']
        self.accept(pending, {'impact': '0' * 64, 'claims': [], 'unlinked': []})
        retried = self.auto('next')
        self.assertEqual(retried['pending']['role'], 'author')
        self.assertEqual(retried['pending']['attempt'], 2)
        self.assertIn('DECISIONS', retried['pending']['prompt'])
        self.author(2); self.review(); self.assertEqual(self.auto('next')['phase'], 'completed')

    def test_verified_goal_older_than_new_frontier_is_retained_without_apply(self):
        goal = {'id': 'goal', 'version': 'v1', 'text': 'Use three attempts.', 'acceptance': ['Three attempts']}
        execution = self.event(self.baseline, 'goal', kind='goal', goal=goal)['execution']
        pending = self.auto('next')['pending']
        revision = self.commit(3)
        self.accept(pending, {'revision': revision})
        review = self.auto('next')['pending']
        e = self.auto('status')['executions'][execution]
        newer = self.commit(4)
        self.event(newer, 'newer-source')
        self.accept(review, {'verdict': 'pass', 'goal_hash': e['input']['goal_hash'], 'revision': revision, 'findings': []})
        self.assertEqual(self.auto('next')['phase'], 'stale')
        self.assertEqual(self.knowledge('status')['baseline'], self.baseline)
        self.assertEqual(self.auto('status')['executions'][execution]['implementation_status'], 'verified')
        self.author(4); self.review(); self.auto('next')
        self.assertEqual(self.knowledge('status')['baseline'], newer)


if __name__ == '__main__':
    unittest.main()
