"""FastAPI app exposing the AI Crash Fix pipeline as an HTTP service.

Endpoints
---------
- ``GET /api/health``                 simple liveness probe
- ``POST /api/runs``                  run the pipeline (batch or single crash by id)
                                      and stream NDJSON events back
- ``GET /api/crashes``                paged list from the SQLite crash store
- ``GET /api/crashes/{crash_id}``     full row + parsed result JSON

Run with::

    uvicorn app.api.server:app --reload --port 8000

The streaming endpoint runs the (synchronous) graph generator in a worker
thread and forwards events through an ``asyncio.Queue`` so it never blocks the
event loop while LLM / BigQuery / git work is in flight.
"""

from __future__ import annotations

import asyncio
import threading
from typing import Any, AsyncIterator, Dict, List, Optional

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from app.api.analytics import compute_analytics
from app.api.events import ERROR, to_ndjson
from app.api.runner import stream_run
from app.services.crash_store import CrashStore


app = FastAPI(
    title="AI Crash Fix API",
    description=(
        "HTTP layer over the LangGraph crash-fix pipeline. Streams per-step "
        "graph events as NDJSON and exposes the crash store for read-only access."
    ),
    version="0.1.0",
)

# Permissive CORS for local UI development. Tighten in production behind a
# reverse proxy / explicit allow-list.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---- Schemas ---------------------------------------------------------------


class RunRequest(BaseModel):
    """Request body for ``POST /api/runs``.

    `mode="batch"`  - mirrors `scripts/run_batch.py`: fetches up to `limit`
                      recent crashes (or mocked) and runs each through the graph.
    `mode="single"` - runs the graph once: loads the crash by ``crash_id`` from
                      Crashlytics (or falls back to the last persisted ``result`` in SQLite).
    """

    mode: str = Field("batch", description="'batch' or 'single'")
    limit: int = Field(10, ge=1, le=200)
    mock: bool = False
    skip_jira_creation: bool = False
    crash_ids: Optional[List[str]] = Field(
        None,
        description=(
            "Batch mode: optional whitelist of crash ids; only those (from the "
            "fetched batch) are processed."
        ),
    )
    crash_id: Optional[str] = Field(
        None,
        description="Single mode: Crashlytics issue id to fetch, then run the pipeline.",
    )


# ---- Endpoints -------------------------------------------------------------


@app.get("/api/health")
async def health() -> Dict[str, Any]:
    return {"ok": True}


@app.post("/api/runs")
async def post_runs(req: RunRequest) -> StreamingResponse:
    if req.mode not in ("batch", "single"):
        raise HTTPException(status_code=400, detail=f"unknown mode={req.mode!r}")
    if req.mode == "single" and not (req.crash_id or "").strip():
        raise HTTPException(
            status_code=400,
            detail="mode='single' requires a non-empty 'crash_id' in the request body",
        )

    return StreamingResponse(
        _ndjson_stream(req),
        media_type="application/x-ndjson",
        headers={
            # Disable buffering by intermediaries (nginx, etc.) so events flush
            # in real time.
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@app.get("/api/crashes")
async def list_crashes(
    status: Optional[str] = Query(None, description="filter by status column"),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    include_result: bool = Query(False, description="parse and include the result JSON"),
) -> Dict[str, Any]:
    store = CrashStore()
    rows = store.list_crashes(
        status=status,
        limit=limit,
        offset=offset,
        include_result=include_result,
    )
    return {"items": rows, "limit": limit, "offset": offset, "count": len(rows)}


@app.get("/api/crashes/{crash_id}")
async def get_crash(crash_id: str) -> Dict[str, Any]:
    store = CrashStore()
    row = store.get_crash(crash_id, include_result=True)
    if row is None:
        raise HTTPException(status_code=404, detail=f"crash_id={crash_id!r} not found")
    return row


@app.get("/api/analytics")
async def get_analytics(
    no_cache: bool = Query(False, description="Bypass the 5s in-process cache"),
) -> Dict[str, Any]:
    store = CrashStore()
    return compute_analytics(store, use_cache=not no_cache)


@app.get("/api/config")
async def get_config() -> Dict[str, Any]:
    """Read-only redacted snapshot of `app.config` (loaded from .env at startup).

    Secrets are never returned; callers get a `has_*` boolean indicator instead.
    """
    from app import config as cfg

    return {
        "llm": {
            "provider": cfg.LLM_PROVIDER,
            "openai_model": cfg.OPENAI_MODEL,
            "gemini_model": cfg.GEMINI_MODEL,
            "openai_url": cfg.OPENAI_URL,
            "has_openai_api_key": bool(cfg.OPENAI_API_KEY),
            "has_google_api_key": bool(cfg.GOOGLE_API_KEY),
        },
        "repo": {
            "repo_root": cfg.REPO_ROOT,
            "main_branch": cfg.MAIN_BRANCH,
        },
        "crashlytics": {
            "backend": cfg.CRASHLYTICS_FETCH_BACKEND,
            "project_id": cfg.BQ_PROJECT_ID,
            "firebase_console_project_id": cfg.FIREBASE_CONSOLE_PROJECT_ID,
            "android_package_default": cfg.CRASHLYTICS_ANDROID_PACKAGE_DEFAULT,
            "ios_bundle_id_default": cfg.CRASHLYTICS_IOS_BUNDLE_ID_DEFAULT,
            "dataset": cfg.BQ_DATASET,
            "android_table": cfg.BQ_CRASHLYTICS_ANDROID_TABLE,
            "ios_table": cfg.BQ_CRASHLYTICS_IOS_TABLE,
            "has_credentials": bool(cfg.GOOGLE_APPLICATION_CREDENTIALS),
        },
        "jira": {
            "server_url": cfg.JIRA_SERVER_URL,
            "project_key": cfg.JIRA_PROJECT_KEY,
            "verify_ssl": cfg.JIRA_VERIFY_SSL,
            "has_token": bool(cfg.JIRA_TOKEN),
        },
        "gitlab": {
            "server_url": cfg.GITLAB_SERVER_URL,
            "project": cfg.GITLAB_PROJECT,
            "verify_ssl": cfg.GITLAB_VERIFY_SSL,
            "has_token": bool(cfg.GITLAB_TOKEN),
            "ca_bundle_set": bool(cfg.GITLAB_SSL_CA_BUNDLE),
        },
        "logging": {
            "level": cfg.AI_CRASH_FIX_GRAPH_LOG_LEVEL,
            "style": cfg.AI_CRASH_FIX_GRAPH_LOG_STYLE,
        },
    }


# ---- internals -------------------------------------------------------------


async def _ndjson_stream(req: RunRequest) -> AsyncIterator[bytes]:
    """Bridge the sync `stream_run` generator into an async NDJSON byte stream."""
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue = asyncio.Queue(maxsize=512)
    sentinel = object()

    def _producer() -> None:
        try:
            for ev in stream_run(
                mode=req.mode,  # type: ignore[arg-type]
                limit=req.limit,
                mock=req.mock,
                skip_jira_creation=req.skip_jira_creation,
                crash_ids=req.crash_ids,
                crash_id=(req.crash_id or "").strip() or None,
            ):
                fut = asyncio.run_coroutine_threadsafe(queue.put(ev), loop)
                fut.result()  # propagate back-pressure / cancellation
        except Exception as e:
            try:
                fut = asyncio.run_coroutine_threadsafe(
                    queue.put(
                        {
                            "type": ERROR,
                            "error": {
                                "type": type(e).__name__,
                                "message": str(e),
                            },
                        }
                    ),
                    loop,
                )
                fut.result()
            except Exception:
                pass
        finally:
            try:
                asyncio.run_coroutine_threadsafe(queue.put(sentinel), loop).result()
            except Exception:
                pass

    thread = threading.Thread(target=_producer, name="ai-crash-fix-runner", daemon=True)
    thread.start()

    while True:
        item = await queue.get()
        if item is sentinel:
            break
        yield to_ndjson(item)
