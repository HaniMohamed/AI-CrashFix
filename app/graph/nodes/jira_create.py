 
from app.services.jira_service import create_jira_issue
from app.services.crash_store import CrashStore

crash_store = CrashStore()

def jira_create(state):
    crash_id = state.get("crash_id")
    exception = state.get("exception")
    platform = state.get("platform")
    app_version = state.get("app_version")
    device = state.get("device")

    summary = state.get("summary") or f"[CrashLens] {exception or crash_id or 'Crash'}"

    if state.get("description"):
        description = state.get("description")
    else:
        stack_lines = state.get("stacktrace") or []
        stack_preview = "\n".join(stack_lines[:50]) if isinstance(stack_lines, list) else str(stack_lines)

        mapped = state.get("mapped_frames") or []
        mapped_preview = "\n".join(
            f'- {f.get("file")}:{f.get("line")} ({f.get("type")})'
            for f in mapped
            if isinstance(f, dict)
        )

        root_cause = state.get("root_cause")
        fix = state.get("fix_suggestion")
        llm_expl = state.get("llm_explanation")

        description = "\n".join(
            [
                f"Crash ID: {crash_id}",
                f"Exception: {exception}",
                f"Platform: {platform}",
                f"App version: {app_version}",
                f"Device: {device}",
                "",
                "### Analysis",
                f"Root cause: {root_cause}",
                f"Fix suggestion: {fix}",
                f"LLM explanation: {llm_expl}",
                "",
                "### Mapped frames",
                mapped_preview or "(none)",
                "",
                "### Stacktrace (first 50 lines)",
                stack_preview or "(empty)",
            ]
        ).strip()

    project_key = state.get("project_key")
    issue_type = state.get("issue_type") or "Bug"
    issue = create_jira_issue(summary, description, project_key, issue_type)
    state["jira_issue_id"] = issue.get("id")
    if state["jira_issue_id"]:
        crash_store.mark_processed(state["crash_id"], state["jira_issue_id"])
    return state