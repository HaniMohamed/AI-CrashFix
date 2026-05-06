from app.graph.state import CrashState

# Prefix for `graph_error` when fix/review/validate exhausts retries; runner uses
# it to choose CRASH_FAILED `error.type`.
FIX_VALIDATION_EXHAUSTED_PREFIX = "fix_validation_exhausted:"


def fallback_node(state: CrashState):
    if state.get("graph_error"):
        return state

    feedback = (state.get("fix_review_feedback") or "").strip()
    changes = state.get("fix_required_changes") or []
    if not isinstance(changes, list):
        changes = []

    detail = feedback
    if not detail and changes:
        detail = "; ".join(str(c) for c in changes if str(c).strip())
    if not detail:
        detail = "Fix did not pass validation after maximum iterations."

    state["graph_error"] = f"{FIX_VALIDATION_EXHAUSTED_PREFIX} {detail}"
    return state
