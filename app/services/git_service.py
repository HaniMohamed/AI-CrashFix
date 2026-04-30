import subprocess
import os

from app.config import REPO_ROOT, MAIN_BRANCH

class GitService:

    def _run_git(self, args: list[str]) -> str:
        cmd = ["git", *args]
        return subprocess.check_output(cmd, cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT)

    def _slugify_title(self, title: str, max_len: int = 50) -> str:
        s = title.strip().lower()
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
        slug = self._slugify_title(title)
        branch_name = f"bugfix/{jira}-{slug}"
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

        # 5) Create PR (requires GitHub CLI)
        pr_title = f"{jira}: {title.strip()}"
        pr_body = (body or "").strip()
        gh_cmd = [
            "gh",
            "pr",
            "create",
            "--base",
            base,
            "--head",
            branch_name,
            "--title",
            pr_title,
            "--body",
            pr_body,
        ]
        if draft:
            gh_cmd.append("--draft")

        try:
            out = subprocess.check_output(gh_cmd, cwd=REPO_ROOT, text=True, stderr=subprocess.STDOUT).strip()
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Failed to create PR via GitHub CLI.\n\n{e.output}") from e

        # `gh pr create` usually prints the PR URL on success.
        return {
            "base": base,
            "branch": branch_name,
            "pr_title": pr_title,
            "pr_url": out,
        }
    