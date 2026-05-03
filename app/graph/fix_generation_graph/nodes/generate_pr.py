from app.graph.state import CrashState
from app.prompts.pr_fix_prompts import PR_FIX_PROMPT_INPUT, PR_SYSTEM_PROMPT
from app.services.ai_service import LLMService
from app.services.git_service import GitService
from app.utils.llm_helpers import parse_json


def generate_pr_node(state: CrashState):
    """
    Best-effort: new branch from main → apply `generated_fix` unified diff → commit → push → draft MR.
    Errors are stored in `pr_error`; the graph still completes.
    """
    state.pop("pr_error", None)

    patch = (state.get("generated_fix") or "").strip()
    if not patch or patch.lower() == "insufficient evidence":
        state["pr_title"] = state.get("pr_title") or "No fix generated"
        state["pr_body"] = state.get("pr_body") or "No fix generated"
        state["pr_error"] = "Missing or insufficient generated_fix; skipping PR creation."
        return state

    jira_issue_id = state.get("jira_issue_id")
    if not jira_issue_id or not str(jira_issue_id).strip():
        state["pr_error"] = "Missing jira_issue_id; skipping PR creation."
        return state

    try:
        llm = LLMService()
        pr_meta = parse_json(
            llm.call(
                system_prompt=PR_SYSTEM_PROMPT(),
                user_prompt=PR_FIX_PROMPT_INPUT(state),
            )
        )
        state["pr_title"] = pr_meta["pr_title"]
        state["pr_body"] = pr_meta["pr_body"]

        pr_title = (state["pr_title"] or "CrashLens fix").strip()
        pr_body = (state["pr_body"] or "").strip()
        jira = str(jira_issue_id).strip().upper()

        git = GitService()
        branch_info = git.create_branch_from_main(jira_ticket_id=jira, title=pr_title)
        branch = branch_info["branch"]
        state["pr_branch"] = branch

        git.apply_unified_diff(patch)

        commit_msg = f"{jira}: {pr_title}"
        git.commit_all(commit_msg)
        git.push_current_branch(branch_name=branch)

        mr = git.create_merge_request(
            source_branch=branch,
            target_branch=branch_info.get("base") or "main",
            title=commit_msg,
            body=pr_body,
            draft=True,
        )
        state["pr_url"] = mr.get("pr_url")
        state["generated_diff"] = patch
    except Exception as e:
        state["pr_error"] = str(e)

    return state
