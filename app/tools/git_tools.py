import subprocess

class GitService:

    def get_blame(self, file, line):
        cmd = f"git blame -L {line},{line} {file}"
        return subprocess.getoutput(cmd)

    def get_recent_commits(self, file):
        cmd = f"git log -n 5 --pretty=format:'%h - %an - %s' {file}"
        return subprocess.getoutput(cmd)