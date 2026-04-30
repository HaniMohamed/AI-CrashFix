from app.graph.state import CrashState
from app.services.git_service import GitService

def generate_pr_node(state: CrashState):
    if not state.get("final_fix"):
        state["pr_title"] = "No fix generated"
        state["pr_body"] = "No fix generated"
        return "fallback"
    else:
        try:
            git_service = GitService()
            git_service.create_branch_and_pr_from_main(
                jira_ticket_id=state["jira_issue_id"],
                draft=True,
                title=state["pr_title"],
                body=state["pr_body"],
            )
        except Exception as e:
            return "fallback"
        return state