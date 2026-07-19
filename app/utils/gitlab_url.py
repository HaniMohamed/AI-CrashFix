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


def derive_gitlab_server_url_from_repo_url(raw: str) -> str | None:
    """
    GitLab base URL (scheme + host[:port]) from a normal git remote URL.

    Examples:
      https://gitlab.gosi.ins/super-app/gosi-super-app → https://gitlab.gosi.ins
      git@gitlab.gosi.ins:super-app/gosi-super-app.git → https://gitlab.gosi.ins
    """
    u = (raw or "").strip()
    if not u:
        return None
    if u.startswith("git@"):
        # git@host:path
        at = u.find("@")
        colon = u.find(":")
        if at < 0 or colon <= at:
            return None
        host = u[at + 1 : colon].strip()
        if not host:
            return None
        return f"https://{host}"
    parsed = urlparse(u)
    if not parsed.scheme or not parsed.netloc:
        return None
    # Drop userinfo if present (rare for https remotes).
    host = parsed.hostname
    if not host:
        return None
    port = parsed.port
    netloc = f"{host}:{port}" if port else host
    return f"{parsed.scheme}://{netloc}"
