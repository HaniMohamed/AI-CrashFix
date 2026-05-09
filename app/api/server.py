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

import os
import shutil
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from app.api.analytics import compute_analytics
from app.api.events import ERROR, to_ndjson
from app.api.runner import stream_run
from app.services.crash_store import CrashStore
from app.services.repo_registry_store import RepoRegistryStore


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
    repo_url: Optional[str] = Field(
        None,
        description="Optional: remote git repository URL to clone into the local workspace for this run.",
    )
    repo_ref: Optional[str] = Field(
        None,
        description="Optional: git ref to checkout after cloning (branch, tag, or commit).",
    )
    repo_key: Optional[str] = Field(
        None,
        description="Optional: stable repo key. If set, the backend resolves repo_url/ref from the repo registry.",
    )


class RepoUpsertRequest(BaseModel):
    name: str = Field(..., description="User-visible name for this repository.")
    repo_url: str = Field(..., description="Remote git repo URL.")
    repo_ref: Optional[str] = Field(None, description="Optional git ref (branch/tag/commit).")
    firebase_project_id: Optional[str] = Field(
        None,
        description="Firebase/GCP project id to use for Crashlytics/BigQuery instead of .env BQ_PROJECT_ID.",
    )
    access_token: Optional[str] = Field(
        None,
        description="Optional access token for cloning private repos. Stored server-side; never returned.",
    )
    packages_dirs: Optional[List[str]] = Field(
        None,
        description=(
            "Optional list of monorepo package root directories (repo-relative). "
            "Each entry is used as <dir>/*/lib during indexing/mapping, in addition to root lib/."
        ),
    )


class RepoSelectRequest(BaseModel):
    repo_key: str = Field(..., description="repo_key to mark as active.")


class RepoDeleteRequest(BaseModel):
    confirm_name: str = Field(..., description="Must match the repo name to confirm deletion.")


class RepoStatusResponse(BaseModel):
    repo_key: str
    repo_url: str
    repo_ref: Optional[str] = None
    repo_root: Optional[str] = None
    head_sha: Optional[str] = None
    index_status: Dict[str, Any] = Field(default_factory=dict)


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
    repo_key: Optional[str] = Query(None, description="Scope crashes to this repo_key (defaults to active repo)."),
) -> Dict[str, Any]:
    key = _resolve_repo_key(repo_key)
    project_id = None
    if key:
        entry = RepoRegistryStore().get_repo(key)
        project_id = entry.firebase_project_id if entry else None
    store = CrashStore(repo_key=key, project_id=project_id) if key else CrashStore(project_id=project_id)
    rows = store.list_crashes(
        status=status,
        limit=limit,
        offset=offset,
        include_result=include_result,
    )
    return {"items": rows, "limit": limit, "offset": offset, "count": len(rows)}


@app.get("/api/crashes/{crash_id}")
async def get_crash(
    crash_id: str,
    repo_key: Optional[str] = Query(None, description="Scope lookup to this repo_key (defaults to active repo)."),
) -> Dict[str, Any]:
    key = _resolve_repo_key(repo_key)
    project_id = None
    if key:
        entry = RepoRegistryStore().get_repo(key)
        project_id = entry.firebase_project_id if entry else None
    store = CrashStore(repo_key=key, project_id=project_id) if key else CrashStore(project_id=project_id)
    row = store.get_crash(crash_id, include_result=True)
    if row is None:
        raise HTTPException(status_code=404, detail=f"crash_id={crash_id!r} not found")
    return row


@app.get("/api/analytics")
async def get_analytics(
    no_cache: bool = Query(False, description="Bypass the 5s in-process cache"),
    repo_key: Optional[str] = Query(None, description="Scope analytics to this repo_key (defaults to active repo)."),
) -> Dict[str, Any]:
    key = _resolve_repo_key(repo_key)
    project_id = None
    if key:
        entry = RepoRegistryStore().get_repo(key)
        project_id = entry.firebase_project_id if entry else None
    store = CrashStore(repo_key=key, project_id=project_id) if key else CrashStore(project_id=project_id)
    return compute_analytics(store, use_cache=not no_cache)


@app.get("/api/repos")
async def list_repos() -> Dict[str, Any]:
    reg = RepoRegistryStore()
    items = [e.__dict__ for e in reg.list_repos()]
    return {"items": items, "count": len(items)}


@app.post("/api/repos")
async def upsert_repo(req: RepoUpsertRequest) -> Dict[str, Any]:
    reg = RepoRegistryStore()
    try:
        # Validate by cloning/checking out before persisting in registry.
        from app.services.project_service import ProjectService

        proj = ProjectService().prepare_repo(
            repo_url=req.repo_url,
            repo_ref=req.repo_ref,
            access_token=req.access_token,
        )
        entry = reg.upsert_repo(
            name=req.name,
            repo_url=req.repo_url,
            repo_ref=req.repo_ref,
            firebase_project_id=req.firebase_project_id,
            access_token=req.access_token,
            packages_dirs=req.packages_dirs,
        )
        # Build the symbol index on first add/update so stacktrace mapping is reliable
        # without requiring a manual refresh.
        try:
            from datetime import datetime

            from app.services.dart_symbol_index import build_symbol_index

            head_sha = ProjectService.get_head_sha(proj.repo_root)
            if head_sha:
                build_symbol_index(
                    repo_root=proj.repo_root,
                    repo_key=entry.repo_key,
                    commit_sha=head_sha,
                    packages_dirs=list(entry.packages_dirs or []),
                )
                reg.upsert_index_status(
                    repo_key=entry.repo_key,
                    indexed_sha=head_sha,
                    last_indexed_at=datetime.utcnow().isoformat(),
                    last_error=None,
                )
        except Exception as e:
            # Best-effort: repo add should still succeed even if indexing fails.
            reg.upsert_index_status(
                repo_key=entry.repo_key,
                indexed_sha=None,
                last_indexed_at=None,
                last_error=str(e),
            )
        # Create the per-repo crash DB immediately (schema included) so users see it
        # right after adding the repo (not only after starting a run).
        CrashStore(repo_key=entry.repo_key, project_id=entry.firebase_project_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to clone repo: {e}") from e
    return entry.__dict__


@app.get("/api/repos/active")
async def get_active_repo() -> Dict[str, Any]:
    reg = RepoRegistryStore()
    active = reg.get_active_repo()
    return {"active": (active.__dict__ if active else None)}


@app.post("/api/repos/select")
async def select_repo(req: RepoSelectRequest) -> Dict[str, Any]:
    reg = RepoRegistryStore()
    try:
        entry = reg.set_active_repo(req.repo_key)
    except LookupError as e:
        raise HTTPException(status_code=404, detail=str(e)) from e
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    return {"active": entry.__dict__}


@app.delete("/api/repos/{repo_key}")
async def delete_repo(repo_key: str, req: RepoDeleteRequest) -> Dict[str, Any]:
    reg = RepoRegistryStore()
    entry = reg.get_repo(repo_key)
    if entry is None:
        raise HTTPException(status_code=404, detail=f"repo_key={repo_key!r} not found")
    if (req.confirm_name or "").strip() != (entry.name or "").strip():
        raise HTTPException(status_code=400, detail="confirm_name did not match repo name")

    # Delete per-repo crash DB.
    try:
        crash_db = CrashStore(repo_key=repo_key, project_id=entry.firebase_project_id).db_path
        if crash_db and os.path.exists(crash_db):
            os.remove(crash_db)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete crash DB: {e}") from e

    # Delete cloned workspace directory (best-effort).
    try:
        from app import config as cfg

        base = Path((cfg.WORKSPACE_PROJECTS_DIR or "workspace_projects").strip() or "workspace_projects")
        if not base.is_absolute():
            base = (Path.cwd() / base).resolve()
        if base.is_dir():
            suffix = f"-{repo_key}"
            for child in base.iterdir():
                if child.is_dir() and child.name.endswith(suffix):
                    shutil.rmtree(child, ignore_errors=False)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete workspace clone: {e}") from e

    try:
        reg.delete_repo(repo_key)
    except LookupError as e:
        raise HTTPException(status_code=404, detail=str(e)) from e
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    return {"deleted": True, "repo_key": repo_key}


@app.get("/api/repos/{repo_key}/status")
async def get_repo_status(repo_key: str) -> Dict[str, Any]:
    key = (repo_key or "").strip()
    if not key:
        raise HTTPException(status_code=400, detail="repo_key is required")
    reg = RepoRegistryStore()
    entry = reg.get_repo(key)
    if entry is None:
        raise HTTPException(status_code=404, detail=f"repo_key={key!r} not found")

    from app.services.project_service import ProjectService

    svc = ProjectService()
    repo_root = None
    head_sha = None
    try:
        repo_root = svc.expected_repo_root(repo_url=entry.repo_url, repo_ref=entry.repo_ref)
        if repo_root and os.path.isdir(repo_root) and os.path.isdir(os.path.join(repo_root, ".git")):
            head_sha = svc.get_head_sha(repo_root)
        else:
            repo_root = None
    except Exception:
        repo_root = None

    idx = reg.get_index_status(key)
    idx_payload = {
        "indexed_sha": idx.indexed_sha if idx else None,
        "last_indexed_at": idx.last_indexed_at if idx else None,
        "last_error": idx.last_error if idx else None,
        "indexing": False,
    }
    return RepoStatusResponse(
        repo_key=entry.repo_key,
        repo_url=entry.repo_url,
        repo_ref=entry.repo_ref,
        repo_root=repo_root,
        head_sha=head_sha,
        index_status=idx_payload,
    ).model_dump()


@app.post("/api/repos/{repo_key}/refresh")
async def refresh_repo(repo_key: str) -> Dict[str, Any]:
    key = (repo_key or "").strip()
    if not key:
        raise HTTPException(status_code=400, detail="repo_key is required")
    reg = RepoRegistryStore()
    entry = reg.get_repo(key)
    if entry is None:
        raise HTTPException(status_code=404, detail=f"repo_key={key!r} not found")

    # Fetch + checkout configured ref/main using existing behavior.
    try:
        from app.services.project_service import ProjectService

        proj = ProjectService().prepare_repo(
            repo_url=entry.repo_url,
            repo_ref=entry.repo_ref,
            access_token=(reg.get_access_token(key) or None),
        )
        head_sha = ProjectService.get_head_sha(proj.repo_root)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to refresh repo: {e}") from e

    # Build / update index if HEAD changed.
    idx_before = reg.get_index_status(key)
    indexed_sha_before = idx_before.indexed_sha if idx_before else None
    if head_sha and head_sha != indexed_sha_before:
        try:
            from app.services.dart_symbol_index import build_symbol_index
            from datetime import datetime

            build_symbol_index(
                repo_root=proj.repo_root,
                repo_key=key,
                commit_sha=head_sha,
                packages_dirs=list(entry.packages_dirs or []),
            )
            reg.upsert_index_status(
                repo_key=key,
                indexed_sha=head_sha,
                last_indexed_at=datetime.utcnow().isoformat(),
                last_error=None,
            )
        except Exception as e:
            reg.upsert_index_status(
                repo_key=key,
                indexed_sha=indexed_sha_before,
                last_indexed_at=(idx_before.last_indexed_at if idx_before else None),
                last_error=str(e),
            )

    idx = reg.get_index_status(key)
    idx_payload = {
        "indexed_sha": idx.indexed_sha if idx else None,
        "last_indexed_at": idx.last_indexed_at if idx else None,
        "last_error": idx.last_error if idx else None,
        "indexing": False,
    }
    return RepoStatusResponse(
        repo_key=entry.repo_key,
        repo_url=entry.repo_url,
        repo_ref=entry.repo_ref,
        repo_root=proj.repo_root,
        head_sha=head_sha,
        index_status=idx_payload,
    ).model_dump()


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
            "workspace_projects_dir": cfg.WORKSPACE_PROJECTS_DIR,
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
                repo_url=_run_repo_url(req),
                repo_ref=_run_repo_ref(req),
                access_token=_run_repo_token(req),
                firebase_project_id=_run_firebase_project_id(req),
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


def _resolve_repo_key(explicit: str | None) -> str | None:
    key = (explicit or "").strip() or None
    if key:
        return key
    return RepoRegistryStore().get_active_repo_key()


def _run_repo_url(req: RunRequest) -> str | None:
    # Priority: explicit repo_url in request > resolve from repo_key > None
    if (req.repo_url or "").strip():
        return (req.repo_url or "").strip()
    if (req.repo_key or "").strip():
        reg = RepoRegistryStore()
        entry = reg.get_repo((req.repo_key or "").strip())
        if entry:
            return entry.repo_url
    return None


def _run_repo_ref(req: RunRequest) -> str | None:
    # Priority: explicit repo_ref in request > resolve from repo_key > None
    if (req.repo_ref or "").strip():
        return (req.repo_ref or "").strip()
    if (req.repo_key or "").strip():
        reg = RepoRegistryStore()
        entry = reg.get_repo((req.repo_key or "").strip())
        if entry:
            return entry.repo_ref
    return None


def _run_repo_token(req: RunRequest) -> str | None:
    # Only resolved from repo_key; we do not accept tokens in /api/runs payload.
    if (req.repo_key or "").strip():
        return RepoRegistryStore().get_access_token((req.repo_key or "").strip())
    return None


def _run_firebase_project_id(req: RunRequest) -> str | None:
    if (req.repo_key or "").strip():
        entry = RepoRegistryStore().get_repo((req.repo_key or "").strip())
        if entry:
            return entry.firebase_project_id
    return None
