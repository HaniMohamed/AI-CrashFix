from __future__ import annotations

from app.services.jira_service import (
    append_mr_block_to_description,
    get_jira_issue,
    transition_jira_issue,
    update_jira_issue_description,
)


def jira_update(state):
    """After MR creation: append MR link to Jira description and transition to Done."""
    state["jira_update_error"] = None

    if state.get("skip_jira_creation"):
        return state

    issue_key = str(state.get("jira_issue_id") or "").strip()
    pr_url = str(state.get("pr_url") or "").strip()
    if not issue_key or not pr_url:
        return state

    repo_key = (state.get("repo_key") or "").strip() or None
    mock = bool(state.get("mock"))
    pr_branch = str(state.get("pr_branch") or "").strip() or None

    try:
        issue = get_jira_issue(
            issue_key,
            fields="description,status",
            mock=mock,
            repo_key=repo_key,
        )
        fields = issue.get("fields") if isinstance(issue, dict) else {}
        if not isinstance(fields, dict):
            fields = {}
        current_desc = fields.get("description")
        new_desc, changed = append_mr_block_to_description(
            current_desc,
            pr_url=pr_url,
            pr_branch=pr_branch,
        )
        if changed:
            update_jira_issue_description(
                issue_key,
                new_desc,
                mock=mock,
                repo_key=repo_key,
            )

        transition_jira_issue(
            issue_key,
            "Done",
            mock=mock,
            repo_key=repo_key,
        )
    except Exception as exc:  # noqa: BLE001 — best-effort; do not fail the run
        state["jira_update_error"] = str(exc)

    return state
