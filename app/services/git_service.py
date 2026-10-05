from __future__ import annotations

import json
import os
import re
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
)

_RE_UNIFIED_HUNK_HEADER = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@\s*$")


def _needs_unflatten_unified_diff(text: str) -> bool:
    """True when --- / +++ / @@ or hunk rows are glued without newlines (common malformed LLM output)."""
    if not text or not text.strip():
        return False
    if re.search(r"---\s+a/\S+\s+\+\+\+", text):
        return True
    if re.search(r"\+\+\+\s+b/\S+\s+@@", text):
        return True
    if re.search(r"@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@(?!\n)", text):
        return True
    return False


def _unflatten_llm_unified_diff(text: str) -> str:
    """
    Insert missing newlines so a flattened pseudo-diff becomes a valid unified diff.
    Does nothing if the text already looks multi-line structured.
    """
    if not _needs_unflatten_unified_diff(text):
        return text
    t = text
    # --- a/path +++ b/path (same physical line)
    t = re.sub(r"(---\s+a/\S+)\s+(\+\+\+\s+b/\S+)", r"\1\n\2", t)
    # +++ b/path @@ -...
    t = re.sub(r"(\+\+\+\s+b/\S+)\s+(@@\s*-)", r"\1\n\2", t)
    # @@ header not followed by newline (body glued on same line)
    t = re.sub(r"(@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@)(?!\n)", r"\1\n", t)
    # Hunk body: multiple +/- lines concatenated (repeat until stable).
    # Prefer specific closers before generic `)\s+-` to avoid splitting inside `"),` etc.
    for _ in range(64):
        before = t
        # `}}));` / `}));` / `, }));` before next `-`/`+` hunk line (regex: `}` + N×`)` + `;`)
        t = re.sub(r"(\}\}\)\);)\s+(-\s)", r"\1\n\2", t)
        t = re.sub(r"(\}\}\)\);)\s+(\+\s)", r"\1\n\2", t)
        t = re.sub(r"(,\s*\}\)\);)\s+(-\s)", r"\1\n\2", t)
        t = re.sub(r"(,\s*\}\)\);)\s+(\+\s)", r"\1\n\2", t)
        t = re.sub(r"(\}\)\);)\s+(-\s)", r"\1\n\2", t)
        t = re.sub(r"(\}\)\);)\s+(\+\s)", r"\1\n\2", t)
        t = re.sub(r"(;)\s+(-\s)", r";\n\2", t)
        t = re.sub(r"(;)\s+(\+\s)", r";\n\2", t)
        t = re.sub(r"(})\s+(-\s)", r"}\n\2", t)
        t = re.sub(r"(})\s+(\+\s)", r"}\n\2", t)
        t = re.sub(r"(])\s+(-\s)", r"]\n\2", t)
        t = re.sub(r"(])\s+(\+\s)", r"]\n\2", t)
        if t == before:
            break
    # Second minus/plus line glued after first: "- foo - bar", "+ x + y"
    t = re.sub(r"(-[^\n]+?)\s+(-\s)", r"\1\n\2", t)
    t = re.sub(r"(\+[^\n]+?)\s+(\+\s)", r"\1\n\2", t)
    return _trim_glued_tail_after_plus_line(t)


def _trim_glued_tail_after_plus_line(text: str) -> str:
    """
    LLMs sometimes paste the next statement onto a '+' line, e.g.
    `+ return Left(...); } on DioException catch ...` — truncate before `);` when followed by `} on`.
    """
    lines = text.splitlines()
    out: list[str] = []
    for line in lines:
        if line.startswith("+"):
            last = None
            for m in re.finditer(r"\);(?=\s+\}\s+on\b)", line):
                last = m
            if last is not None:
                line = line[: last.end()]
        out.append(line)
    return "\n".join(out)


def _repair_unified_diff_hunk_counts(text: str) -> str:
    """
    Rewrite @@ hunk headers so old/new line counts match the hunk body.
    LLMs often emit wrong counts (e.g. +68,5 with only four '+' lines), which makes `git apply` fail with "corrupt patch".
    """
    lines = text.splitlines()
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = _RE_UNIFIED_HUNK_HEADER.match(line)
        if not m:
            out.append(line)
            i += 1
            continue
        old_start = int(m.group(1))
        new_start = int(m.group(3))
        j = i + 1
        body: list[str] = []
        while j < len(lines):
            L = lines[j]
            if not L:
                break
            c0 = L[0]
            if c0 in (" ", "+", "-"):
                body.append(L)
                j += 1
                continue
            if c0 == "\\" and "No newline" in L:
                body.append(L)
                j += 1
                continue
            break
        old_count = sum(1 for L in body if L[0] in (" ", "-"))
        new_count = sum(1 for L in body if L[0] in (" ", "+"))
        out.append(f"@@ -{old_start},{old_count} +{new_start},{new_count} @@")
        out.extend(body)
        i = j
    return "\n".join(out)


def _parse_hunk_body(lines: list[str], start: int) -> tuple[list[str], int]:
    body: list[str] = []
    j = start
    while j < len(lines):
        L = lines[j]
        if not L:
            break
        c0 = L[0]
        if c0 in (" ", "+", "-"):
            body.append(L)
            j += 1
            continue
        if c0 == "\\" and "No newline" in L:
            body.append(L)
            j += 1
            continue
        break
    return body, j


def _repair_overlapping_hunks(text: str) -> str:
    """
    Fix consecutive hunks that overlap on the same old-file line range.

    LLMs often emit hunk1 covering lines 1-5 and hunk2 starting again at line 5
    (shared blank line). ``git apply`` then fails with "patch does not apply".
    """
    lines = text.splitlines()
    out: list[str] = []
    i = 0
    prev_old_end = 0
    prev_new_end = 0
    in_file = False

    while i < len(lines):
        line = lines[i]
        if line.startswith("diff --git ") or line.startswith("--- "):
            in_file = True
            prev_old_end = 0
            prev_new_end = 0
            out.append(line)
            i += 1
            continue

        m = _RE_UNIFIED_HUNK_HEADER.match(line)
        if not m or not in_file:
            out.append(line)
            i += 1
            continue

        old_start = int(m.group(1))
        new_start = int(m.group(3))
        body, j = _parse_hunk_body(lines, i + 1)

        # Drop leading context-only lines that overlap the previous hunk.
        while (
            prev_old_end > 0
            and old_start < prev_old_end
            and body
            and body[0].startswith(" ")
        ):
            body = body[1:]
            old_start += 1
            new_start += 1

        if prev_old_end > 0 and old_start < prev_old_end:
            # Still overlaps (edits collide) — force start after previous hunk.
            shift = prev_old_end - old_start
            old_start = prev_old_end
            new_start = prev_new_end
            # Drop that many leading context lines if present.
            dropped = 0
            while dropped < shift and body and body[0].startswith(" "):
                body = body[1:]
                dropped += 1

        old_count = sum(1 for L in body if L and L[0] in (" ", "-"))
        new_count = sum(1 for L in body if L and L[0] in (" ", "+"))
        if old_count == 0 and new_count == 0:
            i = j
            continue

        out.append(f"@@ -{old_start},{old_count} +{new_start},{new_count} @@")
        out.extend(body)
        prev_old_end = old_start + old_count
        prev_new_end = new_start + new_count
        i = j

    return "\n".join(out) + ("\n" if text.endswith("\n") else "")


class GitService:
    def __init__(self, repo_root: str, *, repo_key: str | None = None) -> None:
        if not repo_root or not str(repo_root).strip():
            raise ValueError("repo_root is required")
        self.repo_root = str(repo_root).strip()
        self._repo_key = (repo_key or "").strip() or None
        self._gitlab_project: str | None = None
        self._gitlab_server_url: str | None = None
        self._gitlab_token: str | None = None
        self._gitlab_verify_ssl: str | None = None
        self._gitlab_ssl_ca_bundle: str | None = None
        if self._repo_key:
            from app.services.settings_resolver import SettingsResolver

            gl = SettingsResolver().effective_gitlab(repo_key=self._repo_key)
            self._gitlab_project = (gl.project or "").strip() or None
            self._gitlab_server_url = (gl.server_url or "").strip() or None
            self._gitlab_token = (gl.token or "").strip() or None
            self._gitlab_verify_ssl = (gl.verify_ssl or "").strip() or None
            self._gitlab_ssl_ca_bundle = (gl.ca_bundle or "").strip() or None

    # -----------------------------
    # Low-level git helpers
    # -----------------------------

    def _run_git(self, args: list[str]) -> str:
        cmd = ["git", *args]
        return subprocess.check_output(cmd, cwd=self.repo_root, text=True, stderr=subprocess.STDOUT)

    def _run_git_no_check(self, args: list[str]) -> tuple[int, str]:
        cmd = ["git", *args]
        proc = subprocess.run(
            cmd,
            cwd=self.repo_root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
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
        base = (self._gitlab_server_url or GITLAB_SERVER_URL or "").strip()
        if not base:
            raise RuntimeError(
                "Missing GitLab server URL. Set GITLAB_SERVER_URL in Settings, "
                "or ensure the repo remote URL includes the GitLab host "
                "(e.g. https://gitlab.example.com/group/project)."
            )
        base = base.rstrip("/")
        if base.endswith("/api/v4"):
            return base
        return f"{base}/api/v4"

    def _gitlab_project_id(self) -> str:
        project = (self._gitlab_project or GITLAB_PROJECT or "").strip()
        if not project:
            raise RuntimeError(
                "Missing GitLab project path. Set GITLAB_PROJECT (namespace/project) "
                "or add a repo whose remote URL is a GitLab project path."
            )
        return urllib.parse.quote(project, safe="")

    def _gitlab_headers(self) -> dict[str, str]:
        token = (self._gitlab_token or GITLAB_TOKEN or "").strip()
        if not token:
            raise RuntimeError("Missing GitLab token. Set GITLAB_TOKEN.")
        return {
            "PRIVATE-TOKEN": token,
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

    def _gitlab_ssl_context(self) -> ssl.SSLContext | None:
        verify_raw = self._gitlab_verify_ssl if self._gitlab_verify_ssl is not None else GITLAB_VERIFY_SSL
        verify = self._parse_bool(verify_raw, default=True)
        ca_bundle = self._gitlab_ssl_ca_bundle or GITLAB_SSL_CA_BUNDLE
        if verify:
            if ca_bundle:
                return ssl.create_default_context(cafile=ca_bundle)
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
        file_path = file if os.path.isabs(file) else os.path.join(self.repo_root, file)
        cmd = ["git", "blame", "-L", f"{line},{line}", file_path]
        return subprocess.check_output(cmd, cwd=self.repo_root, text=True, stderr=subprocess.STDOUT)

    def get_recent_commits(self, file: str, limit: int = 5) -> list[dict[str, str]]:
        file_path = file if os.path.isabs(file) else os.path.join(self.repo_root, file)
        cmd = ["git", "log", "-n", "5", "--pretty=format:%h|%an|%s|%ad", "--date=short", file_path]
        output = subprocess.check_output(cmd, cwd=self.repo_root, text=True, stderr=subprocess.STDOUT)

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
        abs_path = path if os.path.isabs(path) else os.path.join(self.repo_root, path)
        with open(abs_path, "r", encoding="utf-8") as f:
            return f.read()

    # -----------------------------
    # Branch / PR workflow
    # -----------------------------

    def git_fetch(self):
        cmd = ["git", "fetch"]
        subprocess.check_output(cmd, cwd=self.repo_root, text=True, stderr=subprocess.STDOUT)

    def create_branch_from_main(
        self,
        jira_ticket_id: str,
        title: str,
        *,
        base_branch: str | None = None,
    ) -> dict[str, str]:
        if not jira_ticket_id or not jira_ticket_id.strip():
            raise ValueError("jira_ticket_id is required")
        if not title or not title.strip():
            raise ValueError("title is required")

        jira = jira_ticket_id.strip().upper()
        slug = self._slugify_title(title, jira_issue_id=jira)
        branch_name = f"ai-bugfix/{jira}-{slug}"
        # Prefer the repo's configured ref (e.g. uat) over global MAIN_BRANCH.
        base = (base_branch or "").strip() or (MAIN_BRANCH or "main").strip() or "main"

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
                self._run_git(["checkout", "--force", "-B", base, origin_base])
            except subprocess.CalledProcessError as e:
                raise RuntimeError(
                    f"Failed to reset {base!r} to {origin_base!r}.\n\n{e.output}"
                ) from e
        else:
            try:
                self._run_git(["checkout", "--force", "-B", base, origin_base])
            except subprocess.CalledProcessError as e:
                raise RuntimeError(
                    f"Failed to create {base!r} from {origin_base!r}. "
                    f"Confirm the remote branch exists.\n\n{e.output}"
                ) from e

        # 3) Create feature branch from updated base
        try:
            self._run_git(["checkout", "-B", branch_name])
        except subprocess.CalledProcessError as e:
            raise RuntimeError(
                f"Failed to create branch {branch_name!r}.\n\n{e.output}"
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
        - Un-flattens diffs where --- / +++ / @@ / hunk rows were glued without newlines
        - Fixes @@ hunk line counts when they disagree with the hunk body (common LLM mistake)
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
        text = _unflatten_llm_unified_diff(text)
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

        text = _repair_unified_diff_hunk_counts(text)
        text = _repair_overlapping_hunks(text)
        text = _repair_unified_diff_hunk_counts(text)
        if text and not text.endswith("\n"):
            text += "\n"
        return text

    def apply_unified_diff(self, diff_text: str) -> None:
        diff_text = self._normalize_diff_text(diff_text)
        if not self._looks_like_unified_diff(diff_text):
            raise ValueError("Input does not look like a unified diff (expected 'diff --git' or '---' / '+++').")

        tmp_path: str | None = None
        try:
            with tempfile.NamedTemporaryFile("w", delete=False, dir=self.repo_root, suffix=".diff") as fp:
                fp.write(diff_text)
                tmp_path = fp.name

            def try_apply(args: list[str]) -> tuple[int, str]:
                return self._run_git_no_check([*args, tmp_path])

            attempts: list[list[str]] = [
                ["apply", "--whitespace=fix", "-p1"],
                ["apply", "--whitespace=fix", "--3way", "-p1"],
                ["apply", "--whitespace=nowarn", "-p1"],
                ["apply", "--whitespace=fix"],
            ]
            errors: list[str] = []
            applied = False
            for args in attempts:
                code, out = try_apply(args)
                if code == 0:
                    applied = True
                    break
                errors.append(f"$ git {' '.join(args)} …\n{out.strip()}")

            if not applied:
                raise RuntimeError(
                    "Failed to apply diff via git apply.\n\n" + "\n\n".join(errors)
                )
        finally:
            if tmp_path:
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass

        status = self._run_git(["status", "--porcelain"]).strip()
        if not status:
            raise RuntimeError("Diff applied cleanly but produced no working tree changes.")

    def commit_changes(self, message: str, paths: list[str] | None = None) -> None:
        """
        Stage and commit only the fix-related paths (no `git add -A`).
        With `paths`, runs `git add -- <paths>`. With an empty list, falls back to `git add -u`
        (tracked modifications only — use when `paths` is unknown but the tree is otherwise clean).
        """
        if not message or not message.strip():
            raise ValueError("commit message is required")
        msg = message.strip()

        spec = list(dict.fromkeys(p.strip() for p in (paths or []) if p and str(p).strip()))
        if spec:
            self._run_git(["add", "--", *spec])
        else:
            self._run_git(["add", "-u"])

        status = self._run_git(["status", "--porcelain"]).strip()
        if not status:
            raise RuntimeError("No changes to commit after staging.")

        try:
            self._run_git(["commit", "-m", msg])
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
                "labels": "AI_CrashFix",
            },
        )

        return {
            "pr_title": normalized_title,
            "pr_url": response.get("web_url") or "",
        }

    def find_open_merge_request(self, source_branch: str) -> dict[str, Any] | None:
        if not source_branch or not source_branch.strip():
            raise ValueError("source_branch is required")

        project_id = self._gitlab_project_id()
        response = self._gitlab_request(
            "GET",
            f"/projects/{project_id}/merge_requests",
            params={"source_branch": source_branch.strip(), "state": "opened"},
        )
        if isinstance(response, list) and response:
            return response[0]
        return None

    def update_merge_request(
        self,
        mr_iid: int | str,
        *,
        title: str | None = None,
        description: str | None = None,
        state_event: str | None = None,
    ) -> dict[str, Any]:
        if not mr_iid:
            raise ValueError("mr_iid is required")

        payload: dict[str, Any] = {}
        if title is not None and title.strip():
            payload["title"] = title.strip()
        if description is not None:
            payload["description"] = description.strip()
        if state_event is not None and state_event.strip():
            payload["state_event"] = state_event.strip()
        if not payload:
            raise ValueError("At least one of title, description, or state_event is required")

        project_id = self._gitlab_project_id()
        return self._gitlab_request(
            "PUT",
            f"/projects/{project_id}/merge_requests/{mr_iid}",
            json_data=payload,
        )

    def close_merge_request(self, mr_iid: int | str, *, comment: str | None = None) -> dict[str, Any]:
        """Close an open MR, optionally leaving a note explaining why first."""
        if not mr_iid:
            raise ValueError("mr_iid is required")
        if comment and comment.strip():
            project_id = self._gitlab_project_id()
            self._gitlab_request(
                "POST",
                f"/projects/{project_id}/merge_requests/{mr_iid}/notes",
                json_data={"body": comment.strip()},
            )
        return self.update_merge_request(mr_iid, state_event="close")

    def checkout_existing_branch(self, branch_name: str) -> None:
        if not branch_name or not branch_name.strip():
            raise ValueError("branch_name is required")
        branch = branch_name.strip()

        self.git_fetch()
        origin_branch = f"origin/{branch}"
        try:
            self._run_git(["checkout", "--force", "-B", branch, origin_branch])
        except subprocess.CalledProcessError as e:
            raise RuntimeError(
                f"Failed to checkout existing branch {branch!r} from {origin_branch!r}. "
                f"Confirm the remote branch still exists.\n\n{e.output}"
            ) from e