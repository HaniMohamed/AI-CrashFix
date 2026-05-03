from app.graph.state import CrashState
from app.services.crash_store import CrashStore

crash_store = CrashStore()


def validate_fix_node(state: CrashState):
    approved = bool(state.get("fix_review_approved"))
    required_changes = state.get("fix_required_changes") or []
    has_required_changes = len(required_changes) > 0

    state["fix_validation_result"] = bool(approved and not has_required_changes)
    cid = state.get("crash_id")
    if cid and state["fix_validation_result"]:
        crash_store.set_pipeline_flags(cid, fix_validated=True)
    return state