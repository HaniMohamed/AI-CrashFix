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
    fix_impacted_files: List[str] = []
    fix_rationale: str = ""
    fix_risk: str = ""
    fix_tests: List[str] = []
    fix_review_feedback: Optional[str] = None
    fix_review_approved: Optional[bool] = None
    fix_required_changes: List[str] = []
    fix_review_questions: List[str] = []
    fix_validation_result: Optional[bool] = None
    fix_iteration_count: int = 0
    fix_max_iterations: int = 3

    final_fix: Optional[str] = None
    fix_ready: Optional[bool] = None

    # PR generation state
    pr_title: Optional[str] = None
    pr_body: Optional[str] = None