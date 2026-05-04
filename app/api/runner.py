"""Streaming runner that mirrors `scripts/run_batch.py` but yields events.

This module contains no business logic of its own; it composes the same
primitives the CLI uses (`build_graph`, `CrashStore`, `CrashlyticsService`,
`node_span`, `ensure_run_id`) and exposes them as an event-yielding generator.

Two event streams are merged into one ordered iterator:

1. Native LangGraph state snapshots from `graph.stream(stream_mode="values")`
   - one full `CrashState` after each top-level node executes.
2. Observability events captured via `register_event_sink` -
   `node_started`, `node_completed`, `router`, plus the `batch.*` spans this
   runner emits itself via `node_span`.

Concurrent runs are demuxed by tagging every emitted event with `run_id`; the
sink filters out events whose `run_id` does not match the current run.
"""

from __future__ import annotations

import collections
import traceback
from typing import Any, Deque, Dict, Iterator, List, Literal, Optional

from app.api.events import (
    CRASH_COMPLETED,
    CRASH_FAILED,
    CRASH_FETCHED,
    CRASH_SKIPPED,
    CRASH_STARTED,
    ERROR,
    RUN_STARTED,
    RUN_SUMMARY,
    STATE_SNAPSHOT,
    redact_state,
)
from app.config import CRASHLYTICS_FETCH_BACKEND
from app.graph.graph_builder import build_graph
from app.graph.observability import (
    ensure_run_id,
    node_span,
    record_graph_error,
    register_event_sink,
    stamp_graph_run_end,
    stamp_graph_run_start,
    unregister_event_sink,
)
from app.services.crash_store import CrashStore
from app.services.crashlytics_service import CrashlyticsService


# Same shape used by scripts/run_batch.py::_initial_state_for_crash; duplicated
# here on purpose so the script does not need to be modified.
def _initial_state_for_crash(
    crash: Dict[str, Any],
    *,
    run_id: str,
    skip_jira_creation: bool,
    mock: bool,
) -> Dict[str, Any]:
    return {
        "graph_run_id": run_id,
        "graph_error": None,
        "mock": bool(mock),
        "skip_jira_creation": bool(skip_jira_creation),
        "crash_id": crash.get("crash_id") or "",
        "exception": crash.get("exception") or "",
        "stacktrace": crash.get("stacktrace") or [],
        "app_version": crash.get("app_version"),
        "device": crash.get("device"),
        "platform": crash.get("platform"),
        "mapped_frames": [],
        "repo_context": {},
        "root_cause": "",
        "confidence": 0.0,
        "fix_suggestion": "",
        "jira_payload": None,
        "jira_issue_id": None,
    }


def stream_run(
    *,
    mode: Literal["batch", "single"],
    limit: int = 10,
    mock: bool = False,
    skip_jira_creation: bool = False,
    crash_ids: Optional[List[str]] = None,
    crash: Optional[Dict[str, Any]] = None,
) -> Iterator[Dict[str, Any]]:
    """Yield NDJSON-ready event dicts for a batch or single-crash run.

    Args:
        mode: "batch" runs the same flow as `scripts/run_batch.py`. "single"
              runs the graph for one crash payload supplied by the caller.
        limit: max crashes to fetch (batch mode only).
        mock: use the mocked crash list instead of BigQuery / Cloud Logging.
        skip_jira_creation: forwarded to the graph state.
        crash_ids: optional whitelist applied AFTER fetching (batch mode); only
                   crashes whose id appears in this list are processed.
        crash: required when `mode="single"`; the crash payload to run.
    """
    graph = build_graph()
    crash_store = CrashStore()

    batch_state: Dict[str, Any] = {}
    run_id = ensure_run_id(batch_state)

    pending: Deque[Dict[str, Any]] = collections.deque()

    def _sink(ev: Dict[str, Any]) -> None:
        # Filter out events from other concurrent runs.
        if ev.get("run_id") and ev.get("run_id") != run_id:
            return
        pending.append(ev)

    register_event_sink(_sink)

    try:
        yield {
            "type": RUN_STARTED,
            "run_id": run_id,
            "mode": mode,
            "limit": limit,
            "mock": mock,
            "skip_jira_creation": skip_jira_creation,
            "crash_ids_filter": list(crash_ids) if crash_ids else None,
            "crashlytics_backend": CRASHLYTICS_FETCH_BACKEND,
        }

        if mode == "batch":
            yield from _run_batch(
                graph=graph,
                crash_store=crash_store,
                run_id=run_id,
                limit=limit,
                mock=mock,
                skip_jira_creation=skip_jira_creation,
                crash_ids=crash_ids,
                pending=pending,
            )
        elif mode == "single":
            if not crash:
                yield {
                    "type": ERROR,
                    "run_id": run_id,
                    "error": {
                        "type": "ValueError",
                        "message": "mode='single' requires a 'crash' payload",
                    },
                }
                return
            yield from _run_single(
                graph=graph,
                crash_store=crash_store,
                run_id=run_id,
                crash=crash,
                mock=mock,
                skip_jira_creation=skip_jira_creation,
                pending=pending,
            )
        else:
            yield {
                "type": ERROR,
                "run_id": run_id,
                "error": {"type": "ValueError", "message": f"unknown mode={mode!r}"},
            }
    except Exception as e:
        yield {
            "type": ERROR,
            "run_id": run_id,
            "error": {
                "type": type(e).__name__,
                "message": str(e),
                "trace": traceback.format_exc(),
            },
        }
        raise
    finally:
        unregister_event_sink(_sink)
        while pending:
            yield pending.popleft()


# ---- internals -------------------------------------------------------------


def _drain(pending: Deque[Dict[str, Any]]) -> Iterator[Dict[str, Any]]:
    while pending:
        yield pending.popleft()


def _run_batch(
    *,
    graph,
    crash_store: CrashStore,
    run_id: str,
    limit: int,
    mock: bool,
    skip_jira_creation: bool,
    crash_ids: Optional[List[str]],
    pending: Deque[Dict[str, Any]],
) -> Iterator[Dict[str, Any]]:
    service = CrashlyticsService()

    with node_span(
        {"graph_run_id": run_id},
        "batch.fetch",
        extra={
            "limit": limit,
            "mock": mock,
            "crashlytics_backend": CRASHLYTICS_FETCH_BACKEND,
        },
    ):
        crashes = (
            service.fetch_recent_crashes_mock(limit=limit)
            if mock
            else service.fetch_recent_crashes(limit=limit)
        ) or []

    if crash_ids:
        wanted = {c.strip() for c in crash_ids if c}
        crashes = [c for c in crashes if c.get("crash_id") in wanted]

    yield from _drain(pending)
    yield {
        "type": CRASH_FETCHED,
        "run_id": run_id,
        "count": len(crashes),
        "crash_ids": [c.get("crash_id") for c in crashes if c.get("crash_id")],
    }

    if not crashes:
        yield {
            "type": RUN_SUMMARY,
            "run_id": run_id,
            "fetched": 0,
            "processed": 0,
            "skipped": 0,
            "failed": 0,
        }
        return

    counters = {"processed": 0, "skipped": 0, "failed": 0}

    for crash in crashes:
        crash_id = crash.get("crash_id")
        if not crash_id:
            continue

        if crash_store.is_processed(crash_id):
            counters["skipped"] += 1
            with node_span(
                {"graph_run_id": run_id, "crash_id": crash_id},
                "batch.skip",
                extra={"reason": "already_processed"},
            ):
                pass
            yield from _drain(pending)
            yield {
                "type": CRASH_SKIPPED,
                "run_id": run_id,
                "crash_id": crash_id,
                "reason": "already_processed",
            }
            continue

        crash_store.insert_crash(crash_id)
        state = _initial_state_for_crash(
            crash, run_id=run_id, skip_jira_creation=skip_jira_creation, mock=mock
        )
        yield from _stream_one_crash(
            graph=graph,
            crash_store=crash_store,
            run_id=run_id,
            state=state,
            pending=pending,
            counters=counters,
        )

    yield {
        "type": RUN_SUMMARY,
        "run_id": run_id,
        "fetched": len(crashes),
        "processed": counters["processed"],
        "skipped": counters["skipped"],
        "failed": counters["failed"],
    }


def _run_single(
    *,
    graph,
    crash_store: CrashStore,
    run_id: str,
    crash: Dict[str, Any],
    mock: bool,
    skip_jira_creation: bool,
    pending: Deque[Dict[str, Any]],
) -> Iterator[Dict[str, Any]]:
    crash_id = (crash.get("crash_id") or "").strip()
    if crash_id:
        crash_store.insert_crash(crash_id)

    state = _initial_state_for_crash(
        crash, run_id=run_id, skip_jira_creation=skip_jira_creation, mock=mock
    )

    counters = {"processed": 0, "skipped": 0, "failed": 0}
    yield from _stream_one_crash(
        graph=graph,
        crash_store=crash_store,
        run_id=run_id,
        state=state,
        pending=pending,
        counters=counters,
    )

    yield {
        "type": RUN_SUMMARY,
        "run_id": run_id,
        "fetched": 1,
        "processed": counters["processed"],
        "skipped": counters["skipped"],
        "failed": counters["failed"],
    }


def _stream_one_crash(
    *,
    graph,
    crash_store: CrashStore,
    run_id: str,
    state: Dict[str, Any],
    pending: Deque[Dict[str, Any]],
    counters: Dict[str, int],
) -> Iterator[Dict[str, Any]]:
    crash_id = state.get("crash_id") or ""

    yield {
        "type": CRASH_STARTED,
        "run_id": run_id,
        "crash_id": crash_id,
        "initial_state": redact_state(state),
    }

    last_completed_node: Optional[str] = None
    final_state: Dict[str, Any] = state

    try:
        with node_span(state, "batch.process_crash"):
            stamp_graph_run_start(state)
            # `stream_mode="values"` yields the full CrashState after each top-level
            # node. Inner subgraph nodes still surface as node_started/node_completed
            # via the observability sink (no extra snapshot per inner node).
            for chunk in graph.stream(state, stream_mode="values"):
                # Flush any sink events accumulated since the last yield. The
                # most recent `node_completed` event tells us which node
                # produced this snapshot.
                while pending:
                    ev = pending.popleft()
                    if ev.get("type") == "node_completed":
                        last_completed_node = ev.get("node")
                    yield ev

                if isinstance(chunk, dict):
                    final_state = chunk
                    yield {
                        "type": STATE_SNAPSHOT,
                        "run_id": run_id,
                        "crash_id": crash_id,
                        "after_node": last_completed_node,
                        "state": redact_state(chunk),
                    }

        yield from _drain(pending)
    except Exception as e:
        yield from _drain(pending)
        # Shallow copy so we do not rely on LangGraph mutating the original dict.
        outcome: Dict[str, Any] = dict(final_state) if isinstance(final_state, dict) else dict(state)
        record_graph_error(outcome, "graph.stream", e)
        stamp_graph_run_end(outcome)
        counters["failed"] += 1
        if crash_id:
            try:
                crash_store.update_result(crash_id, outcome)
            except Exception:
                pass
        yield {
            "type": CRASH_FAILED,
            "run_id": run_id,
            "crash_id": crash_id,
            "error": {"type": type(e).__name__, "message": str(e)},
        }
        return

    stamp_graph_run_end(final_state)
    if crash_id:
        try:
            crash_store.update_result(crash_id, final_state)
        except Exception:
            # Persistence failure must not break the stream.
            pass

    counters["processed"] += 1
    yield {
        "type": CRASH_COMPLETED,
        "run_id": run_id,
        "crash_id": crash_id,
        "final_state": redact_state(final_state),
    }
