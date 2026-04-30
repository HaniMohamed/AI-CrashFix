from langgraph.graph import StateGraph, END


from app.graph.fix_generation_graph.nodes.generate_fix import generate_fix_node
from app.graph.fix_generation_graph.nodes.review_fix import review_fix_node
from app.graph.fix_generation_graph.nodes.validate_fix import validate_fix_node
from app.graph.fix_generation_graph.nodes.enhance_fix import enhance_fix_node
from app.graph.fix_generation_graph.nodes.finalize_fix import finalize_fix_node
from app.graph.fix_generation_graph.nodes.generate_pr import generate_pr_node
from app.graph.fix_generation_graph.nodes.fallback import fallback_node
from app.graph.observability import instrument_node, instrument_router
from app.graph.state import CrashState

def build_fix_subgraph():
    fix_graph = StateGraph(CrashState)

    # Indented names so subgraph logs read as "nested" under the parent graph step.
    log_prefix = "-------"
    fix_graph.add_node("generate_fix", instrument_node(f"{log_prefix}generate_fix", generate_fix_node))
    fix_graph.add_node("review_fix", instrument_node(f"{log_prefix}review_fix", review_fix_node))
    fix_graph.add_node("validate_fix", instrument_node(f"{log_prefix}validate_fix", validate_fix_node))
    fix_graph.add_node("enhance_fix", instrument_node(f"{log_prefix}enhance_fix", enhance_fix_node))
    fix_graph.add_node("finalize_fix", instrument_node(f"{log_prefix}finalize_fix", finalize_fix_node))
    fix_graph.add_node("generate_pr", instrument_node(f"{log_prefix}generate_pr", generate_pr_node))
    fix_graph.add_node("fallback", instrument_node(f"{log_prefix}fallback", fallback_node))

    fix_graph.set_entry_point("generate_fix")

    fix_graph.add_edge("generate_fix", "review_fix")
    fix_graph.add_edge("review_fix", "validate_fix")

    fix_graph.add_conditional_edges(
        "validate_fix",
        instrument_router(
            f"{log_prefix}route_after_validate_fix",
            lambda state: (
                "valid"
                if state.get("fix_validation_result")
                else (
                    "fail"
                    if state.get("fix_iteration_count", 0) >= state.get("fix_max_iterations", 3)
                    else "retry"
                )
            ),
        ),
        {
            "valid": "finalize_fix",
            "retry": "enhance_fix",
            "fail": "fallback",
        },
    )

    fix_graph.add_edge("enhance_fix", "review_fix")
    fix_graph.add_edge("finalize_fix", "generate_pr")
    fix_graph.add_edge("generate_pr", END)
    fix_graph.add_edge("fallback", END)

    return fix_graph.compile()