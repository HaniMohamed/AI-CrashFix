import subprocess
import os

from app.config import REPO_ROOT

class GitService:

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