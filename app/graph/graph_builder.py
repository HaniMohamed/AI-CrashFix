from langgraph.graph import StateGraph, END
from app.graph.state import CrashState

from app.graph.nodes.fetch_crash import fetch_crash
from app.graph.nodes.map_stacktrace import map_stacktrace
from app.graph.nodes.repo_context import repo_context
from app.graph.nodes.git_analysis import git_analysis
from app.graph.nodes.llm_analysis import llm_analysis
from app.graph.nodes.fix_generation import fix_generation
from app.graph.nodes.jira_create import jira_create
from app.graph.nodes.git_regression import git_regression

def build_graph():
    graph = StateGraph(CrashState)

    graph.add_node("fetch_crash", fetch_crash)
    graph.add_node("map_stacktrace", map_stacktrace)
    graph.add_node("repo_context", repo_context)
    graph.add_node("git_analysis", git_analysis)
    graph.add_node("git_regression", git_regression)
    graph.add_node("llm_analysis", llm_analysis)
    graph.add_node("fix_generation", fix_generation)
    graph.add_node("jira_create", jira_create)

    graph.set_entry_point("fetch_crash")

    graph.add_edge("fetch_crash", "map_stacktrace")
    graph.add_edge("map_stacktrace", "repo_context")
    graph.add_edge("repo_context", "git_analysis")
    graph.add_edge("git_analysis", "git_regression")
    graph.add_edge("git_regression", "llm_analysis")
    graph.add_edge("llm_analysis", "fix_generation")

    graph.add_conditional_edges(
        "fix_generation",
        lambda state: "jira_create" if state["confidence"] > 0.7 else END
    )

    return graph.compile()