from typing import TypedDict, List, Dict, Optional

class CrashState(TypedDict):
    crash_id: str
    exception: str
    stacktrace: List[Dict]

    mapped_frames: List[Dict]
    repo_context: Dict

    root_cause: str
    confidence: float
    fix_suggestion: str

    jira_payload: Optional[Dict]