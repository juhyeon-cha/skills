"""Validate routing boundaries without treating declared authority as authenticated."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'plugins/toolkit/skills/refresh-knowledge/scripts'))
import intake
from cli import sha


def source(identity, kind, authority, text, version='v1'):
    return dict(id=identity, kind=kind, authority=authority, text=text, version=version,
                locator='fixture/' + identity, sha256=sha(text.encode()))


def fixture(intent='behavior_change'):
    value = {'version': 1, 'origin': 'user', 'intent': intent,
             'sources': [source('request', 'user', 'user_instruction', 'Export empty lists as CSV headers.')],
             'current': {'code': None, 'description': 'No implementation exists.'},
             'target': {'sources': ['request'], 'description': 'CSV export', 'acceptance': ['Empty list yields headers only.'], 'status': 'confirmed'},
             'differences': [{'kind': 'behavior', 'description': 'Export is unimplemented.', 'sources': ['request']}],
             'rationale': 'Explicit instruction; implementation is stage 3.'}
    if intent == 'current_behavior':
        value.update(origin='code', sources=[source('code','code','observed_implementation','ATTEMPTS=3')])
        value['current']['code']='code';value['target']['sources']=['code'];value['differences'][0].update(kind='documentation',sources=['code'])
    if intent == 'wording_only':
        value.update(origin='document',sources=[source('doc','document','context','Before: three attempts. After: 3 attempts.')])
        value['target']['sources']=['doc'];value['differences'][0].update(kind='wording',sources=['doc'])
    return value


class IntakeTests(unittest.TestCase):
    def test_three_routes_and_target_statuses(self):
        for intent, phase in [('current_behavior','awaiting_document_update'),('wording_only','no_code_work'),('behavior_change','pending_implementation')]:
            value=fixture(intent); result=intake.classify(value)
            self.assertEqual(result['phase'],phase)
            self.assertEqual(result['document_quality'],'not_evaluated')
            self.assertNotEqual(result['implementation'],'completed')
        for intent in ['current_behavior','wording_only','behavior_change']:
            for state in ['proposed','deferred','withdrawn']:
                value=fixture(intent);value['target']['status']=state
                self.assertEqual(intake.classify(value)['phase'], 'awaiting_decision' if state == 'proposed' else state)

    def test_false_current_wording_and_authority_fail(self):
        cases=[]
        value=fixture('current_behavior');value['current']['code']=None;cases.append(value)
        value=fixture('wording_only');value['differences'][0]['kind']='behavior';cases.append(value)
        value=fixture();value['sources'][0]['authority']='context';cases.append(value)
        value=fixture();value['sources'][0]['kind']='document';cases.append(value)
        value=fixture();value['target']['sources']=['missing'];cases.append(value)
        value=fixture();value['sources'].append(copy.deepcopy(value['sources'][0]));cases.append(value)
        value=fixture();value['sources'][0]['text']='changed';cases.append(value)
        for value in cases:
            with self.subTest(value=value), self.assertRaises(ValueError):intake.classify(value)

    def test_missing_and_unknown_fields_cannot_claim_completion(self):
        from jsonschema.exceptions import ValidationError
        cases=[]
        value=fixture();del value['current']['code'];cases.append(value)
        value=fixture();value['implementation']='completed';cases.append(value)
        value=fixture();value['target']['acceptance']=[];cases.append(value)
        for value in cases:
            with self.subTest(value=value), self.assertRaises(ValidationError):intake.classify(value)

    def test_immutable_reentry_and_tamper_refusal(self):
        from argparse import Namespace
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); input_file=root/'input.json';input_file.write_text(json.dumps(fixture()))
            args=Namespace(input=input_file)
            first=intake.register(args,root);self.assertEqual(first,intake.register(args,root))
            record=intake.load(root,first['intake']);self.assertIsNone(record['input']['current']['code'])
            path=Path(first['record']); value=json.loads(path.read_text());value['phase']='completed';path.write_text(json.dumps(value))
            with self.assertRaises(ValueError):intake.load(root,first['intake'])
            with self.assertRaises(ValueError):intake.load(root,'../input')
            (root/'retired.json').write_text('{}')
            with self.assertRaises(ValueError):intake.register(args,root)


if __name__ == '__main__':unittest.main()
