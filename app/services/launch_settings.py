from __future__ import annotations

import os
from pathlib import Path

from app.services.app_settings_store import AppSettingsStore

# Env keys from `open --args` / launcher / env-file that map to editable app_settings.
_APP_SETTINGS_ENV_KEYS: frozenset[str] = frozenset(
    {
        "LLM_PROVIDER",
        "OPENAI_URL",
        "OPENAI_MODEL",
        "OPENAI_API_KEY",
        "GOOGLE_API_KEY",
        "GEMINI_MODEL",
        "GOSI_BRAIN_URL",
        "GOSI_BRAIN_MODEL",
        "GOSI_BRAIN_AUTHORIZATION",
        "GOSI_BRAIN_API_KEY",
        "GOSI_BRAIN_OAUTH_IDENTITY_DOMAIN_NAME",
        "GOSI_BRAIN_TEMPERATURE",
        "GOSI_BRAIN_USER_ID",
        "GOSI_BRAIN_COOKIE",
        "GOSI_BRAIN_STREAMING",
        "GOSI_BRAIN_IDLE_TIMEOUT",
        "GOSI_BRAIN_WAF_CONTENT_SHIELD",
        "GOSI_BRAIN_SEND_OAUTH_DOMAIN",
        "GOOGLE_APPLICATION_CREDENTIALS",
        "BQ_PROJECT_ID",
        "FIREBASE_CONSOLE_PROJECT_ID",
        "CRASHLYTICS_ANDROID_PACKAGE",
        "CRASHLYTICS_IOS_BUNDLE_ID",
        "JIRA_SERVER_URL",
        "JIRA_VERIFY_SSL",
        "JIRA_AUTH",
        "JIRA_CREATE_FIELDS",
        "JIRA_TOKEN",
        "JIRA_EMAIL",
        "JIRA_ISSUE_TYPE",
        "JIRA_PROJECT_KEY",
        "GITLAB_SERVER_URL",
        "GITLAB_VERIFY_SSL",
        "GITLAB_SSL_CA_BUNDLE",
        "GITLAB_TOKEN",
    }
)


def _coerce_value(key: str, raw: str) -> str | float:
    if key == "GOSI_BRAIN_TEMPERATURE":
        return float(raw.strip())
    return raw.strip()


def _parse_env_file(path: Path) -> dict[str, str]:
    """Parse a simple KEY=VALUE env file (supports quotes; ignores blank/# lines)."""
    out: dict[str, str] = {}
    text = path.read_text(encoding="utf-8")
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        if not key:
            continue
        val = val.strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
            val = val[1:-1]
        out[key] = val
    return out


def apply_launch_env_file() -> list[str]:
    """
    Load ``AI_CRASH_FIX_ENV_FILE`` into ``os.environ``.

    Avoids macOS ``ARG_MAX`` / "command too long" when JWTs and keys are too large
    for ``open --args`` / ``open --env``. Only the short file path needs to be on
    the command line (or exported in the parent shell).

    Keys loaded from the file are merged into ``AI_CRASH_FIX_LAUNCH_ENV_KEYS`` so
    ``persist_launch_env_overrides`` writes them into Settings.
    """
    raw_path = (os.environ.get("AI_CRASH_FIX_ENV_FILE") or "").strip()
    if not raw_path:
        return []
    path = Path(raw_path).expanduser()
    if not path.is_file():
        # Do not crash the API process — missing file should be visible in Settings.
        import logging

        logging.getLogger(__name__).warning(
            "AI_CRASH_FIX_ENV_FILE not found: %s (continuing without it)",
            path,
        )
        return []

    loaded = _parse_env_file(path)
    applied: list[str] = []
    for key, value in loaded.items():
        os.environ[key] = value
        applied.append(key)

    if applied:
        existing = {
            k.strip()
            for k in (os.environ.get("AI_CRASH_FIX_LAUNCH_ENV_KEYS") or "").split(",")
            if k.strip()
        }
        merged = sorted(existing | set(applied))
        os.environ["AI_CRASH_FIX_LAUNCH_ENV_KEYS"] = ",".join(merged)
    return applied


def persist_launch_env_overrides() -> list[str]:
    """
    When the macOS launcher starts the backend with ``open --args``, or when
    ``AI_CRASH_FIX_ENV_FILE`` was applied, ``AI_CRASH_FIX_LAUNCH_ENV_KEYS`` lists
    env keys to persist into SQLite so Settings reflects the launch configuration.
    """
    from app.services.repo_data_guard import is_repo_data_readonly

    apply_launch_env_file()

    if is_repo_data_readonly():
        return []

    marker = (os.environ.get("AI_CRASH_FIX_LAUNCH_ENV_KEYS") or "").strip()
    if not marker:
        return []

    from app.services.user_context import assert_postgres_user_id_configured

    try:
        assert_postgres_user_id_configured()
    except ValueError:
        import logging

        logging.getLogger(__name__).warning(
            "Skipping launch env persist: postgres backend requires AI_CRASH_FIX_USER_ID "
            "(or GOSI_BRAIN_USER_ID as fallback)"
        )
        return []

    store = AppSettingsStore()
    persisted: list[str] = []
    crash_fix_uid = (os.environ.get("AI_CRASH_FIX_USER_ID") or "").strip()
    for key in marker.split(","):
        k = key.strip()
        if not k or k not in _APP_SETTINGS_ENV_KEYS:
            continue
        # AI_CRASH_FIX_USER_ID owns identity; do not mirror GOSI_BRAIN_USER_ID into settings.
        if k == "GOSI_BRAIN_USER_ID" and crash_fix_uid:
            continue
        raw = os.environ.get(k)
        if raw is None:
            continue
        s = str(raw).strip()
        if not s:
            continue
        try:
            store.set(k=k, v=_coerce_value(k, s))
        except ValueError:
            store.set(k=k, v=s)
        persisted.append(k)
    return persisted
