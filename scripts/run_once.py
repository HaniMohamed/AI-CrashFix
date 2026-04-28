from app.graph.graph_builder import build_graph
from pprint import pprint

graph = build_graph()

initial_state = {
    "crash_id": "",
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
pprint(result, sort_dicts=False, width=120)