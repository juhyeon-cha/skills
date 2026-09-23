"""Convert explicit SAP graph show-id exports without collecting or opening a DB."""

import hashlib
import json
from datetime import datetime


def _text(value, field):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"INPUT: SAP {field} must be a nonblank string")
    return value


def _object(value, field):
    if not isinstance(value, dict):
        raise ValueError(f"INPUT: SAP {field} must be an object")
    return value


def adapt_sap_graph(payload, *, producer_version):
    """Preserve one exported owner graph; completeness is limited to its profile."""
    _text(producer_version, "producer_version")
    _object(payload, "export")
    observation = _object(payload.get("observation"), "observation")
    owner = _object(payload.get("owner"), "owner")
    selected = _object(payload.get("selected"), "selected")
    source = _text(observation.get("source_id"), "observation.source_id")
    object_id = _text(observation.get("id"), "observation.id")
    profile = _text(observation.get("profile"), "observation.profile")
    object_type = _text(observation.get("object_type"), "observation.object_type")
    source_key = _text(observation.get("source_key"), "observation.source_key")
    name = _text(observation.get("name"), "observation.name")
    if (owner.get("id"), owner.get("system_key"), owner.get("object_type"),
            owner.get("source_key")) != (object_id, source, object_type, source_key):
        raise ValueError("INPUT: SAP owner does not match observation source and identity")
    for key in ("references", "elements", "relations", "effectiveSignatures", "collection"):
        if not isinstance(payload.get(key), list) or any(
            not isinstance(item, dict) for item in payload[key]
        ):
            raise ValueError(f"INPUT: SAP {key} must be an array of objects")
    for key, owner_field in (("elements", "object_id"), ("relations", "owner_object_id")):
        for item in payload[key]:
            _text(item.get("id"), key + ".id")
            if item.get(owner_field) != object_id:
                raise ValueError(f"INPUT: SAP {key} includes another owner's evidence")
    if selected not in [owner, *payload["elements"], *payload["relations"]]:
        raise ValueError("INPUT: SAP selected entity is outside the exported owner graph")
    _object(observation.get("evidence"), "observation.evidence")
    original_status = observation.get("status")
    if original_status not in ("complete", "partial", "failed", "unsupported", "reference"):
        raise ValueError("INPUT: SAP observation status is unsupported")
    structure_source = observation.get("structureSource")
    if structure_source not in ("complete", "partial", "none"):
        raise ValueError("INPUT: SAP observation structureSource is unsupported")
    stale = observation.get("stale")
    if not isinstance(stale, bool):
        raise ValueError("INPUT: SAP observation stale must be a boolean")
    if original_status == "complete":
        _text(observation.get("structure_hash"), "observation.structure_hash")
        if structure_source != "complete":
            raise ValueError("INPUT: SAP complete observation lacks a complete structure")
    observed_at = _text(observation.get("observed_at"), "observation.observed_at")
    try:
        timestamp = datetime.fromisoformat(observed_at.replace("Z", "+00:00"))
        if "T" not in observed_at or timestamp.utcoffset() is None:
            raise ValueError()
    except ValueError as exc:
        raise ValueError("INPUT: SAP observed_at must be an ISO timestamp with timezone") from exc
    try:
        canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True,
                               separators=(",", ":"), allow_nan=False)
        body = json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2,
                          allow_nan=False)
    except (TypeError, ValueError) as exc:
        raise ValueError("INPUT: SAP export must contain JSON values") from exc
    status = original_status if original_status in ("complete", "failed") else "partial"
    if status == "complete" and stale:
        status = "partial"
    return {
        "source": source,
        "object": object_id,
        "revision": "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
        "observed_at": observed_at,
        "status": status,
        "title": f"{object_type} {name}",
        "body": body,
        "metadata": {
            "producer": "sap-harness graph show-id",
            "producer_version": producer_version,
            "locator": "object:" + object_id,
            "original_status": original_status,
            "structure_source": structure_source,
            "stale": str(stale).lower(),
            "profile": profile,
            "source_key": source_key,
            "revision_kind": "export-content-sha256",
            "evidence_scope": "single exported object graph; collector profile " + profile,
        },
    }
