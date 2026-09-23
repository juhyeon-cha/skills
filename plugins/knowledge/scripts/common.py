"""Pure shared identity, version ordering and process environment helpers."""
from datetime import datetime, timezone
import hashlib
import json
import os
import re


def now():
    return datetime.now(timezone.utc).isoformat()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                     separators=(',', ':')).encode()).hexdigest()


def goal_order(before, after):
    """Only the documented integer families declare chronological ordering."""
    if before == after:
        return 0
    left, right = re.fullmatch(r'(v?)(0|[1-9][0-9]*)', before), re.fullmatch(r'(v?)(0|[1-9][0-9]*)', after)
    if not left or not right or left[1] != right[1]:
        raise ValueError('GOAL_VERSION_ORDER: incomparable versions; preserve the current goal and use a declared integer sequence')
    return (int(right[2]) > int(left[2])) - (int(right[2]) < int(left[2]))


def environment():
    return {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
