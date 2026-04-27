import subprocess

class GitService:

    def get_blame(self, file, line):
        cmd = f"git blame -L {line},{line} {file}"
        return subprocess.getoutput(cmd)

    def get_recent_commits(self, file):
        cmd = f"git log -n 5 --pretty=format:'%h|%an|%s|%ad' --date=short {file}"
        output = subprocess.getoutput(cmd)

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
        cmd = f"git log -1 -- {file}"
        return bool(subprocess.getoutput(cmd))