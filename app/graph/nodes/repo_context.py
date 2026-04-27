from app.services.git_service import GitService
from app.services.repo_service import RepoService

git_service = GitService()
repo_service = RepoService()

def repo_context(state):
    context = []

    for frame in state["mapped_frames"]:
        file = frame["file"]
        line = frame["line"]

        code = repo_service.get_file_context(file, line)
        blame = git_service.get_blame(file, line)
        commits = git_service.get_recent_commits(file)

        context.append({
            "file": file,
            "line": line,
            "code": code,
            "blame": blame,
            "commits": commits
        })

    state["repo_context"] = context
    return state