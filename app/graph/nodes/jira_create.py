 
from app.services.jira_service import create_jira_issue

def jira_create(state):
    summary = state.get("summary")
    description = state.get("description")
    project_key = state.get("project_key")
    issue_type = state.get("issue_type")
    issue = create_jira_issue(summary, description, project_key, issue_type)
    state["jira_issue_id"] = issue.get("id")
    return state