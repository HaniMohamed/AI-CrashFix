from __future__ import annotations

import json
from typing import Any, Literal

PIPELINE_FLAG_COLUMNS = (
    "analysis_done",
    "jira_created",
    "fix_generated",
    "fix_validated",
    "diff_applied",
    "branch_created",
    "mr_created",
    "pipeline_complete",
)

FEEDBACK_COLUMNS = (
    "feedback_iteration_count",
    "feedback_locked",
)

RESTART_COLUMNS = ("restart_count",)


def row_to_dict(row: Any, *, include_result: bool) -> dict:
    all_columns = (
        "crash_id",
        "jira_issue_id",
        "pr_url",
        "status",
        "created_at",
        "updated_at",
        "created_by_user_id",
        *PIPELINE_FLAG_COLUMNS,
        *FEEDBACK_COLUMNS,
        *RESTART_COLUMNS,
    )
    if hasattr(row, "keys"):
        out = {k: row[k] for k in all_columns if k in row.keys()}
    else:
        out = dict(row)
    for col in PIPELINE_FLAG_COLUMNS:
        if col in out:
            out[col] = bool(out[col])
    if "feedback_locked" in out:
        out["feedback_locked"] = bool(out["feedback_locked"])
    if "feedback_iteration_count" in out and out["feedback_iteration_count"] is None:
        out["feedback_iteration_count"] = 0
    if "restart_count" in out and out["restart_count"] is None:
        out["restart_count"] = 0
    if "created_by_user_id" in out:
        raw_uid = out["created_by_user_id"]
        if raw_uid is None:
            out["created_by_user_id"] = None
        else:
            s = str(raw_uid).strip()
            out["created_by_user_id"] = s or None
    if include_result and "result" in row.keys():
        raw = row["result"]
        if raw is None:
            out["result"] = None
        elif isinstance(raw, dict):
            out["result"] = raw
        elif isinstance(raw, str):
            if raw:
                try:
                    out["result"] = json.loads(raw)
                except Exception:
                    out["result"] = raw
            else:
                out["result"] = None
        else:
            out["result"] = raw
    for col in ("created_at", "updated_at"):
        if col in out and out[col] is not None and not isinstance(out[col], str):
            try:
                out[col] = out[col].isoformat()
            except Exception:
                out[col] = str(out[col])
    return out


def recompute_pipeline_complete(
    conn: Any,
    crash_id: str,
    *,
    now_iso: str,
    dialect: Literal["sqlite", "postgres"],
    project_id: str | None = None,
) -> None:
    flag_cols = ", ".join(c for c in PIPELINE_FLAG_COLUMNS if c != "pipeline_complete")
    if dialect == "postgres":
        row = conn.execute(
            f"""
            SELECT {flag_cols}, status
            FROM crashes
            WHERE firebase_project_id = %s AND crash_id = %s
            """,
            (project_id, crash_id),
        ).fetchone()
    else:
        row = conn.execute(
            f"""
            SELECT {flag_cols}, status
            FROM crashes WHERE crash_id = ?
            """,
            (crash_id,),
        ).fetchone()

    if not row:
        return

    if isinstance(row, dict):
        analysis_done = row["analysis_done"]
        fix_generated = row["fix_generated"]
        fix_validated = row["fix_validated"]
        diff_applied = row["diff_applied"]
        branch_created = row["branch_created"]
        mr_created = row["mr_created"]
        existing_status = row["status"]
    else:
        (
            analysis_done,
            _jira_created,
            fix_generated,
            fix_validated,
            diff_applied,
            branch_created,
            mr_created,
            existing_status,
        ) = row
    complete = bool(
        analysis_done
        and fix_generated
        and fix_validated
        and diff_applied
        and branch_created
        and mr_created
    )
    existing = str(existing_status or "").lower()
    status = (
        "completed"
        if complete
        else (
            "failed"
            if existing == "failed"
            else ("skipped" if existing == "skipped" else "in_progress")
        )
    )
    if dialect == "postgres":
        conn.execute(
            """
            UPDATE crashes
            SET pipeline_complete = %s, status = %s, updated_at = %s
            WHERE firebase_project_id = %s AND crash_id = %s
            """,
            (complete, status, now_iso, project_id, crash_id),
        )
    else:
        conn.execute(
            """
            UPDATE crashes
            SET pipeline_complete = ?, status = ?, updated_at = ?
            WHERE crash_id = ?
            """,
            (int(complete), status, now_iso, crash_id),
        )
