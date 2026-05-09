from app.graph.state import CrashState

from app.prompts.fix_generation_prompts import SYSTEM_PROMPT, USER_PROMPT
from app.services.ai_service import LLMService
from app.services.crash_store import CrashStore
from app.utils.fix_json import fix_corrupted_json
from app.utils.llm_helpers import parse_json

def _normalize_unified_diff_fix(fix: str | None) -> str | None:
    """Strip accidental markdown fences from the JSON 'fix' field."""
    if fix is None:
        return None
    t = fix.strip()
    if not t or t.lower() == "insufficient evidence":
        return t if t else None
    if t.startswith("```"):
        first_nl = t.find("\n")
        if first_nl != -1:
            t = t[first_nl + 1 :]
        t = t.rstrip()
        if t.endswith("```"):
            t = t[:-3].rstrip()
    return t.strip() or None


def _impacted_files_from_unified_diff(diff: str) -> list[str]:
    """Best-effort paths from +++ b/ or diff --git lines when the model omits impacted_files."""
    paths: list[str] = []
    seen: set[str] = set()
    for line in diff.splitlines():
        if line.startswith("+++ b/") and "/dev/null" not in line:
            rest = line[6:].strip()
            path = rest.split("\t", 1)[0].strip()
            if path and path not in seen:
                seen.add(path)
                paths.append(path)
        elif line.startswith("diff --git "):
            parts = line.split()
            if len(parts) >= 4 and parts[3].startswith("b/"):
                path = parts[3][2:]
                if path and path != "/dev/null" and path not in seen:
                    seen.add(path)
                    paths.append(path)
    return paths


def generate_fix_node(state: CrashState):
    llm = LLMService()
    response = llm.call(
        system_prompt=SYSTEM_PROMPT(),
        user_prompt=USER_PROMPT(state)
    )
    cleaned_response = fix_corrupted_json(response)
    parsed = parse_json(cleaned_response)
    raw_fix = parsed.get("fix")
    normalized = _normalize_unified_diff_fix(raw_fix) if isinstance(raw_fix, str) else None
    state["generated_fix"] = normalized

    impacted = parsed.get("impacted_files") or []
    if not isinstance(impacted, list):
        impacted = []
    if not impacted and normalized and normalized.lower() != "insufficient evidence":
        impacted = _impacted_files_from_unified_diff(normalized)
    state["fix_impacted_files"] = impacted
    state["fix_rationale"] = parsed.get("rationale", "")
    state["fix_risk"] = parsed.get("risk", "")
    state["fix_tests"] = parsed.get("tests", [])
    state["fix_iteration_count"] = state.get("fix_iteration_count", 0) + 1
    state.setdefault("fix_max_iterations", 3)

    cid = state.get("crash_id")
    if cid and normalized and str(normalized).lower() != "insufficient evidence":
        repo_key = (state.get("repo_key") or "").strip() or None
        CrashStore(repo_key=repo_key).set_pipeline_flags(cid, fix_generated=True)

    return state