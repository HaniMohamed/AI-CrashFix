"""Per-repo GCP service-account credential file storage."""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path

from app import config as cfg
from app.services.repo_registry_store import RepoEntry, RepoRegistryStore

_SAFE_REPO_KEY = re.compile(r"[^A-Za-z0-9._-]+")


def _credentials_root() -> Path:
    base = Path((cfg.WORKSPACE_PROJECTS_DIR or "workspace_projects").strip() or "workspace_projects")
    if not base.is_absolute():
        base = (Path.cwd() / base).resolve()
    return (base / "_credentials").resolve()


def save_repo_google_credentials(
    *,
    repo_key: str,
    raw: bytes,
    reg: RepoRegistryStore | None = None,
) -> tuple[RepoEntry, str]:
    """
    Validate SA JSON, write under ``_credentials/{repo_key}/``, and set the repo column.

    Returns ``(updated_entry, absolute_path)``.
    """
    key = (repo_key or "").strip()
    if not key:
        raise ValueError("repo_key is required")
    if not raw:
        raise ValueError("Empty file")
    try:
        parsed = json.loads(raw.decode("utf-8", errors="strict"))
    except Exception as e:
        raise ValueError(f"Invalid JSON: {e}") from e
    if not isinstance(parsed, dict):
        raise ValueError("Invalid JSON: expected object")
    if not parsed.get("type"):
        raise ValueError("Invalid service account JSON (missing 'type')")

    store = reg or RepoRegistryStore()
    entry = store.get_repo(key)
    if entry is None:
        raise LookupError(f"repo_key={key!r} not found")

    safe_key = _SAFE_REPO_KEY.sub("_", key)[:64] or "repo"
    target_dir = _credentials_root() / safe_key
    target_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    target = target_dir / f"gcp_credentials_{ts}.json"
    target.write_bytes(raw)

    updated = store.set_google_application_credentials(key, str(target))
    return updated, str(target)
