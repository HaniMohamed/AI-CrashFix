from typing import TypedDict, List, Optional, Dict

class CrashState(TypedDict):
    crash_id: str
    exception: str
    stacktrace: List[Dict]

    mapped_frames: List[Dict]   # file, line, method
    repo_context: Dict          # code snippets, blame, commits

    root_cause: str
    confidence: float

    fix_suggestion: str

    jira_payload: Optional[Dict]