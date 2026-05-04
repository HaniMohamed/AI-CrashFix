"""Aggregated analytics computed over the SQLite crash store.

Used by `GET /api/analytics`. Pure-Python; no schema migration. The dataset is
small (one project, hundreds of crashes), so a single-pass scan is plenty.

Cached for 5 seconds in-process to avoid hammering SQLite when the dashboard
polls or the user clicks refresh repeatedly.
"""

from __future__ import annotations

import time
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Tuple

from app.services.crash_store import CrashStore


_FUNNEL_COLUMNS: Tuple[str, ...] = (
    "analysis_done",
    "jira_created",
    "fix_generated",
    "fix_validated",
    "diff_applied",
    "branch_created",
    "mr_created",
)

# Five-second TTL cache keyed by db path.
_CACHE: Dict[str, Tuple[float, Dict[str, Any]]] = {}
_CACHE_TTL_SECONDS = 5.0


def _parse_iso(value: Any) -> datetime | None:
    if not value or not isinstance(value, str):
        return None
    try:
        # Stored timestamps are naive UTC isoformat from `datetime.utcnow().isoformat()`.
        return datetime.fromisoformat(value)
    except Exception:
        return None


def _device_key(value: Any) -> str | None:
    if not value:
        return None
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        for key in ("model", "name", "manufacturer", "id"):
            v = value.get(key)
            if isinstance(v, str) and v:
                return v
        return None
    return str(value)


def compute_analytics(store: CrashStore, *, use_cache: bool = True) -> Dict[str, Any]:
    """Return the aggregated dashboard payload."""
    cache_key = store.db_path
    now = time.monotonic()

    if use_cache:
        cached = _CACHE.get(cache_key)
        if cached and (now - cached[0]) < _CACHE_TTL_SECONDS:
            return cached[1]

    status_counter: Counter[str] = Counter()
    funnel: Dict[str, int] = {col: 0 for col in _FUNNEL_COLUMNS}
    pipeline_complete_count = 0
    with_jira = 0
    with_pr = 0
    duration_sum = 0.0
    duration_n = 0

    timeseries_created: Dict[str, int] = defaultdict(int)
    timeseries_completed: Dict[str, int] = defaultdict(int)
    timeseries_failed: Dict[str, int] = defaultdict(int)

    platforms: Counter[str] = Counter()
    app_versions: Counter[str] = Counter()
    devices: Counter[str] = Counter()

    total = 0
    for row, parsed in store.iter_all_results():
        total += 1
        status = (row.get("status") or "pending") or "pending"
        status_counter[status] += 1

        if row.get("pipeline_complete"):
            pipeline_complete_count += 1
        for col in _FUNNEL_COLUMNS:
            if row.get(col):
                funnel[col] += 1

        if row.get("jira_issue_id"):
            with_jira += 1
        if row.get("pr_url"):
            with_pr += 1

        created = _parse_iso(row.get("created_at"))
        updated = _parse_iso(row.get("updated_at"))

        if created and updated and row.get("pipeline_complete"):
            duration_sum += max(0.0, (updated - created).total_seconds())
            duration_n += 1

        if created:
            timeseries_created[created.date().isoformat()] += 1
        if updated and row.get("pipeline_complete"):
            timeseries_completed[updated.date().isoformat()] += 1
        if status == "failed" and updated:
            timeseries_failed[updated.date().isoformat()] += 1

        if parsed:
            platform = parsed.get("platform")
            if isinstance(platform, str) and platform:
                platforms[platform] += 1
            version = parsed.get("app_version")
            if isinstance(version, str) and version:
                app_versions[version] += 1
            device = _device_key(parsed.get("device"))
            if device:
                devices[device] += 1

    today = datetime.now(timezone.utc).date()
    timeseries: List[Dict[str, Any]] = []
    for i in range(29, -1, -1):
        d = (today - timedelta(days=i)).isoformat()
        timeseries.append(
            {
                "date": d,
                "created": timeseries_created.get(d, 0),
                "completed": timeseries_completed.get(d, 0),
                "failed": timeseries_failed.get(d, 0),
            }
        )

    completion_rate = (pipeline_complete_count / total) if total else 0.0
    step_success_rate = {
        col: ((funnel[col] / total) if total else 0.0) for col in _FUNNEL_COLUMNS
    }
    avg_duration = (duration_sum / duration_n) if duration_n else 0.0

    recent = store.list_crashes(limit=10, include_result=False)

    payload: Dict[str, Any] = {
        "totals": {
            "all": total,
            "completed": status_counter.get("completed", 0),
            "in_progress": status_counter.get("in_progress", 0),
            "pending": status_counter.get("pending", 0),
            "failed": status_counter.get("failed", 0),
            "with_jira": with_jira,
            "with_pr": with_pr,
            "pipeline_complete": pipeline_complete_count,
        },
        "pipeline_funnel": funnel,
        "step_success_rate": step_success_rate,
        "completion_rate": completion_rate,
        "avg_pipeline_duration_seconds": avg_duration,
        "timeseries_daily": timeseries,
        "top_platforms": [
            {"key": k, "count": v} for k, v in platforms.most_common(10)
        ],
        "top_app_versions": [
            {"key": k, "count": v} for k, v in app_versions.most_common(10)
        ],
        "top_devices": [{"key": k, "count": v} for k, v in devices.most_common(10)],
        "recent": recent,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }

    _CACHE[cache_key] = (now, payload)
    return payload
