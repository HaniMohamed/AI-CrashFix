from langgraph.graph import StateGraph, END
from app.graph.state import CrashState

from app.graph.nodes.map_stacktrace import map_stacktrace
from app.graph.nodes.repo_context import repo_context
from app.graph.nodes.llm_analysis import llm_analysis
from app.graph.nodes.jira_create import jira_create
from app.graph.nodes.git_regression import git_regression
from app.services.crash_store import CrashStore
from app.graph.observability import instrument_node, instrument_router

crash_store = CrashStore()

def build_graph():
    graph = StateGraph(CrashState)

    graph.add_node("map_stacktrace", instrument_node("map_stacktrace", map_stacktrace))
    graph.add_node("repo_context", instrument_node("repo_context", repo_context))
    graph.add_node("git_regression", instrument_node("git_regression", git_regression))
    graph.add_node("llm_analysis", instrument_node("llm_analysis", llm_analysis))
    graph.add_node("jira_create", instrument_node("jira_create", jira_create))

    graph.set_entry_point("map_stacktrace")


    graph.add_edge("map_stacktrace", "repo_context")
    graph.add_edge("repo_context", "git_regression")
    graph.add_edge("git_regression", "llm_analysis")

    graph.add_conditional_edges(
        "llm_analysis",
        instrument_router(
            "route_after_llm_analysis",
            lambda state: "jira_create" if state["confidence"] > 0.7 else END,
        ),
    )


    return graph.compile()