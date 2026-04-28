 
from app.services.jira_service import create_jira_issue
from app.services.crash_store import CrashStore

crash_store = CrashStore()

def jira_create(state):
    summary = state.get("summary")
    description = state.get("description")
    project_key = state.get("project_key")
    issue_type = state.get("issue_type")
    issue = create_jira_issue(summary, description, project_key, issue_type)
    state["jira_issue_id"] = issue.get("id")
    if state["jira_issue_id"]:
        crash_store.mark_processed(state["crash_id"], state["jira_issue_id"])
    return state