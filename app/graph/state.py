from typing import TypedDict, List, Dict, Optional

class CrashState(TypedDict):
    crash_id: str
    exception: str
    stacktrace: List[Dict]

    app_version: str
    device: str
    platform: str

    mapped_frames: List[Dict]
    repo_context: Dict

    root_cause: str
    confidence: float
    fix_suggestion: str

    jira_payload: Optional[Dict]

    jira_issue_id: Optional[str]