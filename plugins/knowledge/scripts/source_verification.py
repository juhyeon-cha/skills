"""Reuse only pinned Git captures within one project command."""
from contextlib import contextmanager
from contextvars import ContextVar

from cli import canonical

_captures = ContextVar('knowledge_captures', default=None)


@contextmanager
def command_sources():
    token = _captures.set({})
    try:
        yield
    finally:
        _captures.reset(token)


def verify_source(repo, snapshot, capture):
    cache = _captures.get()
    key = (str(repo.resolve()), snapshot['repository'], snapshot['commit'],
           canonical(snapshot['scope']))
    if cache is None or key not in cache:
        actual = capture(repo, snapshot['repository'], snapshot['commit'], snapshot['scope'])
        if cache is not None:
            cache[key] = actual
    else:
        actual = cache[key]
    # Compare the whole supplied snapshot on every use, even on cache hits.
    if actual != snapshot:
        raise ValueError('SOURCE_MISMATCH: pinned Git tree differs')
