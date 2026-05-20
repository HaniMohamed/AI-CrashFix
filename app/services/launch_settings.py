from __future__ import annotations

import os

from app.services.app_settings_store import AppSettingsStore

# Env keys from `open --args` / launcher that map to editable app_settings (Settings UI).
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
        "GOOGLE_APPLICATION_CREDENTIALS",
        "BQ_PROJECT_ID",
        "FIREBASE_CONSOLE_PROJECT_ID",
        "CRASHLYTICS_ANDROID_PACKAGE",
        "CRASHLYTICS_IOS_BUNDLE_ID",
        "JIRA_SERVER_URL",
        "JIRA_VERIFY_SSL",
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


def persist_launch_env_overrides() -> list[str]:
    """
    When the macOS launcher starts the backend with `open --args`, it sets
    ``AI_CRASH_FIX_LAUNCH_ENV_KEYS`` to a comma-separated list of env keys that
    were explicitly provided. Persist those values into SQLite so ``GET
    /api/settings`` (Settings page) reflects the launch configuration.
    """
    marker = (os.environ.get("AI_CRASH_FIX_LAUNCH_ENV_KEYS") or "").strip()
    if not marker:
        return []

    store = AppSettingsStore()
    persisted: list[str] = []
    for key in marker.split(","):
        k = key.strip()
        if not k or k not in _APP_SETTINGS_ENV_KEYS:
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
