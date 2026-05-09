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
import queue
import threading
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
from app.graph.fix_generation_graph.nodes.fallback import FIX_VALIDATION_EXHAUSTED_PREFIX
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
    repo_root: str | None,
    repo_url: str | None,
    repo_ref: str | None,
    repo_key: str | None,
) -> Dict[str, Any]:
    return {
        "graph_run_id": run_id,
        "graph_error": None,
        "mock": bool(mock),
        "skip_jira_creation": bool(skip_jira_creation),
        "repo_root": repo_root,
        "repo_url": repo_url,
        "repo_ref": repo_ref,
        "repo_key": repo_key,
        "crash_id": crash.get("crash_id") or "",
        "exception": crash.get("exception") or "",
        "stacktrace": crash.get("stacktrace") or [],
        "app_version": crash.get("app_version"),
        "device": crash.get("device"),
        "platform": crash.get("platform"),
        "app_identifier": crash.get("app_identifier"),
        "crashlytics_console_app_id": crash.get("crashlytics_console_app_id"),
        "mapped_frames": [],
        "repo_context": {},
        "root_cause": "",
        "confidence": 0.0,
        "fix_suggestion": "",
        "jira_payload": None,
        "jira_issue_id": None,
    }


def _crash_dict_from_persisted_result(result: Dict[str, Any], crash_id: str) -> Dict[str, Any]:
    """Rebuild the minimal crash payload the graph expects from a stored ``result`` JSON."""
    cid = (str(result.get("crash_id") or crash_id or "")).strip()
    return {
        "crash_id": cid,
        "exception": result.get("exception") or "",
        "stacktrace": result.get("stacktrace") or [],
        "app_version": result.get("app_version"),
        "device": result.get("device"),
        "platform": result.get("platform"),
        "app_identifier": result.get("app_identifier"),
        "crashlytics_console_app_id": result.get("crashlytics_console_app_id"),
    }


def _resolve_single_crash_payload(
    *,
    crash_store: CrashStore,
    service: CrashlyticsService,
    crash_id: str,
    mock: bool,
) -> Dict[str, Any] | None:
    """Load one crash from Crashlytics (or mock), else from SQLite ``result``."""
    cid = (crash_id or "").strip()
    if not cid:
        return None
    row = service.fetch_crash_by_id(cid, mock=mock)
    if row is not None:
        return row
    st = crash_store.get_crash(cid, include_result=True)
    if st and isinstance(st.get("result"), dict):
        return _crash_dict_from_persisted_result(st["result"], cid)
    return None


def stream_run(
    *,
    mode: Literal["batch", "single"],
    limit: int = 10,
    mock: bool = False,
    skip_jira_creation: bool = False,
    crash_ids: Optional[List[str]] = None,
    crash_id: Optional[str] = None,
    repo_url: Optional[str] = None,
    repo_ref: Optional[str] = None,
) -> Iterator[Dict[str, Any]]:
    """Yield NDJSON-ready event dicts for a batch or single-crash run.

    Args:
        mode: "batch" runs the same flow as `scripts/run_batch.py`. "single"
              fetches one crash by ``crash_id`` then runs the graph.
        limit: max crashes to fetch (batch mode only).
        mock: use the mocked crash list instead of BigQuery / Cloud Logging.
        skip_jira_creation: forwarded to the graph state.
        crash_ids: optional whitelist applied AFTER fetching (batch mode); only
                   crashes whose id appears in this list are processed.
        crash_id: required when ``mode="single"``; Crashlytics issue id to load.
    """
    graph = build_graph()
    batch_state: Dict[str, Any] = {}
    run_id = ensure_run_id(batch_state)

    # Resolve repo_root once per run; all crashes in the batch share it.
    resolved_repo_root: str | None = None
    resolved_repo_url: str | None = (repo_url or "").strip() or None
    resolved_repo_ref: str | None = (repo_ref or "").strip() or None
    resolved_repo_key: str | None = None
    if resolved_repo_url:
        from app.services.project_service import ProjectService

        proj = ProjectService().prepare_repo(repo_url=resolved_repo_url, repo_ref=resolved_repo_ref)
        resolved_repo_root = proj.repo_root
        resolved_repo_key = proj.project_id
    else:
        # Back-compat: allow env REPO_ROOT, but UI should prefer repo_url.
        from app import config as cfg

        resolved_repo_root = (cfg.REPO_ROOT or "").strip() or None
        resolved_repo_key = None

    crash_store = CrashStore(repo_key=resolved_repo_key) if resolved_repo_key else CrashStore()

    # NOTE: Must be a thread-safe queue. Subgraph node events can be emitted while
    # `graph.stream(...)` is blocked inside a long-running node; we still want to
    # stream those events to the client in real time.
    pending: queue.Queue[Dict[str, Any]] = queue.Queue()

    def _sink(ev: Dict[str, Any]) -> None:
        # Filter out events from other concurrent runs.
        if ev.get("run_id") and ev.get("run_id") != run_id:
            return
        pending.put(ev)

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
            "repo": {
                "repo_url": resolved_repo_url,
                "repo_ref": resolved_repo_ref,
                "repo_root": resolved_repo_root,
                "repo_key": resolved_repo_key,
            },
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
                repo_root=resolved_repo_root,
                repo_url=resolved_repo_url,
                repo_ref=resolved_repo_ref,
                repo_key=resolved_repo_key,
            )
        elif mode == "single":
            cid = (crash_id or "").strip()
            if not cid:
                yield {
                    "type": ERROR,
                    "run_id": run_id,
                    "error": {
                        "type": "ValueError",
                        "message": "mode='single' requires crash_id",
                    },
                }
                return
            service = CrashlyticsService(mock=mock)
            resolved = _resolve_single_crash_payload(
                crash_store=crash_store,
                service=service,
                crash_id=cid,
                mock=mock,
            )
            if not resolved:
                yield {
                    "type": ERROR,
                    "run_id": run_id,
                    "error": {
                        "type": "LookupError",
                        "message": (
                            f"crash_id={cid!r} not found in Crashlytics"
                            + (" (mock)" if mock else "")
                            + " and no persisted result in the local store"
                        ),
                    },
                }
                return
            yield from _drain(pending)
            yield {
                "type": CRASH_FETCHED,
                "run_id": run_id,
                "count": 1,
                "crash_ids": [cid],
            }
            yield from _run_single(
                graph=graph,
                crash_store=crash_store,
                run_id=run_id,
                crash=resolved,
                mock=mock,
                skip_jira_creation=skip_jira_creation,
                pending=pending,
                repo_root=resolved_repo_root,
                repo_url=resolved_repo_url,
                repo_ref=resolved_repo_ref,
                repo_key=resolved_repo_key,
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
        yield from _drain(pending)


# ---- internals -------------------------------------------------------------


def _drain(pending: Deque[Dict[str, Any]]) -> Iterator[Dict[str, Any]]:
    # Drain a Queue without blocking.
    while True:
        try:
            yield pending.get_nowait()
        except Exception:
            break


def _run_batch(
    *,
    graph,
    crash_store: CrashStore,
    run_id: str,
    limit: int,
    mock: bool,
    skip_jira_creation: bool,
    crash_ids: Optional[List[str]],
    pending: queue.Queue[Dict[str, Any]],
    repo_root: str | None,
    repo_url: str | None,
    repo_ref: str | None,
    repo_key: str | None,
) -> Iterator[Dict[str, Any]]:
    service = CrashlyticsService(mock=mock)

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
            "deduped": 0,
            "failed": 0,
        }
        return

    counters = {"processed": 0, "skipped": 0, "deduped": 0, "failed": 0}

    for crash in crashes:
        crash_id = crash.get("crash_id")
        if not crash_id:
            continue

        if crash_store.is_processed(crash_id):
            counters["deduped"] += 1
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
            crash,
            run_id=run_id,
            skip_jira_creation=skip_jira_creation,
            mock=mock,
            repo_root=repo_root,
            repo_url=repo_url,
            repo_ref=repo_ref,
            repo_key=repo_key,
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
        "deduped": counters["deduped"],
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
    pending: queue.Queue[Dict[str, Any]],
    repo_root: str | None,
    repo_url: str | None,
    repo_ref: str | None,
    repo_key: str | None,
) -> Iterator[Dict[str, Any]]:
    crash_id = (crash.get("crash_id") or "").strip()
    if crash_id:
        crash_store.insert_crash(crash_id)

    state = _initial_state_for_crash(
        crash,
        run_id=run_id,
        skip_jira_creation=skip_jira_creation,
        mock=mock,
        repo_root=repo_root,
        repo_url=repo_url,
        repo_ref=repo_ref,
        repo_key=repo_key,
    )

    counters = {"processed": 0, "skipped": 0, "deduped": 0, "failed": 0}
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
        "deduped": counters["deduped"],
        "failed": counters["failed"],
    }


def _stream_one_crash(
    *,
    graph,
    crash_store: CrashStore,
    run_id: str,
    state: Dict[str, Any],
    pending: queue.Queue[Dict[str, Any]],
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
            # node. Subgraph nodes do NOT yield values, but they DO emit observability
            # events via the sink. To stream those subgraph events in real time, we
            # run `graph.stream(...)` in a background thread and continuously drain
            # the sink queue while it executes.

            snapshots: queue.Queue[Dict[str, Any]] = queue.Queue()
            done = threading.Event()
            stream_exc: list[BaseException] = []

            def _run_stream() -> None:
                try:
                    for chunk in graph.stream(state, stream_mode="values"):
                        if isinstance(chunk, dict):
                            snapshots.put(chunk)
                except BaseException as e:  # noqa: BLE001
                    stream_exc.append(e)
                finally:
                    done.set()

            t = threading.Thread(target=_run_stream, name="graph.stream", daemon=True)
            t.start()

            # Drain loop: prioritize node events; emit snapshots when available.
            while True:
                emitted = False

                # 1) Drain all pending node/router events first.
                while True:
                    try:
                        ev = pending.get_nowait()
                    except Exception:
                        break
                    emitted = True
                    if ev.get("type") == "node_completed":
                        last_completed_node = ev.get("node")
                    yield ev

                # 2) Emit any snapshots produced so far.
                while True:
                    try:
                        chunk = snapshots.get_nowait()
                    except Exception:
                        break
                    emitted = True
                    final_state = chunk
                    yield {
                        "type": STATE_SNAPSHOT,
                        "run_id": run_id,
                        "crash_id": crash_id,
                        "after_node": last_completed_node,
                        "state": redact_state(chunk),
                    }

                # 3) Exit when stream is done and queues are empty.
                if done.is_set() and snapshots.empty():
                    break

                # 4) Avoid busy-spin; wake up frequently to keep events "live".
                if not emitted:
                    done.wait(0.05)

            # If the graph thread failed, re-raise so the outer handler emits CRASH_FAILED.
            if stream_exc:
                raise stream_exc[0]

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

    # Non-error terminal outcome: graph decided to skip further processing.
    if str(final_state.get("pipeline_status") or "").lower() == "skipped":
        counters["skipped"] += 1
        yield {
            "type": CRASH_SKIPPED,
            "run_id": run_id,
            "crash_id": crash_id,
            "reason": (final_state.get("pipeline_note") or "skipped").strip()
            if isinstance(final_state.get("pipeline_note"), str)
            else "skipped",
        }
        return

    err_msg = final_state.get("graph_error") if isinstance(final_state, dict) else None
    if err_msg:
        counters["failed"] += 1
        msg = str(err_msg)
        err_type = (
            "FixValidationExhausted"
            if msg.startswith(FIX_VALIDATION_EXHAUSTED_PREFIX)
            else "GraphPipelineError"
        )
        yield {
            "type": CRASH_FAILED,
            "run_id": run_id,
            "crash_id": crash_id,
            "error": {"type": err_type, "message": msg},
        }
        return

    counters["processed"] += 1
    yield {
        "type": CRASH_COMPLETED,
        "run_id": run_id,
        "crash_id": crash_id,
        "final_state": redact_state(final_state),
    }
