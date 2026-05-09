from app.services.ai_service import LLMService
from app.services.crash_store import CrashStore

from app.prompts.prompts import SYSTEM_PROMPT, USER_PROMPT
from app.utils.llm_helpers import parse_json, extract_top_commits

llm = LLMService()


def llm_analysis(state):
    prompt_input = {
        "mapped_frames": state["mapped_frames"],
        "repo_context": state["repo_context"],
        "regression_analysis": state["repo_context"],
        "top_commits": extract_top_commits(state["repo_context"])
    }

    response = llm.call(
        system_prompt=SYSTEM_PROMPT(),
        user_prompt=USER_PROMPT(prompt_input)
    )

    parsed = parse_json(response)

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