from __future__ import annotations

from urllib.parse import urlparse


def derive_gitlab_project_path_from_repo_url(raw: str) -> str | None:
    """
    ``namespace/project`` path for the GitLab API, derived from a normal git remote URL.
    Mirrors the frontend ``deriveGitlabProjectPathFromRepoUrl``.
    """
    u = (raw or "").strip()
    if not u:
        return None
    if u.startswith("git@"):
        at = u.find("@")
        colon = u.find(":")
        if colon <= at or colon >= len(u) - 1:
            return None
        path = u[colon + 1 :].strip()
        if path.lower().endswith(".git"):
            path = path[: -len(".git")]
        path = path.strip("/")
        return path or None
    parsed = urlparse(u)
    if not parsed.netloc:
        return None
    path = parsed.path or ""
    if path.lower().endswith(".git"):
        path = path[: -len(".git")]
    path = path.strip("/")
    return path or None
