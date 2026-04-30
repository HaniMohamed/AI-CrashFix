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
        result = git_service.create_branch_and_pr_from_main(
            jira_ticket_id=jira_issue_id,
            draft=True,
            title=state.get("pr_title") or "CrashLens fix",
            body=state.get("pr_body") or "",
        )
        state["pr_url"] = result.get("pr_url")
        state["pr_branch"] = result.get("branch")
    except Exception as e:
        state["pr_error"] = str(e)

    return state