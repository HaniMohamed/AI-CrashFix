from app.graph.state import CrashState
from app.prompts.pr_fix_prompts import PR_SYSTEM_PROMPT, PR_FIX_PROMPT_INPUT
from app.services.ai_service import LLMService
from app.prompts.prepare_diff_prompts import PREPARE_DIFF_SYSTEM_PROMPT, PREPARE_DIFF_USER_PROMPT
from app.services.git_service import GitService
from app.utils.llm_helpers import parse_json

def finalize_fix_node(state: CrashState):
    # This node may be re-entered by the graph runtime in some edge cases.
    # Make it idempotent to avoid double LLM calls / duplicate debug stops.
    if state.get("fix_ready") and state.get("generated_diff") and state.get("pr_title") and state.get("pr_body"):
        return state

    fix_proposal = (state.get("generated_fix") or "").strip()
    if not fix_proposal:
        state["generated_diff"] = "insufficient evidence"
        state["fix_ready"] = False
        state["pr_title"] = state.get("pr_title") or "No fix generated"
        state["pr_body"] = state.get("pr_body") or "No fix generated"
        return state

    impacted_files = state.get("fix_impacted_files") or []
    current_files: list[dict[str, str]] = []
    git = GitService()
    for p in impacted_files[:5]:
        try:
            current_files.append({"path": p, "content": git.read_repo_file(p)})
        except Exception:
            continue

    llm = LLMService()
    response = llm.call(
        system_prompt=PREPARE_DIFF_SYSTEM_PROMPT(),
        user_prompt=PREPARE_DIFF_USER_PROMPT(
            fix_proposal=fix_proposal,
            impacted_files=impacted_files,
            current_files=current_files,
        ),
    )
    parsed = parse_json(response)

    diff_text = (parsed.get("fix") or "").strip()
    state["generated_diff"] = diff_text
    state["fix_impacted_files"] = parsed.get("impacted_files") or impacted_files
    state["fix_ready"] = bool(diff_text and diff_text != "insufficient evidence")


    return state