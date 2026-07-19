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

    def expected_repo_root(self, *, repo_url: str, repo_ref: str | None = None) -> str:
        """Compute the deterministic local path for this repo key (no network)."""
        url = (repo_url or "").strip()
        if not url:
            raise ValueError("repo_url is required")
        ref = (repo_ref or "").strip() or None
        key = f"{url}@{ref or ''}".encode("utf-8")
        project_id = hashlib.sha1(key).hexdigest()[:12]
        name = _repo_name_from_url(url)
        target = (self.base_dir / f"{name}-{project_id}").resolve()
        return os.fspath(target)

    @staticmethod
    def get_head_sha(repo_root: str) -> str | None:
        root = (repo_root or "").strip()
        if not root:
            return None
        try:
            out = subprocess.check_output(
                ["git", "rev-parse", "HEAD"],
                cwd=root,
                text=True,
                stderr=subprocess.STDOUT,
            )
            sha = (out or "").strip()
            return sha or None
        except Exception:
            return None

    def prepare_repo(
        self,
        *,
        repo_url: str,
        repo_ref: str | None = None,
        access_token: str | None = None,
        clean_workdir: bool = True,
    ) -> PreparedProject:
        url = (repo_url or "").strip()
        if not url:
            raise ValueError("repo_url is required")

        ref = (repo_ref or "").strip() or None
        key = f"{url}@{ref or ''}".encode("utf-8")
        project_id = hashlib.sha1(key).hexdigest()[:12]  # stable, short id

        name = _repo_name_from_url(url)
        target = (self.base_dir / f"{name}-{project_id}").resolve()
        self.base_dir.mkdir(parents=True, exist_ok=True)

        token = (access_token or "").strip() or None
        clone_cmd = ["git"]
        if token:
            # Avoid embedding tokens in URLs (and avoid leaking them in logs).
            # For GitHub PATs, a Basic auth header of "x-access-token:<token>" works.
            import base64

            basic = base64.b64encode(f"x-access-token:{token}".encode("utf-8")).decode("ascii")
            clone_cmd.extend(["-c", f"http.extraHeader=Authorization: Basic {basic}"])

        if not (target / ".git").is_dir():
            # Clone once. Keep it lightweight for large repos.
            subprocess.check_output(
                [*clone_cmd, "clone", "--no-tags", "--filter=blob:none", url, str(target)],
                text=True,
                stderr=subprocess.STDOUT,
            )
        else:
            # Existing clone: refresh refs.
            subprocess.check_output(
                [*clone_cmd, "fetch", "--all", "--prune"],
                cwd=str(target),
                text=True,
                stderr=subprocess.STDOUT,
            )

        # Checkout requested ref (branch / tag / commit) if provided.
        # Critical: after fetch, `git checkout --force uat` keeps the *local* branch tip
        # (often stale). Reset local branch to origin/<ref> when that remote exists.
        if ref:
            self._checkout_ref(
                target, ref=ref, clone_cmd=clone_cmd, clean_workdir=clean_workdir
            )
        else:
            # Ensure working tree tracks the configured main branch tip.
            main = (cfg.MAIN_BRANCH or "main").strip() or "main"
            try:
                self._checkout_ref(
                    target, ref=main, clone_cmd=clone_cmd, clean_workdir=clean_workdir
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

    @staticmethod
    def _rev_parse_ok(repo_root: Path, rev: str) -> bool:
        proc = subprocess.run(
            ["git", "rev-parse", "--verify", rev],
            cwd=str(repo_root),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        return proc.returncode == 0

    def _checkout_ref(
        self,
        target: Path,
        *,
        ref: str,
        clone_cmd: list[str],
        clean_workdir: bool = True,
    ) -> None:
        """
        Move HEAD to the latest remote tip for branch-like refs.

        Prefer ``origin/<ref>`` after fetch; otherwise fall back to a direct
        checkout (commit SHA / local-only ref / tag after a targeted fetch).
        """
        remote_ref = f"origin/{ref}"
        if self._rev_parse_ok(target, remote_ref):
            # Create/reset local branch to match remote tip.
            subprocess.check_output(
                ["git", "checkout", "--force", "-B", ref, remote_ref],
                cwd=str(target),
                text=True,
                stderr=subprocess.STDOUT,
            )
        else:
            # Tag or other remote ref that is not origin/<name> yet — try fetching it.
            if not self._rev_parse_ok(target, ref):
                try:
                    subprocess.check_output(
                        [*clone_cmd, "fetch", "origin", "tag", ref, "--no-tags"],
                        cwd=str(target),
                        text=True,
                        stderr=subprocess.STDOUT,
                    )
                except Exception:
                    try:
                        subprocess.check_output(
                            [*clone_cmd, "fetch", "origin", ref],
                            cwd=str(target),
                            text=True,
                            stderr=subprocess.STDOUT,
                        )
                    except Exception:
                        pass

            subprocess.check_output(
                ["git", "checkout", "--force", ref],
                cwd=str(target),
                text=True,
                stderr=subprocess.STDOUT,
            )

        # Drop leftover edits/untracked files from a previous crash/PR attempt so
        # the next run starts from a clean tip of the configured ref.
        if clean_workdir:
            subprocess.check_output(
                ["git", "reset", "--hard", "HEAD"],
                cwd=str(target),
                text=True,
                stderr=subprocess.STDOUT,
            )
            subprocess.check_output(
                ["git", "clean", "-fd"],
                cwd=str(target),
                text=True,
                stderr=subprocess.STDOUT,
            )

