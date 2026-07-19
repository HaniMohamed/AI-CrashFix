from app.services.ai_service import LLMService
from app.services.crash_store import CrashStore

from app.prompts.prompts import SYSTEM_PROMPT, USER_PROMPT
from app.utils.llm_helpers import parse_json_object
from app.utils.prompt_budget import compact_analysis_prompt_input


def llm_analysis(state):
    llm = LLMService()

    def compact_input(_state, level: int):
        return compact_analysis_prompt_input(_state, level)

    response = llm.call_with_prompt_budget(
        system_prompt=SYSTEM_PROMPT(),
        build_user_prompt=USER_PROMPT,
        prompt_input=state,
        compact_input=compact_input,
    )

    parsed = parse_json_object(response, context="llm_analysis")

    state["root_cause"] = parsed["root_cause"]
    state["confidence"] = parsed["confidence"]
    state["fix_suggestion"] = parsed["fix_suggestion"]
    state["llm_explanation"] = parsed["explanation"]

    cid = state.get("crash_id")
    if cid:
        repo_key = (state.get("repo_key") or "").strip() or None
        fpid = (state.get("firebase_project_id") or "").strip() or None
        CrashStore(repo_key=repo_key, project_id=fpid).set_pipeline_flags(cid, analysis_done=True)

    return state
