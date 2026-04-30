from typing import TypedDict, List, Dict, Optional

class CrashState(TypedDict):
    graph_run_id: Optional[str]
    skip_jira_creation: Optional[bool]
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



    # Fix generation state
    generated_fix: Optional[str] = None
    review_feedback: Optional[str] = None
    validation_result: Optional[bool] = None
    iteration_count: int = 0
    max_iterations: int = 3

    final_fix: Optional[str] = None
    fix_ready: bool = False
    needs_manual_review: bool = False