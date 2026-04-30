from __future__ import annotations

import json
import os
import ssl
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from app.config import (
    GITLAB_PROJECT,
    GITLAB_SERVER_URL,
    GITLAB_SSL_CA_BUNDLE,
    GITLAB_TOKEN,
    GITLAB_VERIFY_SSL,
    MAIN_BRANCH,
    REPO_ROOT,
)

class GitService:

    def _run_git(self, args: list[str]) -> str:
        cmd = ["git", *args]
        return subprocess.check_output(cmd, cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT)

    def _parse_bool(self, value: Any, default: bool = True) -> bool:
        if value is None:
            return default
        if isinstance(value, bool):
            return value
        text = str(value).strip().lower()
        if text in {"1", "true", "yes", "y", "on"}:
            return True
        if text in {"0", "false", "no", "n", "off"}:
            return False
        return default

    def _gitlab_api_base(self) -> str:
        base = (GITLAB_SERVER_URL or "").strip()
        if not base:
            raise RuntimeError("Missing GitLab server URL. Set GITLAB_SERVER_URL.")
        base = base.rstrip("/")
        if base.endswith("/api/v4"):
            return base
        return f"{base}/api/v4"

    def _gitlab_project_id(self) -> str:
        project = (GITLAB_PROJECT or "").strip()
        if not project:
            raise RuntimeError("Missing GitLab project path. Set GITLAB_PROJECT (namespace/project).")
        return urllib.parse.quote(project, safe="")

    def _gitlab_headers(self) -> dict[str, str]:
        token = (GITLAB_TOKEN or "").strip()
        if not token:
            raise RuntimeError("Missing GitLab token. Set GITLAB_TOKEN.")
        return {
            "PRIVATE-TOKEN": token,
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

    def _gitlab_ssl_context(self) -> ssl.SSLContext | None:
        verify = self._parse_bool(GITLAB_VERIFY_SSL, default=True)
        if verify:
            if GITLAB_SSL_CA_BUNDLE:
                return ssl.create_default_context(cafile=GITLAB_SSL_CA_BUNDLE)
            return None
        return ssl._create_unverified_context()  # noqa: SLF001

    def _gitlab_request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
        json_data: dict[str, Any] | None = None,
    ) -> Any:
        base = self._gitlab_api_base()
        url = f"{base}{path}"
        if params:
            query = urllib.parse.urlencode(params)
            url = f"{url}?{query}"

        data = None
        if json_data is not None:
            data = json.dumps(json_data).encode("utf-8")

        req = urllib.request.Request(
            url,
            data=data,
            method=method.upper(),
            headers=self._gitlab_headers(),
        )

        try:
            with urllib.request.urlopen(req, timeout=30, context=self._gitlab_ssl_context()) as resp:
                raw = resp.read()
                if not raw:
                    return {}
                try:
                    return json.loads(raw.decode("utf-8"))
                except json.JSONDecodeError:
                    return {"raw_response": raw.decode("utf-8", errors="replace")}
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
            raise RuntimeError(f"GitLab API error ({exc.code}) for {method} {path}: {body}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"GitLab request failed: {exc}") from exc

    def _slugify_title(self, title: str, max_len: int = 50, jira_issue_id: str | None = None) -> str:
        s = title.strip()
        if jira_issue_id:
            jira = jira_issue_id.strip()
            if jira:
                upper = s.upper()
                jira_upper = jira.upper()
                if upper.startswith(jira_upper):
                    s = s[len(jira) :].lstrip(" :-_#/[]()")
        s = s.lower()
        out: list[str] = []
        prev_dash = False
        for ch in s:
            is_alnum = ("a" <= ch <= "z") or ("0" <= ch <= "9")
            if is_alnum:
                out.append(ch)
                prev_dash = False
                continue

            if ch in (" ", "-", "_", ".", "/"):
                if not prev_dash and out:
                    out.append("-")
                    prev_dash = True
                continue

            # drop all other characters (emoji, punctuation, etc.)
        slug = "".join(out).strip("-")
        if not slug:
            slug = "fix"
        return slug[:max_len].rstrip("-")

    def get_blame(self, file, line):
        file_path = file if os.path.isabs(file) else os.path.join(REPO_ROOT, file)
        cmd = ["git", "blame", "-L", f"{line},{line}", file_path]
        return subprocess.check_output(cmd, cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT)

    def get_recent_commits(self, file):
        file_path = file if os.path.isabs(file) else os.path.join(REPO_ROOT, file)
        cmd = ["git", "log", "-n", "5", "--pretty=format:%h|%an|%s|%ad", "--date=short", file_path]
        output = subprocess.check_output(cmd, cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT)

        commits = []
        for line in output.split("\n"):
            parts = line.split("|")
            if len(parts) == 4:
                commits.append({
                    "hash": parts[0],
                    "author": parts[1],
                    "message": parts[2],
                    "date": parts[3]
                })

        return commits

    def file_changed_recently(self, file):
        file_path = file if os.path.isabs(file) else os.path.join(REPO_ROOT, file)
        cmd = ["git", "log", "-1", "--", file_path]
        out = subprocess.check_output(cmd, cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT)
        return bool(out.strip())



    def git_fetch(self):
        cmd = ["git", "fetch"]
        subprocess.check_output(cmd, cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT)

    def create_branch_and_pr_from_main(
        self,
        jira_ticket_id: str,
        title: str,
        body: str | None = None,
        *,
        draft: bool = False,
    ) -> dict:
        """
        Fetches latest remote state, creates a branch from config.MAIN_BRANCH, pushes it,
        and opens a PR targeting config.MAIN_BRANCH.
        """
        if not jira_ticket_id or not jira_ticket_id.strip():
            raise ValueError("jira_ticket_id is required")
        if not title or not title.strip():
            raise ValueError("title is required")

        jira = jira_ticket_id.strip().upper()
        slug = self._slugify_title(title, jira_issue_id=jira)
        branch_name = f"ai-bugfix/{jira}-{slug}"
        base = MAIN_BRANCH

        # 1) Sync refs
        self.git_fetch()

        # 2) Ensure local base branch exists and fast-forwards to origin/base
        origin_base = f"origin/{base}"
        base_exists = True
        try:
            self._run_git(["rev-parse", "--verify", base])
        except subprocess.CalledProcessError:
            base_exists = False

        if base_exists:
            try:
                self._run_git(["checkout", base])
                self._run_git(["merge", "--ff-only", origin_base])
            except subprocess.CalledProcessError as e:
                raise RuntimeError(
                    f"Failed to fast-forward {base!r} to {origin_base!r}. "
                    f"Your local branch may have diverged.\n\n{e.output}"
                ) from e
        else:
            self._run_git(["checkout", "-b", base, origin_base])

        # 3) Create feature branch from updated base
        try:
            self._run_git(["checkout", "-b", branch_name])
        except subprocess.CalledProcessError as e:
            raise RuntimeError(
                f"Failed to create branch {branch_name!r}. It may already exist.\n\n{e.output}"
            ) from e

        # 4) Push branch
        try:
            self._run_git(["push", "-u", "origin", branch_name])
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Failed to push branch {branch_name!r}.\n\n{e.output}") from e

        # 5) Create PR (GitLab merge request)
        pr_title = f"{jira}: {title.strip()}"
        pr_body = (body or "").strip()
        normalized_title = pr_title
        if draft and not normalized_title.lower().startswith("draft:"):
            normalized_title = f"Draft: {normalized_title}"

        project_id = self._gitlab_project_id()
        response = self._gitlab_request(
            "POST",
            f"/projects/{project_id}/merge_requests",
            json_data={
                "source_branch": branch_name,
                "target_branch": base,
                "title": normalized_title,
                "description": pr_body,
            },
        )

        return {
            "base": base,
            "branch": branch_name,
            "pr_title": normalized_title,
            "pr_url": response.get("web_url") or "",
        }
    