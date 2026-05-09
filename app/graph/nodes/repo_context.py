import subprocess

from app.services.git_service import GitService
from app.services.repo_service import RepoService
from app.utils.analysis import detect_risk_signals

def repo_context(state):
    from app import config as cfg

    repo_root = (state.get("repo_root") or cfg.REPO_ROOT or "").strip()
    git = GitService(repo_root=repo_root)
    repo = RepoService(repo_root=repo_root)

    enriched = []
    kept_frames = []

    for frame in state["mapped_frames"]:
        file = frame["file"]
        line = frame["line"]

        # If blame fails, this frame likely doesn't map to a repo-tracked source file.
        # Drop it to avoid crashing and to prevent enriching the wrong file.
        try:
            blame = git.get_blame(file, line)
        except subprocess.CalledProcessError:
            continue

        # 1. Code context
        code = repo.get_file_context(file, line, radius=30)

        # 3. Recent commits affecting file
        try:
            commits = git.get_recent_commits(file)
        except subprocess.CalledProcessError:
            commits = []

        # 4. Extract method boundaries (important upgrade)
        method_block = repo.extract_method(file, line)

        # 5. Risk analysis
        risks = detect_risk_signals(code)

        kept_frames.append(frame)
        enriched.append({
            "file": file,
            "line": line,
            "method_block": method_block,
            "code_snippet": code,
            "git_blame": blame,
            "recent_commits": commits,
            "risk_signals": risks
        })

    state["mapped_frames"] = kept_frames
    state["repo_context"] = enriched
    return state