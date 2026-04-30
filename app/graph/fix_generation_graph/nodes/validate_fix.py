from app.graph.state import CrashState

def validate_fix_node(state: CrashState):
    approved = bool(state.get("fix_review_approved"))
    required_changes = state.get("fix_required_changes") or []
    has_required_changes = len(required_changes) > 0

    state["fix_validation_result"] = bool(approved and not has_required_changes)
    return state