"""Offline adapter checks against the graph show-id shape at SAP 189fc239."""

import copy
import hashlib
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "plugins/knowledge/scripts"))
from sap_observations import adapt_sap_graph


class SapObservationsTest(unittest.TestCase):
    def fixture(self, version=1):
        return json.loads((Path(__file__).parent / "observations-fixtures" /
                           f"sap-show-id-v{version}.json").read_text())

    def convert(self, payload):
        return adapt_sap_graph(payload, producer_version="189fc239")

    def test_identity_body_time_and_complete_profile(self):
        payload = self.fixture()
        before = copy.deepcopy(payload)
        converted = self.convert(payload)
        self.assertEqual(payload, before)
        self.assertEqual(converted["source"], payload["observation"]["source_id"])
        self.assertEqual(converted["object"], payload["owner"]["id"])
        self.assertEqual(converted["observed_at"], payload["observation"]["observed_at"])
        self.assertEqual(converted["status"], "complete")
        self.assertEqual(json.loads(converted["body"]), payload)
        self.assertIn("clas-structure-v1", converted["metadata"]["evidence_scope"])
        self.assertTrue(all(isinstance(value, str) for value in converted["metadata"].values()))
        canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        self.assertEqual(converted["revision"], "sha256:" + hashlib.sha256(canonical.encode()).hexdigest())
        self.assertEqual(self.convert(dict(reversed(list(payload.items())))), converted)

    def test_partial_recollection_retains_old_structure_without_complete_claim(self):
        old, new = self.convert(self.fixture()), self.convert(self.fixture(2))
        self.assertEqual((old["source"], old["object"]), (new["source"], new["object"]))
        self.assertNotEqual(old["revision"], new["revision"])
        self.assertEqual(new["status"], "partial")
        self.assertEqual(new["metadata"]["stale"], "true")
        self.assertIn("Unsupported method declaration", new["body"])

    def test_projection_change_is_a_new_revision(self):
        payload = self.fixture()
        old = self.convert(payload)
        payload["effectiveSignatures"][0]["reason"] = "inheritance-parent-missing"
        self.assertNotEqual(self.convert(payload)["revision"], old["revision"])

    def test_noncomplete_states_and_no_inferred_removal(self):
        for original, expected in (("partial", "partial"), ("failed", "failed"),
                                   ("unsupported", "partial"), ("reference", "partial")):
            with self.subTest(original=original):
                payload = self.fixture()
                payload["observation"].update(status=original, stale=False,
                                               structure_hash=None, structureSource="none")
                result = self.convert(payload)
                self.assertEqual(result["status"], expected)
                self.assertEqual(result["metadata"]["original_status"], original)
        payload = self.fixture()
        payload["observation"]["stale"] = True
        self.assertEqual(self.convert(payload)["status"], "partial")

    def test_same_name_in_different_source_is_separate(self):
        payload = self.fixture()
        old = self.convert(payload)
        payload["owner"]["system_key"] = "source-b"
        payload["selected"]["system_key"] = "source-b"
        payload["observation"]["source_id"] = "source-b"
        self.assertNotEqual(old["source"], self.convert(payload)["source"])

    def test_element_selection_keeps_owner_identity(self):
        payload = self.fixture()
        payload["selected"] = payload["elements"][0]
        self.assertEqual(self.convert(payload)["object"], payload["owner"]["id"])

    def test_rejects_cross_source_missing_state_invalid_time_and_plan_rows(self):
        mutations = [
            lambda p: p.pop("observation"),
            lambda p: p["observation"].update(source_id="other"),
            lambda p: p["observation"].update(id="other"),
            lambda p: p["observation"].update(status="ready"),
            lambda p: p["observation"].update(status="removed"),
            lambda p: p["observation"].update(stale="false"),
            lambda p: p["observation"].update(observed_at="2026-09-23T08:00:00"),
            lambda p: p["observation"].update(observed_at="yesterday"),
            lambda p: p["observation"].update(structure_hash=None),
            lambda p: p["observation"].update(evidence="{}"),
            lambda p: p["owner"].update(source_key="other"),
            lambda p: p["elements"][0].update(object_id="another-owner"),
            lambda p: p.update(selected={"id": "another-object"}),
            lambda p: p.pop("elements"),
            lambda p: p.update(references=["invalid"]),
            lambda p: p.update(extra=float("nan")),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                payload = self.fixture()
                mutate(payload)
                with self.assertRaisesRegex(ValueError, "^INPUT:"):
                    self.convert(payload)
        with self.assertRaisesRegex(ValueError, "^INPUT:"):
            adapt_sap_graph(self.fixture(), producer_version="")


if __name__ == "__main__":
    unittest.main()
