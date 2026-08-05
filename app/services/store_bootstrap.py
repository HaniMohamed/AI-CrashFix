"""Persist crash-store backend choice for the Setup Wizard / Settings UI.

Store backend cannot live in app_settings (chicken-and-egg: that store *is*
SQLite or Postgres). Instead we write a small JSON file under the data dir
and apply it into process env on startup and when the user saves.
"""

from __future__ import annotations

import json
import logging
import os
import re
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlparse, urlunparse

_log = logging.getLogger(__name__)

STORE_BOOTSTRAP_FILENAME = "store_bootstrap.json"


def _data_dir() -> Path | None:
    from app.services.log_files import resolve_data_dir

    return resolve_data_dir()


def store_bootstrap_path() -> Path | None:
    base = _data_dir()
    if base is None:
        # Dev fallback when DATA_DIR is unset: keep next to repo registry default.
        try:
            return Path("db").resolve() / STORE_BOOTSTRAP_FILENAME
        except Exception:
            return None
    return (base / STORE_BOOTSTRAP_FILENAME).resolve()


def _mask_db_url(url: str | None) -> str | None:
    raw = (url or "").strip()
    if not raw:
        return None
    try:
        parsed = urlparse(raw)
        if not parsed.scheme or not parsed.netloc:
            return raw
        userinfo, _, hostport = parsed.netloc.rpartition("@")
        if not userinfo:
            return raw
        user, sep, _password = userinfo.partition(":")
        if sep:
            masked_userinfo = f"{user}:***"
        else:
            masked_userinfo = userinfo
        netloc = f"{masked_userinfo}@{hostport}"
        return urlunparse(parsed._replace(netloc=netloc))
    except Exception:
        return re.sub(r"(://[^:/@]+:)[^@]+(@)", r"\1***\2", raw)


def compose_db_url(
    url: str,
    *,
    username: str | None = None,
    password: str | None = None,
) -> str:
    """Merge optional username/password into a Postgres URL."""
    base = (url or "").strip()
    user = (username or "").strip() or None
    password_raw = password if password is not None else None
    pwd = (password_raw or "").strip() if password_raw is not None else None
    if not base:
        return base
    if not user and pwd is None:
        return base
    parsed = urlparse(base)
    if not parsed.scheme:
        raise ValueError("Database URL must include a scheme (e.g. postgresql://…)")
    hostport = parsed.netloc
    existing_userinfo = ""
    if "@" in parsed.netloc:
        existing_userinfo, _, hostport = parsed.netloc.rpartition("@")
    existing_user, _, existing_pwd = existing_userinfo.partition(":")
    final_user = user or (existing_user or None)
    if pwd is not None and pwd != "":
        final_pwd: str | None = pwd
    elif user and pwd == "":
        # Explicit empty password override
        final_pwd = ""
    elif existing_userinfo and ":" in existing_userinfo:
        final_pwd = existing_pwd
    else:
        final_pwd = None
    if not final_user:
        return base
    if final_pwd is None:
        userinfo = quote(final_user, safe="")
    else:
        userinfo = f"{quote(final_user, safe='')}:{quote(final_pwd, safe='')}"
    return urlunparse(parsed._replace(netloc=f"{userinfo}@{hostport}"))


def load_store_bootstrap() -> dict[str, Any] | None:
    path = store_bootstrap_path()
    if path is None or not path.is_file():
        return None
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        _log.warning("Ignoring invalid store bootstrap at %s: %s", path, exc)
        return None
    if not isinstance(raw, dict):
        return None
    backend = str(raw.get("backend") or "").strip().lower()
    if backend not in {"sqlite", "postgres"}:
        return None
    return {
        "backend": backend,
        "db_url": (str(raw.get("db_url") or "").strip() or None),
        "user_id": (str(raw.get("user_id") or "").strip() or None),
    }


def save_store_bootstrap(
    *,
    backend: str,
    db_url: str | None = None,
    user_id: str | None = None,
) -> Path:
    path = store_bootstrap_path()
    if path is None:
        raise RuntimeError(
            "Cannot persist store config: AI_CRASH_FIX_DATA_DIR is unset "
            "and no writable fallback path is available."
        )
    backend_norm = (backend or "").strip().lower()
    if backend_norm not in {"sqlite", "postgres"}:
        raise ValueError("backend must be 'sqlite' or 'postgres'")
    payload: dict[str, Any] = {"backend": backend_norm}
    if backend_norm == "postgres":
        url = (db_url or "").strip()
        if not url:
            raise ValueError("db_url is required for postgres")
        uid = (user_id or "").strip()
        if not uid:
            raise ValueError("user_id is required for postgres")
        payload["db_url"] = url
        payload["user_id"] = uid
    else:
        # Keep optional user_id for identity continuity; clear remote URL.
        uid = (user_id or "").strip()
        if uid:
            payload["user_id"] = uid
        payload["db_url"] = None

    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return path


def _sync_user_id_config_from_environ() -> None:
    import app.config as cfg

    cfg.AI_CRASH_FIX_USER_ID = (os.getenv("AI_CRASH_FIX_USER_ID") or "").strip() or None


def apply_store_bootstrap_to_environ() -> dict[str, Any] | None:
    """Overlay bootstrap file onto process env. Returns applied payload or None."""
    data = load_store_bootstrap()
    if not data:
        return None

    backend = data["backend"]
    os.environ["AI_CRASH_FIX_CRASH_STORE_BACKEND"] = backend
    if backend == "postgres":
        url = data.get("db_url")
        if url:
            os.environ["AI_CRASH_FIX_CRASH_DB_URL"] = str(url)
        uid = data.get("user_id")
        if uid:
            os.environ["AI_CRASH_FIX_USER_ID"] = str(uid)
        # Buyer-selected remote store should not silently fall back mid-session
        # unless they later force local via use-local-store.
    else:
        os.environ["AI_CRASH_FIX_CRASH_STORE_BACKEND"] = "sqlite"
        # Leave CRASH_DB_URL in env if IT set it, but backend=sqlite wins.
        uid = data.get("user_id")
        if uid:
            os.environ["AI_CRASH_FIX_USER_ID"] = str(uid)

    from app.services.crash_store import _sync_crash_store_config_from_environ

    _sync_crash_store_config_from_environ()
    _sync_user_id_config_from_environ()
    return data


def is_store_setup_complete() -> bool:
    """True when a store backend choice has been committed for this machine.

    Fresh installs default to SQLite in process env but are *not* complete until
    the buyer confirms via first-run / wizard (``store_bootstrap.json``), unless
    they already have auth users (upgrade) or launch env pins remote Postgres.
    """
    if load_store_bootstrap() is not None:
        return True
    try:
        from app.services.auth_store import AuthStore

        if AuthStore().count_users() > 0:
            return True
    except Exception:
        pass
    backend = (os.getenv("AI_CRASH_FIX_CRASH_STORE_BACKEND") or "").strip().lower()
    url = (os.getenv("AI_CRASH_FIX_CRASH_DB_URL") or "").strip()
    if backend == "postgres" and url:
        return True
    return False


def can_configure_store_without_auth() -> bool:
    """Allow unauthenticated store setup during first-run (before any admin exists)."""
    if not is_store_setup_complete():
        return True
    try:
        from app.services.auth_store import AuthStore

        return AuthStore().count_users() == 0
    except Exception:
        return True


def reset_store_singletons() -> None:
    """Drop cached store facades after a backend switch."""
    from app.services.app_settings_store import AppSettingsStore
    from app.services import crash_store as cs
    from app.services.repo_registry_store import RepoRegistryStore
    from app.services.auth_store import AuthStore

    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()
    AuthStore.clear_shared_for_tests()
    cs._CRASH_STORE_HEALTH_CACHE = None
    cs._CRASH_STORE_HEALTH_CACHED_AT = 0.0
    cs._CRASH_STORE_FALLBACK = None


def current_store_config_public() -> dict[str, Any]:
    """Public view of effective store config (secrets masked)."""
    from app.services.crash_store import crash_store_backend_name, crash_store_health
    from app.services.user_context import resolve_user_id

    bootstrap = load_store_bootstrap()
    try:
        backend = crash_store_backend_name()
    except ValueError:
        backend = "unknown"

    db_url = (os.getenv("AI_CRASH_FIX_CRASH_DB_URL") or "").strip() or None
    if not db_url and bootstrap:
        db_url = bootstrap.get("db_url")

    return {
        "backend": backend,
        "db_url_masked": _mask_db_url(db_url),
        "has_db_url": bool(db_url),
        "user_id": resolve_user_id(required=False),
        "bootstrap_path": str(store_bootstrap_path()) if store_bootstrap_path() else None,
        "bootstrap_present": bootstrap is not None,
        "crash_store": crash_store_health(force=True),
    }


def configure_store(
    *,
    backend: str,
    db_url: str | None = None,
    username: str | None = None,
    password: str | None = None,
    user_id: str | None = None,
    test_connection: bool = True,
) -> dict[str, Any]:
    """Persist, apply, and optionally verify the selected store backend."""
    backend_norm = (backend or "").strip().lower()
    if backend_norm not in {"sqlite", "postgres"}:
        raise ValueError("backend must be 'sqlite' or 'postgres'")

    composed_url: str | None = None
    if backend_norm == "postgres":
        raw_url = (db_url or "").strip()
        if not raw_url and (username or password):
            raise ValueError("db_url is required (host/database); username/password are optional extras")
        if not raw_url:
            # Keep existing URL when only rotating credentials / user id.
            existing = load_store_bootstrap() or {}
            raw_url = (existing.get("db_url") or os.getenv("AI_CRASH_FIX_CRASH_DB_URL") or "").strip()
        if not raw_url:
            raise ValueError("db_url is required for postgres")
        composed_url = compose_db_url(raw_url, username=username, password=password)
        uid = (user_id or "").strip()
        if not uid:
            raise ValueError("user_id is required for postgres")

        if test_connection:
            # Temporarily poke env for the probe without committing yet.
            prev_backend = os.environ.get("AI_CRASH_FIX_CRASH_STORE_BACKEND")
            prev_url = os.environ.get("AI_CRASH_FIX_CRASH_DB_URL")
            prev_uid = os.environ.get("AI_CRASH_FIX_USER_ID")
            try:
                os.environ["AI_CRASH_FIX_CRASH_STORE_BACKEND"] = "postgres"
                os.environ["AI_CRASH_FIX_CRASH_DB_URL"] = composed_url
                os.environ["AI_CRASH_FIX_USER_ID"] = uid
                from app.services.crash_store import _sync_crash_store_config_from_environ
                from app.services.crash_store_postgres import check_postgres_crash_store

                _sync_crash_store_config_from_environ()
                _sync_user_id_config_from_environ()
                ok, error = check_postgres_crash_store()
                if not ok:
                    raise ValueError(error or "Postgres connection failed")
            finally:
                if prev_backend is None:
                    os.environ.pop("AI_CRASH_FIX_CRASH_STORE_BACKEND", None)
                else:
                    os.environ["AI_CRASH_FIX_CRASH_STORE_BACKEND"] = prev_backend
                if prev_url is None:
                    os.environ.pop("AI_CRASH_FIX_CRASH_DB_URL", None)
                else:
                    os.environ["AI_CRASH_FIX_CRASH_DB_URL"] = prev_url
                if prev_uid is None:
                    os.environ.pop("AI_CRASH_FIX_USER_ID", None)
                else:
                    os.environ["AI_CRASH_FIX_USER_ID"] = prev_uid
                from app.services.crash_store import _sync_crash_store_config_from_environ

                _sync_crash_store_config_from_environ()
                _sync_user_id_config_from_environ()

        save_store_bootstrap(backend="postgres", db_url=composed_url, user_id=uid)
    else:
        save_store_bootstrap(
            backend="sqlite",
            db_url=None,
            user_id=(user_id or "").strip() or None,
        )
        # Prefer local when buyer explicitly chooses SQLite.
        os.environ.pop("AI_CRASH_FIX_CRASH_STORE_STRICT", None)

    apply_store_bootstrap_to_environ()
    reset_store_singletons()

    # Ensure schema / connectivity on the new backend.
    from app.services.crash_store import ensure_crash_store_available

    ensure = ensure_crash_store_available()
    if backend_norm == "postgres" and ensure.get("ok") is not True:
        raise ValueError(str(ensure.get("error") or "Postgres store is not available"))

    from app.services.auth_store import AuthStore

    AuthStore()

    return {
        "ok": True,
        "config": current_store_config_public(),
        "ensure": ensure,
        "store_setup_complete": is_store_setup_complete(),
    }
