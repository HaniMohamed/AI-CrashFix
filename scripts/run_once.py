from app.graph.graph_builder import build_graph

graph = build_graph()

initial_state = {
    "crash_id": "test",
    "exception": "",
    "stacktrace": [],
    "mapped_frames": [],
    "repo_context": {},
    "root_cause": "",
    "confidence": 0.0,
    "fix_suggestion": "",
    "jira_payload": None
}

result = graph.invoke(initial_state)
print(result)