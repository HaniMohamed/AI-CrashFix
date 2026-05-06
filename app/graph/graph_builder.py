from langgraph.graph import StateGraph, END
from app.graph.state import CrashState
from app.graph.nodes.map_stacktrace import map_stacktrace
from app.graph.nodes.repo_context import repo_context
from app.graph.nodes.llm_analysis import llm_analysis
from app.graph.nodes.jira_create import jira_create
from app.graph.nodes.git_regression import git_regression
from app.graph.fix_generation_graph.nodes.generate_fix import generate_fix_node
from app.graph.fix_generation_graph.nodes.review_fix import review_fix_node
from app.graph.fix_generation_graph.nodes.validate_fix import validate_fix_node
from app.graph.fix_generation_graph.nodes.generate_pr import generate_pr_node
from app.graph.fix_generation_graph.nodes.fallback import fallback_node
from app.graph.observability import instrument_node, instrument_router


def build_graph():
    graph = StateGraph(CrashState)
   

    graph.add_node("map_stacktrace", instrument_node("map_stacktrace", map_stacktrace))
    graph.add_node("repo_context", instrument_node("repo_context", repo_context))
    graph.add_node("git_regression", instrument_node("git_regression", git_regression))
    graph.add_node("llm_analysis", instrument_node("llm_analysis", llm_analysis))
    graph.add_node("jira_create", instrument_node("jira_create", jira_create))
    graph.add_node(
        "mark_skipped_no_mapped_frames",
        instrument_node(
            "mark_skipped_no_mapped_frames",
            lambda state: {
                **state,
                "pipeline_status": "skipped",
                "pipeline_note": "No mapped stack frames; cannot map crash to repository files.",
            },
        ),
    )

    # Inline fix-generation nodes so `graph.stream(stream_mode="values")` yields
    # state snapshots after each step (generate/review/validate/retry).
    graph.add_node("generate_fix", instrument_node("generate_fix", generate_fix_node))
    graph.add_node("review_fix", instrument_node("review_fix", review_fix_node))
    graph.add_node("validate_fix", instrument_node("validate_fix", validate_fix_node))
    graph.add_node("generate_pr", instrument_node("generate_pr", generate_pr_node))
    graph.add_node("fallback", instrument_node("fallback", fallback_node))

    graph.set_entry_point("map_stacktrace")

    graph.add_conditional_edges(
        "map_stacktrace",
        instrument_router("route_after_map_stacktrace",
        lambda state: "repo_context" if state.get("mapped_frames") else "mark_skipped_no_mapped_frames"))

    graph.add_edge("mark_skipped_no_mapped_frames", END)

    graph.add_edge("repo_context", "git_regression")
    graph.add_edge("git_regression", "llm_analysis")

    graph.add_conditional_edges(
        "llm_analysis",
        instrument_router(
            "route_after_llm_analysis",
            lambda state: (
                "generate_fix"
                if state.get("skip_jira_creation")
                else "jira_create"
            ),
        ),
    )

    # If Jira created → then generate fix
    graph.add_edge("jira_create", "generate_fix")

    # Fix flow
    graph.add_edge("generate_fix", "review_fix")
    graph.add_edge("review_fix", "validate_fix")
    graph.add_conditional_edges(
        "validate_fix",
        instrument_router(
            "route_after_validate_fix",
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
            "valid": "generate_pr",
            "retry": "generate_fix",
            "fail": "fallback",
        },
    )

    graph.add_edge("generate_pr", END)
    graph.add_edge("fallback", END)

    return graph.compile()