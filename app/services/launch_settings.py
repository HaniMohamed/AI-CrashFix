from __future__ import annotations

import os
from pathlib import Path

from app.services.app_settings_store import AppSettingsStore

DEFAULT_LAUNCH_ENV_FILENAME = "crash_fix_gosi_brain_conf.env"
# Prefer Fixora-branded paths before the legacy GOSI launch filename.
FIXORA_LAUNCH_ENV_FILENAMES: tuple[str, ...] = (
    "Library/Application Support/Fixora/launch.env",
    "fixora.env",
)

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


def default_launch_env_file_path() -> Path:
    return Path.home() / DEFAULT_LAUNCH_ENV_FILENAME


def auto_launch_env_candidates() -> list[Path]:
    """Ordered candidates when ``AI_CRASH_FIX_AUTO_LAUNCH_ENV=1``."""
    home = Path.home()
    out: list[Path] = [home / rel for rel in FIXORA_LAUNCH_ENV_FILENAMES]
    out.append(home / DEFAULT_LAUNCH_ENV_FILENAME)
    return out


def env_file_nonempty(path: Path) -> bool:
    if not path.is_file():
        return False
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return False
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        if key.strip() and val.strip():
            return True
    return False


def parse_env_file(path: Path) -> dict[str, str]:
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


def _parse_env_file(path: Path) -> dict[str, str]:
    return parse_env_file(path)


def _resolve_launch_env_file_path() -> Path | None:
    raw_path = (os.environ.get("AI_CRASH_FIX_ENV_FILE") or "").strip()
    if raw_path:
        path = Path(raw_path).expanduser()
        return path if path.is_file() else None
    if (os.environ.get("AI_CRASH_FIX_AUTO_LAUNCH_ENV") or "").strip() != "1":
        return None
    for candidate in auto_launch_env_candidates():
        if env_file_nonempty(candidate):
            return candidate
    return None


# Buyer store choice lives in store_bootstrap.json; launch-env Postgres must not
# override a committed local SQLite install.
_STORE_BACKEND_ENV_KEYS: frozenset[str] = frozenset(
    {
        "AI_CRASH_FIX_CRASH_STORE_BACKEND",
        "AI_CRASH_FIX_CRASH_DB_URL",
    }
)


def _buyer_chose_sqlite_store() -> bool:
    try:
        from app.services.store_bootstrap import load_store_bootstrap

        data = load_store_bootstrap()
    except Exception:
        return False
    return bool(data) and str(data.get("backend") or "").strip().lower() == "sqlite"


def apply_launch_env_file() -> list[str]:
    """
    Load ``AI_CRASH_FIX_ENV_FILE`` into ``os.environ``.

    When ``AI_CRASH_FIX_ENV_FILE`` is unset, auto-detect only if
    ``AI_CRASH_FIX_AUTO_LAUNCH_ENV=1`` (opt-in; standalone builds leave this off).

    Avoids macOS ``ARG_MAX`` / "command too long" when JWTs and keys are too large
    for ``open --args`` / ``open --env``. Only the short file path needs to be on
    the command line (or exported in the parent shell).

    Keys loaded from the file are merged into ``AI_CRASH_FIX_LAUNCH_ENV_KEYS`` so
    ``persist_launch_env_overrides`` writes them into Settings.

    If the buyer already committed SQLite via ``store_bootstrap.json``, crash-store
    backend/URL keys from the launch file are skipped so a dead remote Postgres
    cannot override local auth.
    """
    path = _resolve_launch_env_file_path()
    if path is None:
        return []

    os.environ["AI_CRASH_FIX_ENV_FILE"] = str(path.resolve())
    loaded = parse_env_file(path)
    skip_store = _buyer_chose_sqlite_store()
    applied: list[str] = []
    for key, value in loaded.items():
        if skip_store and key in _STORE_BACKEND_ENV_KEYS:
            continue
        os.environ[key] = value
        applied.append(key)

    if applied:
        existing = {
            k.strip()
            for k in (os.environ.get("AI_CRASH_FIX_LAUNCH_ENV_KEYS") or "").split(",")
            if k.strip()
        }
        # Never mark skipped store keys as launch overrides to persist/re-apply.
        existing -= _STORE_BACKEND_ENV_KEYS if skip_store else set()
        merged = sorted(existing | set(applied))
        os.environ["AI_CRASH_FIX_LAUNCH_ENV_KEYS"] = ",".join(merged)
    return applied


def persist_launch_env_overrides() -> list[str]:
    """
    When the macOS launcher starts the backend with ``open --args``, or when
    ``AI_CRASH_FIX_ENV_FILE`` was applied, ``AI_CRASH_FIX_LAUNCH_ENV_KEYS`` lists
    env keys to persist into SQLite so Settings reflects the launch configuration.

    Does not re-load the launch env file: lifespan already applied it before
    ``store_bootstrap.json``. Re-applying would stomp a buyer SQLite choice with
    launch-file Postgres and break login.
    """
    try:
        return _persist_launch_env_overrides_to_store()
    except Exception:
        import logging

        logging.getLogger(__name__).warning(
            "Skipping launch env persist: app store unavailable",
            exc_info=True,
        )
        return []


def _persist_launch_env_overrides_to_store() -> list[str]:
    from app.services.repo_data_guard import is_repo_data_readonly

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
            "Skipping launch env persist: postgres backend requires AI_CRASH_FIX_USER_ID"
        )
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
