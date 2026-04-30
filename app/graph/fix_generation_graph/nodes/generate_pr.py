from app.graph.state import CrashState
from app.services.git_service import GitService

def generate_pr_node(state: CrashState):
    # LangGraph nodes must return a dict update (state), not a routing string.
    # Treat PR creation as "best effort": record errors in state and continue.
    state.pop("pr_error", None)

    if not state.get("final_fix"):
        state["pr_title"] = state.get("pr_title") or "No fix generated"
        state["pr_body"] = state.get("pr_body") or "No fix generated"
        state["pr_error"] = "Missing final_fix; skipping PR creation."
        return state

    jira_issue_id = state.get("jira_issue_id")
    if not jira_issue_id:
        state["pr_error"] = "Missing jira_issue_id; skipping PR creation."
        return state

    try:
        git_service = GitService()
        pr_title = state.get("pr_title") or "CrashLens fix"
        pr_body = state.get("pr_body") or ""

        # 1) Create branch from main
        branch_info = git_service.create_branch_from_main(jira_ticket_id=jira_issue_id, title=pr_title)
        state["pr_branch"] = branch_info.get("branch")

        # 2) Apply the final fix into the working tree
        git_service.apply_unified_diff(state.get("final_fix") or "")

        # 3) Commit + push the fix
        commit_msg = f"{jira_issue_id.strip().upper()}: {pr_title.strip()}"
        git_service.commit_all(commit_msg)
        git_service.push_current_branch(branch_name=state["pr_branch"])

        # 4) Create PR (GitLab merge request) after pushed commit exists
        mr = git_service.create_merge_request(
            source_branch=state["pr_branch"],
            target_branch=branch_info.get("base") or "main",
            title=commit_msg,
            body=pr_body,
            draft=True,
        )
        state["pr_url"] = mr.get("pr_url")
    except Exception as e:
        state["pr_error"] = str(e)

    return state