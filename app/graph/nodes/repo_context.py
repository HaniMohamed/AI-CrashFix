from app.services.git_service import GitService
from app.services.repo_service import RepoService
from app.utils.analysis import detect_risk_signals

git = GitService()
repo = RepoService()


def repo_context(state):
    enriched = []

    for frame in state["mapped_frames"]:
        file = frame["file"]
        line = frame["line"]

        # 1. Code context
        code = repo.get_file_context(file, line, radius=30)

        # 2. Git blame
        blame = git.get_blame(file, line)

        # 3. Recent commits affecting file
        commits = git.get_recent_commits(file)

        # 4. Extract method boundaries (important upgrade)
        method_block = repo.extract_method(file, line)

        # 5. Risk analysis
        risks = detect_risk_signals(code)

        enriched.append({
            "file": file,
            "line": line,
            "method_block": method_block,
            "code_snippet": code,
            "git_blame": blame,
            "recent_commits": commits,
            "risk_signals": risks
        })

    state["repo_context"] = enriched
    return state