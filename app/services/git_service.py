from __future__ import annotations

import json
import os
import ssl
import subprocess
import tempfile
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
    # -----------------------------
    # Low-level git helpers
    # -----------------------------

    def _run_git(self, args: list[str]) -> str:
        cmd = ["git", *args]
        return subprocess.check_output(cmd, cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT)

    def _run_git_no_check(self, args: list[str]) -> tuple[int, str]:
        cmd = ["git", *args]
        proc = subprocess.run(cmd, cwd=REPO_ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        return proc.returncode, proc.stdout or ""

    # -----------------------------
    # GitLab API helpers
    # -----------------------------

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

    # -----------------------------
    # Repo metadata helpers
    # -----------------------------

    def get_blame(self, file: str, line: int) -> str:
        file_path = file if os.path.isabs(file) else os.path.join(REPO_ROOT, file)
        cmd = ["git", "blame", "-L", f"{line},{line}", file_path]
        return subprocess.check_output(cmd, cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT)

    def get_recent_commits(self, file: str, limit: int = 5) -> list[dict[str, str]]:
        file_path = file if os.path.isabs(file) else os.path.join(REPO_ROOT, file)
        cmd = ["git", "log", "-n", "5", "--pretty=format:%h|%an|%s|%ad", "--date=short", file_path]
        output = subprocess.check_output(cmd, cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT)

        commits: list[dict[str, str]] = []
        for row in output.split("\n"):
            parts = row.split("|")
            if len(parts) == 4:
                commits.append(
                    {
                        "hash": parts[0],
                        "author": parts[1],
                        "message": parts[2],
                        "date": parts[3],
                    }
                )

        return commits[:limit]

    def read_repo_file(self, relative_path: str) -> str:
        if not relative_path or not relative_path.strip():
            raise ValueError("relative_path is required")
        path = relative_path.strip()
        abs_path = path if os.path.isabs(path) else os.path.join(REPO_ROOT, path)
        with open(abs_path, "r", encoding="utf-8") as f:
            return f.read()

    # -----------------------------
    # Branch / PR workflow
    # -----------------------------

    def git_fetch(self):
        cmd = ["git", "fetch"]
        subprocess.check_output(cmd, cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT)

    def create_branch_from_main(self, jira_ticket_id: str, title: str) -> dict[str, str]:
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

        return {"base": base, "branch": branch_name}

    # -----------------------------
    # Patch handling
    # -----------------------------

    def _looks_like_unified_diff(self, text: str) -> bool:
        t = (text or "").lstrip()
        if not t:
            return False
        if "diff --git " in t:
            return True
        if "--- " in t and "+++ " in t:
            return True
        if t.startswith("@@ "):
            return True
        return False

    def _normalize_diff_text(self, diff_text: str) -> str:
        """
        Make LLM-produced diffs more "git apply"-friendly.
        - Converts CRLF to LF
        - If text contains literal '\\n' but no real newlines, decode escapes
        - Ensures trailing newline
        - If patch begins with ---/+++ without a 'diff --git' header, prepend one
        """
        text = diff_text or ""

        # If the string contains literal "\n" sequences but no actual newlines,
        # it's likely we received an escaped diff string.
        if "\n" not in text and "\\n" in text:
            try:
                text = text.encode("utf-8").decode("unicode_escape")
            except Exception:
                # If decoding fails, continue with original text; git will error meaningfully.
                pass

        text = text.replace("\r\n", "\n").replace("\r", "\n")
        if text and not text.endswith("\n"):
            text += "\n"

        stripped = text.lstrip()
        if stripped.startswith("--- "):
            lines = stripped.splitlines()
            if len(lines) >= 2 and lines[1].startswith("+++ "):
                old_path = lines[0][4:].strip()
                new_path = lines[1][4:].strip()
                if old_path.startswith("a/") and new_path.startswith("b/") and "diff --git " not in stripped:
                    header = f"diff --git {old_path} {new_path}\n"
                    text = header + stripped + ("\n" if not stripped.endswith("\n") else "")

        return text

    def apply_unified_diff(self, diff_text: str) -> None:
        diff_text = self._normalize_diff_text(diff_text)
        if not self._looks_like_unified_diff(diff_text):
            raise ValueError("Input does not look like a unified diff (expected 'diff --git' or '---' / '+++').")

        tmp_path: str | None = None
        try:
            with tempfile.NamedTemporaryFile("w", delete=False, dir=REPO_ROOT, suffix=".diff") as fp:
                fp.write(diff_text)
                tmp_path = fp.name

            def try_apply(args: list[str]) -> tuple[int, str]:
                return self._run_git_no_check([*args, tmp_path])

            has_diff_git = "diff --git " in diff_text
            has_index_line = "\nindex " in diff_text or diff_text.startswith("index ")

            primary_args = ["apply", "--whitespace=fix"]
            if has_diff_git and has_index_line:
                primary_args.insert(1, "--3way")
            else:
                primary_args.extend(["-p1"])

            code, out = try_apply(primary_args)
            if code != 0 and "--3way" in primary_args:
                fallback_args = ["apply", "--whitespace=fix", "-p1"]
                code2, out2 = try_apply(fallback_args)
                if code2 == 0:
                    code, out = 0, out2
                else:
                    out = f"{out}\n\n--- fallback (no --3way) ---\n{out2}"

            if code != 0:
                raise RuntimeError(f"Failed to apply diff via git apply.\n\n{out}")
        finally:
            if tmp_path:
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass

        status = self._run_git(["status", "--porcelain"]).strip()
        if not status:
            raise RuntimeError("Diff applied cleanly but produced no working tree changes.")

    def commit_all(self, message: str) -> None:
        if not message or not message.strip():
            raise ValueError("commit message is required")

        self._run_git(["add", "-A"])
        status = self._run_git(["status", "--porcelain"]).strip()
        if not status:
            raise RuntimeError("No changes to commit after applying fix.")

        try:
            self._run_git(["commit", "-m", message.strip()])
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Failed to commit changes.\n\n{e.output}") from e

    def push_current_branch(self, branch_name: str | None = None) -> None:
        if branch_name:
            args = ["push", "-u", "origin", branch_name]
        else:
            args = ["push", "-u", "origin", "HEAD"]
        try:
            self._run_git(args)
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Failed to push branch.\n\n{e.output}") from e

    def create_merge_request(
        self,
        *,
        source_branch: str,
        target_branch: str,
        title: str,
        body: str | None = None,
        draft: bool = False,
    ) -> dict[str, str]:
        if not source_branch or not source_branch.strip():
            raise ValueError("source_branch is required")
        if not target_branch or not target_branch.strip():
            raise ValueError("target_branch is required")
        if not title or not title.strip():
            raise ValueError("title is required")

        normalized_title = title.strip()
        if draft and not normalized_title.lower().startswith("draft:"):
            normalized_title = f"Draft: {normalized_title}"

        project_id = self._gitlab_project_id()
        response = self._gitlab_request(
            "POST",
            f"/projects/{project_id}/merge_requests",
            json_data={
                "source_branch": source_branch,
                "target_branch": target_branch,
                "title": normalized_title,
                "description": (body or "").strip(),
            },
        )

        return {
            "pr_title": normalized_title,
            "pr_url": response.get("web_url") or "",
        }