from app.graph.state import CrashState

def enhance_fix_node(state: CrashState):
    state["fix_iteration_count"] = state.get("fix_iteration_count", 0) + 1
    state.setdefault("fix_max_iterations", 3)
    return state