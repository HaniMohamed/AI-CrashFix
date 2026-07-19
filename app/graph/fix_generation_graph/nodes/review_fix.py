from app.graph.state import CrashState
from app.services.ai_service import LLMService
from app.utils.llm_helpers import parse_json_object
from app.prompts.review_fix_prompts import SYSTEM_PROMPT, USER_PROMPT
from app.utils.prompt_budget import compact_crash_prompt_input

def review_fix_node(state: CrashState):
    if not state.get("generated_fix"):
        state["fix_review_approved"] = False
        state["fix_review_feedback"] = "No generated fix found to review."
        state["fix_required_changes"] = ["Generate a fix proposal before review."]
        return state

    llm = LLMService()

    def compact_input(_state: CrashState, level: int):
        return compact_crash_prompt_input(_state, level, include_previous_fix=True)

    try:
        response = llm.call_with_prompt_budget(
            system_prompt=SYSTEM_PROMPT(),
            build_user_prompt=USER_PROMPT,
            prompt_input=state,
            compact_input=compact_input,
        )
        parsed = parse_json_object(response, context="review_fix")
    except (ValueError, TypeError) as exc:
        state["fix_review_approved"] = False
        state["fix_review_feedback"] = f"Reviewer output was not a valid JSON object: {exc}"
        state["fix_required_changes"] = ["Re-run generate_fix with a clearer unified diff."]
        state["fix_review_questions"] = []
        return state

    approved = parsed.get("approved", False)
    state["fix_review_approved"] = bool(approved)
    state["fix_review_feedback"] = parsed.get("feedback") or parsed.get("summary") or ""
    required = parsed.get("required_changes", []) or []
    state["fix_required_changes"] = required if isinstance(required, list) else [str(required)]
    questions = parsed.get("questions", []) or []
    state["fix_review_questions"] = questions if isinstance(questions, list) else [str(questions)]

    # Prefer reviewer risk + tests if provided (merge with existing).
    state["fix_risk"] = parsed.get("risk") or state.get("fix_risk", "")
    suggested_tests = parsed.get("suggested_tests", []) or []
    if not isinstance(suggested_tests, list):
        suggested_tests = [str(suggested_tests)]
    existing_tests = state.get("fix_tests", []) or []
    if not isinstance(existing_tests, list):
        existing_tests = [str(existing_tests)]
    state["fix_tests"] = list(dict.fromkeys([*existing_tests, *suggested_tests]))

    return state
