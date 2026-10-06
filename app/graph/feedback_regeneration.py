"""User-driven refinement: validate a free-text note, then re-run just the
fix-generation sub-flow (generate_fix -> review_fix -> validate_fix (loop) ->
generate_pr -> jira_update) against the same branch/MR.

Reuses the same NDJSON event + observability plumbing as `app.api.runner`.
"""

from __future__ import annotations

import queue
import re
import threading
import traceback
from typing import Any, Dict, Iterator

from app.api.events import (
    CRASH_COMPLETED,
    CRASH_FAILED,
    CRASH_STARTED,
    ERROR,
    FEEDBACK_SUMMARY,
    RUN_STARTED,
    RUN_SUMMARY,
    STATE_SNAPSHOT,
    redact_state,
)
from app.graph.graph_builder import build_feedback_graph
from app.graph.nodes.repo_context import repo_context
from app.graph.observability import (
    ensure_run_id,
    node_span,
    record_graph_error,
    register_event_sink,
    stamp_graph_run_end,
    stamp_graph_run_start,
    unregister_event_sink,
)
from app.prompts.feedback_validation_prompts import (
    FEEDBACK_VALIDATION_PROMPT_INPUT,
    FEEDBACK_VALIDATION_SYSTEM_PROMPT,
)
from app.services.ai_service import LLMService
from app.services.crash_store import CrashStore
from app.services.git_service import GitService
from app.utils.diff_parser import diff_stats, parse_unified_diff
from app.utils.llm_helpers import parse_json_object

_MIN_NOTE_LEN = 3
_MAX_NOTE_LEN = 2000
# Repeated-char / keyboard-mash spam, e.g. "aaaaaaaaaa" or "asdasdasdasd".
_RE_REPEATED_CHAR = re.compile(r"^(.)\1{9,}$")
_RE_REPEATED_RUN = re.compile(r"(.)\1{14,}")
_RE_HAS_LETTER = re.compile(r"[A-Za-z]")


def _guardrail_reject_reason(note: str) -> str | None:
    """Pre-LLM screen for empty/too-short/too-long/spam notes. Returns a reason, or None if it passes."""
    stripped = note.strip()
    if not stripped:
        return "The note is empty."
    if len(stripped) < _MIN_NOTE_LEN:
        return "The note is too short to act on."
    if len(stripped) > _MAX_NOTE_LEN:
        return f"The note exceeds the {_MAX_NOTE_LEN} character limit."
    if _RE_REPEATED_CHAR.match(stripped) or _RE_REPEATED_RUN.search(stripped):
        return "The note looks like repeated-character spam rather than feedback."
    if not _RE_HAS_LETTER.search(stripped):
        return "The note does not contain any readable text."
    return None


_VALID_INTENTS = frozenset({"question", "refinement", "invalid"})


def validate_feedback_note(note: str, state: Dict[str, Any]) -> Dict[str, Any]:
    """
    Guardrails first (no LLM call), then one LLM call that classifies the message as a
    "question" (answered inline, no code change), a "refinement" (triggers regeneration),
    or "invalid" (rejected). Returns ``{valid, intent, reason, answer}`` — ``valid`` is kept
    for backward compatibility and is only true for "refinement" (the one intent that should
    proceed to regenerate the fix).
    """
    reason = _guardrail_reject_reason(note or "")
    if reason:
        return {"valid": False, "intent": "invalid", "reason": reason, "answer": None}

    llm = LLMService()
    parsed = parse_json_object(
        llm.call(
            system_prompt=FEEDBACK_VALIDATION_SYSTEM_PROMPT(),
            user_prompt=FEEDBACK_VALIDATION_PROMPT_INPUT(note=note.strip(), state=state),
        ),
        context="validate_feedback_note",
    )
    intent = str(parsed.get("intent") or "").strip().lower()
    if intent not in _VALID_INTENTS:
        # Back-compat with the older {valid: bool} shape, or a malformed response.
        intent = "refinement" if parsed.get("valid") else "invalid"
    answer = parsed.get("answer")
    return {
        "valid": intent == "refinement",
        "intent": intent,
        "reason": str(parsed.get("reason") or "").strip(),
        "answer": str(answer).strip() if intent == "question" and answer else None,
    }


def _hydrate_feedback_state(crash_id: str, note: str, *, crash_store: CrashStore) -> Dict[str, Any] | None:
    """Rebuild a CrashState from the crash's persisted `result` JSON (same shape as a completed run)."""
    prev = crash_store.get_crash(crash_id, include_result=True)
    if not prev:
        return None
    prev_result = prev.get("result") if isinstance(prev.get("result"), dict) else None
    if not prev_result:
        return None

    state: Dict[str, Any] = dict(prev_result)
    state["crash_id"] = crash_id
    state["user_feedback_note"] = note.strip()
    state["fix_iteration_count"] = 0
    state.setdefault("fix_max_iterations", 3)
    state["pr_error"] = None
    state["jira_update_error"] = None
    state["graph_error"] = None
    state.pop("graph_run_start_time", None)
    state.pop("graph_run_end_time", None)

    # A prior fix is already committed on `pr_branch`; checkout that branch (not main)
    # and refresh `repo_context` from its current files so the new diff's hunk context
    # matches what `git apply` will see, instead of the pre-first-fix snapshot baked
    # into the persisted `result`.
    branch = str(state.get("pr_branch") or "").strip()
    repo_root = str(state.get("repo_root") or "").strip()
    if branch and repo_root:
        repo_key = (state.get("repo_key") or "").strip() or None
        git = GitService(repo_root=repo_root, repo_key=repo_key)
        git.checkout_existing_branch(branch)
        if state.get("mapped_frames"):
            state = repo_context(state)

    return state


def run_feedback_regeneration(crash_id: str, note: str, *, crash_store: CrashStore | None = None) -> Iterator[Dict[str, Any]]:
    """Orchestrator for a validated note: hydrate state, run the small feedback graph, stream events."""
    graph = build_feedback_graph()
    batch_state: Dict[str, Any] = {}
    run_id = ensure_run_id(batch_state)

    store = crash_store or CrashStore()

    pending: queue.Queue[Dict[str, Any]] = queue.Queue()

    def _sink(ev: Dict[str, Any]) -> None:
        if ev.get("run_id") and ev.get("run_id") != run_id:
            return
        pending.put(ev)

    register_event_sink(_sink)

    try:
        yield {"type": RUN_STARTED, "run_id": run_id, "mode": "feedback", "crash_id": crash_id}

        state = _hydrate_feedback_state(crash_id, note, crash_store=store)
        if state is None:
            yield {
                "type": ERROR,
                "run_id": run_id,
                "error": {
                    "type": "LookupError",
                    "message": f"crash_id={crash_id!r} has no persisted result to refine.",
                },
            }
            return

        yield {
            "type": CRASH_STARTED,
            "run_id": run_id,
            "crash_id": crash_id,
            "initial_state": redact_state(state),
        }

        last_completed_node: str | None = None
        final_state: Dict[str, Any] = state

        try:
            with node_span(state, "feedback.process_crash"):
                stamp_graph_run_start(state)

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

                t = threading.Thread(target=_run_stream, name="feedback_graph.stream", daemon=True)
                t.start()

                while True:
                    emitted = False

                    while True:
                        try:
                            ev = pending.get_nowait()
                        except Exception:
                            break
                        emitted = True
                        if ev.get("type") == "node_completed":
                            last_completed_node = ev.get("node")
                        yield ev

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

                    if done.is_set() and snapshots.empty():
                        break
                    if not emitted:
                        done.wait(0.05)

                if stream_exc:
                    raise stream_exc[0]

            while True:
                try:
                    yield pending.get_nowait()
                except Exception:
                    break
        except Exception as e:
            while True:
                try:
                    yield pending.get_nowait()
                except Exception:
                    break
            outcome: Dict[str, Any] = dict(final_state) if isinstance(final_state, dict) else dict(state)
            record_graph_error(outcome, "feedback_graph.stream", e)
            stamp_graph_run_end(outcome)
            try:
                store.update_result(crash_id, outcome)
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
        try:
            store.update_result(crash_id, final_state)
        except Exception:
            pass

        err_msg = final_state.get("graph_error") if isinstance(final_state, dict) else None
        if err_msg or final_state.get("pr_error"):
            yield {
                "type": CRASH_FAILED,
                "run_id": run_id,
                "crash_id": crash_id,
                "error": {
                    "type": "GraphPipelineError",
                    "message": str(err_msg or final_state.get("pr_error")),
                },
            }
            return

        yield {
            "type": CRASH_COMPLETED,
            "run_id": run_id,
            "crash_id": crash_id,
            "final_state": redact_state(final_state),
        }

        generated_diff = final_state.get("generated_diff") or ""
        stats = diff_stats(parse_unified_diff(generated_diff)) if generated_diff.strip() else None
        yield {
            "type": FEEDBACK_SUMMARY,
            "run_id": run_id,
            "crash_id": crash_id,
            "pr_url": final_state.get("pr_url"),
            "pr_body": final_state.get("pr_body"),
            "stats": stats,
        }

        yield {
            "type": RUN_SUMMARY,
            "run_id": run_id,
            "fetched": 1,
            "processed": 1,
            "skipped": 0,
            "deduped": 0,
            "failed": 0,
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
