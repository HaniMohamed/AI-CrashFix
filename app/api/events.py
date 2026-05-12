"""Event types and serialization helpers for the streaming API.

Every API run produces an ordered sequence of dict events. Events are emitted
as newline-delimited JSON (NDJSON) by `app.api.server` so any HTTP client that
can read a streamed body (browser `fetch`, `curl`, `httpx.stream`) can consume
them line-by-line.

Two event sources are merged into one stream by `app.api.runner.stream_run`:
1. Native LangGraph `graph.stream(state, stream_mode="values")` - one full
   `CrashState` after each node executes (emitted here as `state_snapshot`).
2. The observability sink in `app.graph.observability` - per-node start/end
   timing + state delta + router decisions (no extra logging cost).
"""

from __future__ import annotations

import json
from typing import Any, Dict, Iterable

# Event type constants (kept loose strings; see README for the full schema).
RUN_STARTED = "run_started"
CRASH_FETCHED = "crash_fetched"
CRASH_SKIPPED = "crash_skipped"
CRASH_STARTED = "crash_started"
NODE_STARTED = "node_started"
NODE_COMPLETED = "node_completed"
NODE_ERROR = "node_error"
ROUTER = "router"
STATE_SNAPSHOT = "state_snapshot"
CRASH_COMPLETED = "crash_completed"
CRASH_FAILED = "crash_failed"
RUN_SUMMARY = "run_summary"
ERROR = "error"

# Keys that should never leave the process body in a state snapshot.
# Mirrors (and slightly extends) the redaction list in observability.summarize_state.
_REDACTED_KEYS = frozenset(
    k.lower()
    for k in (
        "openai_api_key",
        "google_api_key",
        "jira_token",
        "gitlab_token",
        "authorization",
        "gosi_brain_api_key",
        "gosi_brain_authorization",
    )
)


def _scrub(value: Any, _depth: int = 0) -> Any:
    """Recursively redact secret-like keys from dicts. Bounded depth to avoid
    pathological inputs."""
    if _depth > 8:
        return value
    if isinstance(value, dict):
        out: Dict[str, Any] = {}
        for k, v in value.items():
            if isinstance(k, str) and k.lower() in _REDACTED_KEYS:
                out[k] = "<redacted>"
            else:
                out[k] = _scrub(v, _depth + 1)
        return out
    if isinstance(value, list):
        return [_scrub(v, _depth + 1) for v in value]
    if isinstance(value, tuple):
        return [_scrub(v, _depth + 1) for v in value]
    return value


def redact_state(state: Dict[str, Any]) -> Dict[str, Any]:
    """Return a deep-copied state with any secret-like keys masked."""
    return _scrub(dict(state))


def to_ndjson(event: Dict[str, Any]) -> bytes:
    """Serialize one event as a single NDJSON line (terminated with `\\n`)."""
    return (json.dumps(event, ensure_ascii=False, default=str) + "\n").encode("utf-8")


def iter_ndjson(events: Iterable[Dict[str, Any]]) -> Iterable[bytes]:
    """Convenience: turn an iterable of event dicts into NDJSON byte chunks."""
    for ev in events:
        yield to_ndjson(ev)
