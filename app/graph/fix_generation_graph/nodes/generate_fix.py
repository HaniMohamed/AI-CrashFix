from app.graph.state import CrashState

from app.prompts.fix_generation_prompts import SYSTEM_PROMPT, USER_PROMPT
from app.services.ai_service import LLMService
from app.utils.llm_helpers import parse_json

def generate_fix_node(state: CrashState):
    llm = LLMService()
    response = llm.call(
        system_prompt=SYSTEM_PROMPT(),
        user_prompt=USER_PROMPT(state)
    )
    parsed = parse_json(response)
    state["generated_fix"] = parsed.get("fix", None)
    state["fix_impacted_files"] = parsed.get("impacted_files", [])
    state["fix_rationale"] = parsed.get("rationale", "")
    state["fix_risk"] = parsed.get("risk", "")
    state["fix_tests"] = parsed.get("tests", [])
    state["fix_iteration_count"] = state.get("fix_iteration_count", 0) + 1
    state.setdefault("fix_max_iterations", 3)
    return state