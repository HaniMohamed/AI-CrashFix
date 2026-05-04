import json
import logging
import os
import time
import uuid
from datetime import datetime, timezone
from contextlib import contextmanager
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple

from app.config import AI_CRASH_FIX_GRAPH_LOG_LEVEL, AI_CRASH_FIX_GRAPH_LOG_STYLE

_LOG_LEVEL = AI_CRASH_FIX_GRAPH_LOG_LEVEL.upper()
_LOG_STYLE = AI_CRASH_FIX_GRAPH_LOG_STYLE.lower()  # pretty|json
_LOG_JSON = _LOG_STYLE == "json"

# Optional fan-out of structured events to subscribers (e.g. the API layer).
# This is purely additive; when no sink is registered (CLI / tests), behavior is
# byte-for-byte identical to before. Sinks must be cheap and non-blocking.
_event_sinks: List[Callable[[Dict[str, Any]], None]] = []


def register_event_sink(fn: Callable[[Dict[str, Any]], None]) -> None:
    """Subscribe to graph observability events. Safe to call multiple times."""
    _event_sinks.append(fn)


def unregister_event_sink(fn: Callable[[Dict[str, Any]], None]) -> None:
    """Remove a previously-registered sink. No-op if not present."""
    try:
        _event_sinks.remove(fn)
    except ValueError:
        pass


def _emit(event: Dict[str, Any]) -> None:
    """Fan out an event to all registered sinks; never raises."""
    if not _event_sinks:
        return
    for sink in list(_event_sinks):
        try:
            sink(event)
        except Exception:
            # Sinks must never break the pipeline.
            pass


def _logger() -> logging.Logger:
    logger = logging.getLogger("ai_crash_fix.graph")
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter("%(message)s"))
        logger.addHandler(handler)
    logger.setLevel(_LOG_LEVEL)
    return logger


def _ansi(code: str) -> str:
    return f"\033[{code}m" if sys_stdout_is_tty() else ""


def sys_stdout_is_tty() -> bool:
    try:
        return bool(getattr(os.sys.stdout, "isatty", lambda: False)())
    except Exception:
        return False


def _c(text: str, color_code: str) -> str:
    if _LOG_JSON:
        return text
    return f"{_ansi(color_code)}{text}{_ansi('0')}"


def _safe_json(obj: Any) -> Any:
    try:
        json.dumps(obj)
        return obj
    except Exception:
        return str(obj)


def ensure_run_id(state: Dict[str, Any]) -> str:
    run_id = state.get("graph_run_id")
    if not run_id:
        run_id = uuid.uuid4().hex[:12]
        state["graph_run_id"] = run_id
    return str(run_id)


def record_graph_error(state: Dict[str, Any], where: str, exc: BaseException) -> None:
    """Set `graph_error` once (first failure wins) so outer spans do not mask node errors."""
    if state.get("graph_error"):
        return
    state["graph_error"] = f"{where}: {type(exc).__name__}: {exc}"


def stamp_graph_run_start(state: Dict[str, Any]) -> None:
    """UTC ISO timestamp when the graph run begins (idempotent)."""
    if state.get("graph_run_start_time"):
        return
    state["graph_run_start_time"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def stamp_graph_run_end(state: Dict[str, Any]) -> None:
    """UTC ISO timestamp when the graph run finishes (success or failure; idempotent)."""
    if state.get("graph_run_end_time"):
        return
    state["graph_run_end_time"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _shape(value: Any) -> Any:
    if value is None or isinstance(value, (bool, int, float, str)):
        if isinstance(value, str) and len(value) > 180:
            return value[:180] + "…"
        return value
    if isinstance(value, (list, tuple, set)):
        return {"type": type(value).__name__, "len": len(value)}
    if isinstance(value, dict):
        keys = list(value.keys())
        preview = keys[:10]
        more = max(0, len(keys) - len(preview))
        return {"type": "dict", "keys": preview, "more_keys": more}
    return {"type": type(value).__name__}


def summarize_state(state: Dict[str, Any], keys: Optional[Iterable[str]] = None) -> Dict[str, Any]:
    if keys is None:
        keys = state.keys()
    out: Dict[str, Any] = {}
    for k in keys:
        if k not in state:
            continue
        if k.lower() in {"openai_api_key", "google_api_key", "jira_token", "authorization"}:
            out[k] = "<redacted>"
            continue
        out[k] = _shape(state.get(k))
    return out


def state_delta(before: Dict[str, Any], after: Dict[str, Any]) -> Dict[str, Any]:
    before_keys = set(before.keys())
    after_keys = set(after.keys())

    added = sorted(after_keys - before_keys)
    removed = sorted(before_keys - after_keys)

    changed = []
    for k in sorted(before_keys & after_keys):
        if _shape(before.get(k)) != _shape(after.get(k)):
            changed.append(k)

    return {
        "added": added,
        "removed": removed,
        "changed": changed,
    }


@contextmanager
def node_span(state: Dict[str, Any], node: str, *, extra: Optional[Dict[str, Any]] = None):
    log = _logger()
    run_id = ensure_run_id(state)
    t0 = time.perf_counter()
    before = dict(state)

    if _LOG_JSON:
        payload = {
            "event": "node.start",
            "run_id": run_id,
            "node": node,
            "state": summarize_state(state, keys=("crash_id", "platform", "app_version", "device")),
        }
        if extra:
            payload["extra"] = _safe_json(extra)
        log.info(json.dumps(payload, ensure_ascii=False))
    else:
        headline = f"{_c('▶', '36')} {_c(node, '1;37')}  {_c('run', '90')}={_c(run_id, '35')}"
        if state.get("crash_id"):
            headline += f"  {_c('crash', '90')}={_c(str(state.get('crash_id')), '33')}"
        log.info(headline)

    _emit(
        {
            "type": "node_started",
            "run_id": run_id,
            "node": node,
            "crash_id": state.get("crash_id"),
            "extra": _safe_json(extra) if extra else None,
        }
    )

    try:
        yield
    except Exception as e:
        dt_ms = int((time.perf_counter() - t0) * 1000)
        if _LOG_JSON:
            payload = {
                "event": "node.error",
                "run_id": run_id,
                "node": node,
                "duration_ms": dt_ms,
                "error": {"type": type(e).__name__, "message": str(e)},
                "delta": state_delta(before, state),
            }
            log.error(json.dumps(payload, ensure_ascii=False))
        else:
            log.error(
                f"{_c('✖', '31')} {_c(node, '1;37')}  {_c(str(dt_ms)+'ms', '90')}  "
                f"{_c(type(e).__name__, '31')}: {str(e)}"
            )
        _emit(
            {
                "type": "node_error",
                "run_id": run_id,
                "node": node,
                "crash_id": state.get("crash_id"),
                "duration_ms": dt_ms,
                "delta": state_delta(before, state),
                "error": {"type": type(e).__name__, "message": str(e)},
                "extra": _safe_json(extra) if extra else None,
            }
        )
        record_graph_error(state, node, e)
        raise
    else:
        dt_ms = int((time.perf_counter() - t0) * 1000)
        after = dict(state)
        delta = state_delta(before, after)

        if _LOG_JSON:
            payload = {
                "event": "node.end",
                "run_id": run_id,
                "node": node,
                "duration_ms": dt_ms,
                "delta": delta,
            }
            if extra:
                payload["extra"] = _safe_json(extra)
            log.info(json.dumps(payload, ensure_ascii=False))
        else:
            parts = []
            if delta["added"]:
                parts.append(_c(f"+{len(delta['added'])}", "32"))
            if delta["changed"]:
                parts.append(_c(f"~{len(delta['changed'])}", "33"))
            if delta["removed"]:
                parts.append(_c(f"-{len(delta['removed'])}", "31"))
            diff_chip = " ".join(parts) if parts else _c("no-op", "90")
            log.info(
                f"{_c('✓', '32')} {_c(node, '1;37')}  {_c(str(dt_ms)+'ms', '90')}  {diff_chip}"
            )

        _emit(
            {
                "type": "node_completed",
                "run_id": run_id,
                "node": node,
                "crash_id": state.get("crash_id"),
                "duration_ms": dt_ms,
                "delta": delta,
                "extra": _safe_json(extra) if extra else None,
            }
        )


def instrument_node(node: str, fn: Callable[[Dict[str, Any]], Dict[str, Any]]) -> Callable[[Dict[str, Any]], Dict[str, Any]]:
    def _wrapped(state: Dict[str, Any]) -> Dict[str, Any]:
        if not state.get("graph_run_start_time"):
            state["graph_run_start_time"] = datetime.now(timezone.utc).isoformat()
        try:
            with node_span(state, node):
                return fn(state)
        finally:
            state["graph_run_end_time"] = datetime.now(timezone.utc).isoformat()

    _wrapped.__name__ = getattr(fn, "__name__", "wrapped")
    _wrapped.__doc__ = getattr(fn, "__doc__", None)
    return _wrapped


def instrument_router(name: str, router: Callable[[Dict[str, Any]], Any]) -> Callable[[Dict[str, Any]], Any]:
    def _wrapped(state: Dict[str, Any]) -> Any:
        run_id = ensure_run_id(state)
        t0 = time.perf_counter()
        try:
            route = router(state)
        except Exception as e:
            record_graph_error(state, f"router:{name}", e)
            raise
        dt_ms = int((time.perf_counter() - t0) * 1000)
        log = _logger()

        if _LOG_JSON:
            log.info(
                json.dumps(
                    {"event": "router", "run_id": run_id, "router": name, "route": route, "duration_ms": dt_ms},
                    ensure_ascii=False,
                )
            )
        else:
            log.info(
                f"{_c('↪', '34')} {_c(name, '1;37')}  {_c(str(dt_ms)+'ms', '90')}  "
                f"{_c('route', '90')}={_c(str(route), '36')}"
            )

        _emit(
            {
                "type": "router",
                "run_id": run_id,
                "router": name,
                "route": route,
                "crash_id": state.get("crash_id"),
                "duration_ms": dt_ms,
            }
        )
        return route

    _wrapped.__name__ = getattr(router, "__name__", "router")
    return _wrapped

