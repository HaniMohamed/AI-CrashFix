from __future__ import annotations

import hashlib
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from app import config as cfg


_REPO_NAME_FALLBACK = "project"


def _slugify(text: str, max_len: int = 48) -> str:
    s = (text or "").strip().lower()
    # Keep it filesystem friendly.
    s = re.sub(r"[^a-z0-9._-]+", "-", s)
    s = re.sub(r"-{2,}", "-", s).strip("-._")
    if not s:
        s = _REPO_NAME_FALLBACK
    return s[:max_len].strip("-._") or _REPO_NAME_FALLBACK


def _repo_name_from_url(repo_url: str) -> str:
    u = (repo_url or "").strip().rstrip("/")
    if not u:
        return _REPO_NAME_FALLBACK
    # Remove trailing ".git" and take last path segment.
    tail = u.split("/")[-1]
    if tail.endswith(".git"):
        tail = tail[:-4]
    return _slugify(tail) or _REPO_NAME_FALLBACK


@dataclass(frozen=True)
class PreparedProject:
    project_id: str
    repo_url: str
    repo_ref: str | None
    repo_root: str


class ProjectService:
    """
    Manage user-provided remote repositories by cloning them into a local workspace folder.

    This keeps the main AI-CrashFix repo clean and makes runs reproducible.
    """

    def __init__(self, base_dir: str | None = None) -> None:
        # Default to a workspace-local folder (relative to current process cwd).
        root = (base_dir or getattr(cfg, "WORKSPACE_PROJECTS_DIR", "") or "workspace_projects").strip()
        self.base_dir = Path(root).expanduser()
        if not self.base_dir.is_absolute():
            self.base_dir = (Path.cwd() / self.base_dir).resolve()

    def prepare_repo(self, *, repo_url: str, repo_ref: str | None = None) -> PreparedProject:
        url = (repo_url or "").strip()
        if not url:
            raise ValueError("repo_url is required")

        ref = (repo_ref or "").strip() or None
        key = f"{url}@{ref or ''}".encode("utf-8")
        project_id = hashlib.sha1(key).hexdigest()[:12]  # stable, short id

        name = _repo_name_from_url(url)
        target = (self.base_dir / f"{name}-{project_id}").resolve()
        self.base_dir.mkdir(parents=True, exist_ok=True)

        if not (target / ".git").is_dir():
            # Clone once. Keep it lightweight for large repos.
            subprocess.check_output(
                ["git", "clone", "--no-tags", "--filter=blob:none", url, str(target)],
                text=True,
                stderr=subprocess.STDOUT,
            )
        else:
            # Existing clone: refresh refs.
            subprocess.check_output(
                ["git", "fetch", "--all", "--prune"],
                cwd=str(target),
                text=True,
                stderr=subprocess.STDOUT,
            )

        # Checkout requested ref (branch / tag / commit) if provided.
        if ref:
            subprocess.check_output(
                ["git", "checkout", "--force", ref],
                cwd=str(target),
                text=True,
                stderr=subprocess.STDOUT,
            )
        else:
            # Ensure working tree is on the configured main branch if it exists.
            main = (cfg.MAIN_BRANCH or "main").strip() or "main"
            # Best-effort: checkout main if present; otherwise keep whatever clone defaulted to.
            try:
                subprocess.check_output(
                    ["git", "checkout", "--force", main],
                    cwd=str(target),
                    text=True,
                    stderr=subprocess.STDOUT,
                )
                subprocess.check_output(
                    ["git", "pull", "--ff-only"],
                    cwd=str(target),
                    text=True,
                    stderr=subprocess.STDOUT,
                )
            except Exception:
                pass

        # Basic sanity: must be a git repo.
        subprocess.check_output(
            ["git", "rev-parse", "--is-inside-work-tree"],
            cwd=str(target),
            text=True,
            stderr=subprocess.STDOUT,
        )

        # Normalize path string for downstream usage.
        repo_root = os.fspath(target)
        return PreparedProject(project_id=project_id, repo_url=url, repo_ref=ref, repo_root=repo_root)

