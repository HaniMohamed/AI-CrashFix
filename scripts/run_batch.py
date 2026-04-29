from __future__ import annotations

import argparse
import sys
from pathlib import Path
from pprint import pprint
from typing import Any

# Allow running as `python scripts/run_batch.py` without installing the package.
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from app.graph.graph_builder import build_graph
from app.services.crash_store import CrashStore
from app.services.crashlytics_service import CrashlyticsService
from app.graph.observability import node_span, ensure_run_id


def _initial_state_for_crash(
    crash: dict[str, Any], *, run_id: str, skip_jira_creation: bool
) -> dict[str, Any]:
    return {
        "graph_run_id": run_id,
        "skip_jira_creation": bool(skip_jira_creation),
        "crash_id": crash.get("crash_id") or "",
        "exception": crash.get("exception") or "",
        "stacktrace": crash.get("stacktrace") or [],
        "app_version": crash.get("app_version"),
        "device": crash.get("device"),
        "platform": crash.get("platform"),
        "mapped_frames": [],
        "repo_context": {},
        "root_cause": "",
        "confidence": 0.0,
        "fix_suggestion": "",
        "jira_payload": None,
        "jira_issue_id": None,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch N recent crashes and process each via the CrashLens graph.")
    parser.add_argument("--limit", type=int, default=10, help="How many recent crashes to fetch from Crashlytics/BigQuery.")
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Use mocked crash list (no BigQuery).",
    )
    parser.add_argument("--print-results", action="store_true", help="Pretty-print each final state.")
    parser.add_argument("--skip-jira-creation", action="store_true", help="Skip Jira creation.", default=False)
    args = parser.parse_args()

    graph = build_graph()
    crash_store = CrashStore()
    service = CrashlyticsService()

    batch_state: dict[str, Any] = {}
    run_id = ensure_run_id(batch_state)

    with node_span(batch_state, "batch.fetch", extra={"limit": args.limit, "mock": args.mock}):
        crashes = (
            service.fetch_recent_crashes_mock(limit=args.limit)
            if args.mock
            else service.fetch_recent_crashes(limit=args.limit)
        ) or []

    if not crashes:
        raise SystemExit("No crashes found")

    processed = 0
    skipped = 0
    failed = 0

    for crash in crashes:
        crash_id = crash.get("crash_id")
        if not crash_id:
            continue

        if crash_store.is_processed(crash_id):
            skipped += 1
            with node_span(
                {"graph_run_id": run_id, "crash_id": crash_id},
                "batch.skip",
                extra={"reason": "already_processed"},
            ):
                pass
            continue

        crash_store.insert_crash(crash_id)
        state = _initial_state_for_crash(
            crash, run_id=run_id, skip_jira_creation=args.skip_jira_creation
        )

        try:
            with node_span(state, "batch.process_crash"):
                result = graph.invoke(state)
            processed += 1

            if args.print_results:
                pprint(result, sort_dicts=False, width=120)

            crash_store.update_result(crash_id, result)
        except Exception:
            failed += 1
            # node_span already logged the error; keep moving to next crash.
            continue

    with node_span(
        batch_state,
        "batch.summary",
        extra={"fetched": len(crashes), "processed": processed, "skipped": skipped, "failed": failed},
    ):
        pass

    print(f"Processed={processed} Skipped={skipped} Failed={failed} Fetched={len(crashes)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

