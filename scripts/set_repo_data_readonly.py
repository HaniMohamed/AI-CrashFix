#!/usr/bin/env python3
"""Set REPO_DATA_READONLY in app_settings for the current user."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from app.services.app_settings_store import AppSettingsStore
from app.services.repo_data_guard import SETTINGS_KEY_REPO_DATA_READONLY, is_repo_data_readonly
from app.services.user_context import resolve_user_id


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "value",
        choices=("true", "false", "on", "off", "1", "0"),
        help="Enable or disable repo-data read-only mode",
    )
    args = parser.parse_args()

    enabled = args.value.lower() in ("true", "on", "1")
    user_id = resolve_user_id(required=False)
    if user_id:
        print(f"user_id={user_id}")

    AppSettingsStore().set(k=SETTINGS_KEY_REPO_DATA_READONLY, v=enabled)
    print(f"REPO_DATA_READONLY={enabled} (verified={is_repo_data_readonly()})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
