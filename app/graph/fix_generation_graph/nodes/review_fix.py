from app.graph.state import CrashState
from app.services.ai_service import LLMService
from app.utils.llm_helpers import parse_json
from app.prompts.review_fix_prompts import SYSTEM_PROMPT, USER_PROMPT

def review_fix_node(state: CrashState):
    if not state.get("generated_fix"):
        state["fix_review_approved"] = False
        state["fix_review_feedback"] = "No generated fix found to review."
        state["fix_required_changes"] = ["Generate a fix proposal before review."]
        return state

    llm = LLMService()
    response = llm.call(
        system_prompt=SYSTEM_PROMPT(),
        user_prompt=USER_PROMPT(state),
    )
    parsed = parse_json(response)

    approved = parsed.get("approved", False)
    state["fix_review_approved"] = bool(approved)
    state["fix_review_feedback"] = parsed.get("feedback") or parsed.get("summary") or ""
    state["fix_required_changes"] = parsed.get("required_changes", []) or []
    state["fix_review_questions"] = parsed.get("questions", []) or []

    # Prefer reviewer risk + tests if provided (merge with existing).
    state["fix_risk"] = parsed.get("risk") or state.get("fix_risk", "")
    suggested_tests = parsed.get("suggested_tests", []) or []
    existing_tests = state.get("fix_tests", []) or []
    state["fix_tests"] = list(dict.fromkeys([*existing_tests, *suggested_tests]))

    return state