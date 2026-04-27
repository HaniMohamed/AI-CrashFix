import os
from app.services.git_service import GitService
from app.services.repo_service import RepoService

git_service = GitService()
repo_service = RepoService()

REPO_ROOT = os.getcwd()
def repo_context(state):
    context = []

    for frame in state["mapped_frames"]:
        file = frame["file"]
        line = frame["line"]

        code = repo_service.get_file_context(os.path.join(REPO_ROOT, file), line)
        blame = git_service.get_blame(os.path.join(REPO_ROOT, file), line)
        commits = git_service.get_recent_commits(os.path.join(REPO_ROOT, file))

        context.append({
            "file": os.path.join(REPO_ROOT, file),
            "line": line,
            "code": code,
            "blame": blame,
            "commits": commits
        })

    state["repo_context"] = context
    return state