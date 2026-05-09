from __future__ import annotations

import copy
from typing import Any


def _flooz_wallet_mock_row() -> dict[str, Any]:
    # NOTE: Kept as a standalone builder to avoid editing a huge literal inline.
    # This mock is meant to look like a Dart crash with lib/ paths.
    return {
        "platform": "android",
        "bundle_identifier": "com.example.flooz_wallet",
        "event_id": "mock-event-flooz-0001",
        "is_fatal": True,
        "error_type": "FATAL",
        "issue_id": "issue_flooz_wallet_0001",
        "variant_id": "debug",
        "issue_title": "NoSuchMethodError: The method 'trim' was called on null",
        "issue_subtitle": "Null check / unexpected null in sign-up flow",
        "event_timestamp": "2026-05-09T08:12:30.123Z",
        "received_timestamp": "2026-05-09T08:12:31.456Z",
        "device": {
            "manufacturer": "Google",
            "model": "Pixel 7",
            "architecture": "arm64-v8a",
        },
        "memory": {"used": 223_456_789, "free": 887_654_321},
        "storage": {"used": 2_234_567_890, "free": 8_876_543_210},
        "operating_system": {
            "display_version": "14",
            "name": "Android",
            "modification_state": "unknown",
            "type": "android",
            "device_type": "phone",
        },
        "application": {"build_version": "1", "display_version": "1.0.0"},
        "user": {"name": None, "email": None, "id": "user_flooz_mock_0001"},
        "custom_keys": [
            {"key": "repo", "value": "workspace_projects/flooz_wallet-fb635da5f073"},
            {"key": "screen", "value": "sign_up"},
        ],
        "installation_uuid": "install_flooz_mock_0001",
        "crashlytics_sdk_version": "18.6.0",
        "app_orientation": "portrait",
        "device_orientation": "portrait",
        "process_state": "foreground",
        "logs": [
            {
                "timestamp": "2026-05-09T08:12:28Z",
                "message": "SignUpScreenBloc: NextEvent received",
            }
        ],
        "breadcrumbs": [
            {
                "timestamp": "2026-05-09T08:12:27Z",
                "name": "ui_event",
                "params": [{"key": "message", "value": "User tapped Next on sign up"}],
            }
        ],
        "files": [],
        "blame_frame": {
            "line": 25,
            "file": "lib/app/modules/sign_up_screen/bloc/sign_up_screen_bloc.dart",
            "symbol": "SignUpScreenBloc",
            "offset": 0,
            "address": 0,
            "library": "app",
            "owner": "app",
            "blamed": True,
        },
        "exceptions": [
            {
                "type": "NoSuchMethodError",
                "exception_message": "The method 'trim' was called on null",
                "nested": False,
                "title": "NoSuchMethodError",
                "subtitle": "The method 'trim' was called on null",
                "blamed": True,
                "frames": [
                    {
                        "line": 25,
                        "file": "lib/app/modules/sign_up_screen/bloc/sign_up_screen_bloc.dart",
                        "symbol": "SignUpScreenBloc",
                        "offset": 0,
                        "address": 0,
                        "library": "app",
                        "owner": "app",
                        "blamed": True,
                    },
                    {
                        "line": 9,
                        "file": "lib/app/helpers/validators.dart",
                        "symbol": "Validators.emailValidator",
                        "offset": 0,
                        "address": 0,
                        "library": "app",
                        "owner": "app",
                        "blamed": False,
                    },
                    {
                        "line": 10,
                        "file": "lib/main.dart",
                        "symbol": "main",
                        "offset": 0,
                        "address": 0,
                        "library": "app",
                        "owner": "app",
                        "blamed": False,
                    },
                ],
            }
        ],
        "errors": [],
        "threads": [
            {
                "crashed": True,
                "thread_name": "main",
                "queue_name": "main",
                "signal_name": None,
                "signal_code": None,
                "crash_address": None,
                "title": "main",
                "subtitle": None,
                "blamed": True,
                "frames": [
                    {
                        "line": 25,
                        "file": "lib/app/modules/sign_up_screen/bloc/sign_up_screen_bloc.dart",
                        "symbol": "SignUpScreenBloc",
                        "offset": 0,
                        "address": 0,
                        "library": "app",
                        "owner": "app",
                        "blamed": True,
                    }
                ],
            }
        ],
        "unity_metadata": None,
        "native_crash_info": None,
        "remote_config_feature_rollouts": [],
        "firebase_session_id": "session_flooz_mock_0001",
    }


def _flooz_wallet_mock_row_bare_ast() -> dict[str, Any]:
    """
    Flooz mock that produces a BARE dart frame like:
      #0 Validators.emailValidator (validators.dart:13)
    Intended to resolve via the AST index (resolved_by=dart_ast_index) when the
    active repo contains that symbol.
    """
    r = copy.deepcopy(_flooz_wallet_mock_row())
    r["issue_id"] = "issue_flooz_wallet_0002_bare_ast"
    r["event_id"] = "mock-event-flooz-0002"
    exc0 = (r.get("exceptions") or [])[0]
    frames = exc0.get("frames") or []
    if frames:
        frames[0]["file"] = "validators.dart"
        frames[0]["line"] = 9
        frames[0]["symbol"] = "Validators.emailValidator"
    r["blame_frame"]["file"] = "validators.dart"
    r["blame_frame"]["line"] = 9
    r["blame_frame"]["symbol"] = "Validators.emailValidator"
    return r


def _flooz_wallet_mock_row_bare_legacy() -> dict[str, Any]:
    """
    Flooz mock that should *miss* the AST index lookup (because the symbol string
    contains extra text) and then fall back to legacy glob resolution.

    Produces:
      #0 Validators.emailValidator closure (validators.dart:13)
    """
    r = copy.deepcopy(_flooz_wallet_mock_row_bare_ast())
    r["issue_id"] = "issue_flooz_wallet_0003_bare_legacy"
    r["event_id"] = "mock-event-flooz-0003"
    exc0 = (r.get("exceptions") or [])[0]
    frames = exc0.get("frames") or []
    if frames:
        frames[0]["symbol"] = "Validators.emailValidator closure"
    r["blame_frame"]["symbol"] = "Validators.emailValidator closure"
    return r


def _flooz_wallet_mock_row_package_as_lib() -> dict[str, Any]:
    """
    Flooz mock that produces a package: frame which can be resolved to lib/<path>
    (resolved_by=dart_package_as_lib_path).
    """
    r = copy.deepcopy(_flooz_wallet_mock_row())
    r["issue_id"] = "issue_flooz_wallet_0004_package_as_lib"
    r["event_id"] = "mock-event-flooz-0004"
    exc0 = (r.get("exceptions") or [])[0]
    frames = exc0.get("frames") or []
    if frames:
        frames[0]["file"] = "package:flooz_wallet/app/helpers/validators.dart"
        frames[0]["line"] = 9
        frames[0]["symbol"] = "Validators.emailValidator"
    r["blame_frame"]["file"] = "package:flooz_wallet/app/helpers/validators.dart"
    r["blame_frame"]["line"] = 9
    r["blame_frame"]["symbol"] = "Validators.emailValidator"
    return r


def _flooz_wallet_mock_row_package_local_dir() -> dict[str, Any]:
    """
    Flooz mock that produces a package: frame intended to resolve via a configured
    packages dir (resolved_by=dart_package_local_dir or dart_package_glob_fallback).

    NOTE: This requires the active repo to have packages_dirs configured and to
    contain <packages_dir>/shared_utils/lib/src/formatters.dart (or equivalent).
    """
    r = copy.deepcopy(_flooz_wallet_mock_row())
    r["issue_id"] = "issue_flooz_wallet_0005_package_local_dir"
    r["event_id"] = "mock-event-flooz-0005"
    exc0 = (r.get("exceptions") or [])[0]
    frames = exc0.get("frames") or []
    if frames:
        frames[0]["file"] = "package:shared_utils/src/formatters.dart"
        frames[0]["line"] = 7
        frames[0]["symbol"] = "Formatters.formatPhone"
    r["blame_frame"]["file"] = "package:shared_utils/src/formatters.dart"
    r["blame_frame"]["line"] = 7
    r["blame_frame"]["symbol"] = "Formatters.formatPhone"
    return r


def _taminaty_mock_row(*, idx: int) -> dict[str, Any]:
    issue_id = f"issue_mock_{idx:04d}"
    return {
        "platform": "android",
        "bundle_identifier": "sa.gov.gosi.taminaty",
        "event_id": f"mock-event-{idx:04d}",
        "is_fatal": True,
        "error_type": "FATAL",
        "issue_id": issue_id,
        "variant_id": "variant_mock",
        "issue_title": "TypeError: Null check operator used on a null value",
        "issue_subtitle": "Null check operator used on a null value",
        "event_timestamp": f"2026-04-28T09:12:{30 + (idx % 30):02d}.123Z",
        "received_timestamp": f"2026-04-28T09:12:{35 + (idx % 20):02d}.456Z",
        "device": {
            "manufacturer": "Google",
            "model": "Pixel 7",
            "architecture": "arm64-v8a",
        },
        "memory": {"used": 123_456_789, "free": 987_654_321},
        "storage": {"used": 1_234_567_890, "free": 9_876_543_210},
        "operating_system": {
            "display_version": "14",
            "name": "Android",
            "modification_state": "unknown",
            "type": "android",
            "device_type": "phone",
        },
        "application": {"build_version": "3218", "display_version": "3.2.18"},
        "user": {"name": None, "email": None, "id": f"user_mock_{idx:04d}"},
        "custom_keys": [{"key": "SourceId", "value": "SuperApp"}],
        "installation_uuid": f"install_mock_{idx:04d}",
        "crashlytics_sdk_version": "18.6.0",
        "app_orientation": "portrait",
        "device_orientation": "portrait",
        "process_state": "foreground",
        "logs": [
            {
                "timestamp": "2026-04-28T09:12:19Z",
                "message": "AIEnhanceServiceImpl.enhanceText called (model=iwai-v01)",
            }
        ],
        "breadcrumbs": [
            {
                "timestamp": "2026-04-28T09:12:10Z",
                "name": "ui_event",
                "params": [{"key": "message", "value": "User opened Voice with AI text field"}],
            }
        ],
        "files": [],
        "blame_frame": {
            "line": 69,
            "file": "lib/core/ui/shared_widgets/voice_with_ai_textfield/service/ai_enhance_service.dart",
            "symbol": "AIEnhanceServiceImpl.enhanceText",
            "offset": 0,
            "address": 0,
            "library": "app",
            "owner": "app",
            "blamed": True,
        },
        "exceptions": [
            {
                "type": "_TypeError",
                "exception_message": "Null check operator used on a null value",
                "nested": False,
                "title": "TypeError",
                "subtitle": "Null check operator used on a null value",
                "blamed": True,
                "frames": [
                    {
                        "line": 69,
                        "file": "lib/core/ui/shared_widgets/voice_with_ai_textfield/service/ai_enhance_service.dart",
                        "symbol": "AIEnhanceServiceImpl.enhanceText",
                        "offset": 0,
                        "address": 0,
                        "library": "app",
                        "owner": "app",
                        "blamed": True,
                    },
                    {
                        "line": 141,
                        "file": "lib/core/ui/shared_widgets/voice_with_ai_textfield/controller/voice_with_ai_textfield_controller.dart",
                        "symbol": "VoiceWithAITextFieldController._enhance",
                        "offset": 0,
                        "address": 0,
                        "library": "app",
                        "owner": "app",
                        "blamed": False,
                    },
                ],
            }
        ],
        "errors": [],
        "threads": [
            {
                "crashed": True,
                "thread_name": "main",
                "queue_name": "main",
                "signal_name": None,
                "signal_code": None,
                "crash_address": None,
                "title": "main",
                "subtitle": None,
                "blamed": True,
                "frames": [
                    {
                        "line": 69,
                        "file": "lib/core/ui/shared_widgets/voice_with_ai_textfield/service/ai_enhance_service.dart",
                        "symbol": "AIEnhanceServiceImpl.enhanceText",
                        "offset": 0,
                        "address": 0,
                        "library": "app",
                        "owner": "app",
                        "blamed": True,
                    }
                ],
            }
        ],
        "unity_metadata": None,
        "native_crash_info": None,
        "remote_config_feature_rollouts": [],
        "firebase_session_id": f"session_mock_{idx:04d}",
    }


# Ordered list of concrete mock rows (fixed IDs) that are useful for UI testing.
MOCK_CRASHLYTICS_ROWS: list[dict[str, Any]] = [
    _flooz_wallet_mock_row(),
    _flooz_wallet_mock_row_bare_ast(),
    _flooz_wallet_mock_row_bare_legacy(),
    _flooz_wallet_mock_row_package_as_lib(),
    _flooz_wallet_mock_row_package_local_dir(),
    _taminaty_mock_row(idx=1),  # historical/default sample app id
]


def build_mock_crashlytics_rows(limit: int = 10) -> list[dict[str, Any]]:
    """
    Return mocked Crashlytics/BigQuery-like crash \"rows\".

    If limit exceeds the curated list, additional rows are generated using the
    same Taminaty template with different IDs.
    """
    n = max(0, int(limit))
    out: list[dict[str, Any]] = []
    for i in range(min(n, len(MOCK_CRASHLYTICS_ROWS))):
        out.append(MOCK_CRASHLYTICS_ROWS[i])
    # Generate extra rows deterministically.
    for i in range(len(out), n):
        out.append(_taminaty_mock_row(idx=i + 1))
    return out

