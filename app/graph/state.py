from __future__ import annotations

from typing import Any, TypedDict


class CrashState(TypedDict, total=False):
    graph_run_id: str
    graph_run_start_time: str
    graph_run_end_time: str

    graph_error: str | None

    # Terminal pipeline classification that's not an error (e.g. "skipped").
    pipeline_status: str | None
    pipeline_note: str | None

    
    mock: bool
    skip_jira_creation: bool
    crash_id: str
    exception: str
    stacktrace: list[dict[str, Any]]

    # Target repository for this run (cloned from a user-provided remote URL).
    repo_root: str | None
    repo_url: str | None
    repo_ref: str | None
    repo_key: str | None

    app_version: str | None
    device: str | None
    platform: str | None
    # Bundle id / package from Crashlytics export; used for Firebase Console links.
    app_identifier: str | None
    # e.g. ``android:com.example.app`` or ``ios:com.example.app``
    crashlytics_console_app_id: str | None

    mapped_frames: list[dict[str, Any]]
    repo_context: dict[str, Any]

    root_cause: str
    confidence: float
    fix_suggestion: str

    jira_payload: dict[str, Any] | None

    jira_issue_id: str | None

    # Fix generation state
    generated_fix: str | None
    fix_impacted_files: list[str]
    fix_rationale: str
    fix_risk: str
    fix_tests: list[str]
    fix_review_feedback: str | None
    fix_review_approved: bool | None
    fix_required_changes: list[str]
    fix_review_questions: list[str]
    fix_validation_result: bool | None
    fix_iteration_count: int
    fix_max_iterations: int

    generated_diff: str | None
    commit_message: str | None
    fix_ready: bool | None

    # PR generation state
    pr_title: str | None
    pr_body: str | None
    pr_url: str | None
    pr_branch: str | None
    pr_error: str | None