from app.graph.state import CrashState
from app.prompts.pr_fix_prompts import PR_SYSTEM_PROMPT, PR_FIX_PROMPT_INPUT
from app.services.ai_service import LLMService
from app.utils.llm_helpers import parse_json

def finalize_fix_node(state: CrashState):
    # This node may be re-entered by the graph runtime in some edge cases.
    # Make it idempotent to avoid double LLM calls / duplicate debug stops.
    if state.get("fix_ready") and state.get("pr_title") and state.get("pr_body"):
        return state

    state["final_fix"] = state["generated_fix"]
    state["fix_ready"] = True

    llm = LLMService()
    response = llm.call(
        system_prompt=PR_SYSTEM_PROMPT(),
        user_prompt=PR_FIX_PROMPT_INPUT(state),
    )
    parsed = parse_json(response)
    state["pr_title"] = parsed["pr_title"]
    state["pr_body"] = parsed["pr_body"]
    return state