from app.utils.git_analysis_helpers import find_top_commit, RISK_KEYWORDS


def git_regression(state):
    enriched = []

    for frame in state["repo_context"]:
        commits = frame.get("recent_commits", [])

        top_commit = find_top_commit(commits)

        regression_score = 0.0

        if top_commit:
            regression_score += 0.4

            if any(k in top_commit["message"].lower() for k in RISK_KEYWORDS):
                regression_score += 0.4

        regression_score = min(regression_score, 1.0)

        enriched.append({
            **frame,
            "likely_introducing_commit": top_commit,
            "regression_score": regression_score,
            "is_recent_change_related": regression_score > 0.6
        })

    state["repo_context"] = enriched
    return state