from langgraph.graph import StateGraph, END
from app.graph.state import CrashState
from app.graph.fix_generation_graph.fix_generation_graph import build_fix_subgraph
from app.graph.nodes.map_stacktrace import map_stacktrace
from app.graph.nodes.repo_context import repo_context
from app.graph.nodes.llm_analysis import llm_analysis
from app.graph.nodes.jira_create import jira_create
from app.graph.nodes.git_regression import git_regression
from app.graph.observability import instrument_node, instrument_router


def build_graph():
    graph = StateGraph(CrashState)
   

    graph.add_node("map_stacktrace", instrument_node("map_stacktrace", map_stacktrace))
    graph.add_node("repo_context", instrument_node("repo_context", repo_context))
    graph.add_node("git_regression", instrument_node("git_regression", git_regression))
    graph.add_node("llm_analysis", instrument_node("llm_analysis", llm_analysis))
    graph.add_node("jira_create", instrument_node("jira_create", jira_create))

    # Fix generation subgraph
    fix_subgraph = build_fix_subgraph()
    graph.add_node(
        "fix_generation",
        instrument_node("fix_generation", lambda state: fix_subgraph.invoke(state)),
    )

    graph.set_entry_point("map_stacktrace")
    graph.add_edge("map_stacktrace", "repo_context")
    graph.add_edge("repo_context", "git_regression")
    graph.add_edge("git_regression", "llm_analysis")

    graph.add_conditional_edges(
        "llm_analysis",
        instrument_router(
            "route_after_llm_analysis",
            lambda state: (
                "fix_generation"
                if state.get("skip_jira_creation")
                else "jira_create"
            ),
        ),
    )

    # If Jira created → then generate fix
    graph.add_edge("jira_create", "fix_generation")

    # After fix generation → always END
    graph.add_edge("fix_generation", END)

    return graph.compile()