from __future__ import annotations

from pathlib import Path

from app.services.app_settings_store import AppSettingsStore
from app.services.auth_store import AuthStore
from app.services.repo_registry_store import RepoRegistryStore
from app.services.settings_resolver import SettingsResolver
from app.services.sqlite_util import connect_sqlite, reset_schema_cache_for_tests


def test_connect_sqlite_closes_on_context_exit(tmp_path: Path) -> None:
    db = tmp_path / "t.db"
    with connect_sqlite(str(db)) as conn:
        conn.execute("CREATE TABLE t (id INTEGER)")
        conn.commit()
        assert conn.execute("SELECT COUNT(*) FROM t").fetchone()[0] == 0
    # Re-open after close must succeed (no leaked lock / FD from prior context).
    with connect_sqlite(str(db)) as conn:
        assert conn.execute("SELECT COUNT(*) FROM t").fetchone()[0] == 0


def test_auth_store_repeated_reads_do_not_exhaust_fds(tmp_path: Path, monkeypatch) -> None:
    """Regression: ``with sqlite3.Connection`` does not close; we must close ourselves."""
    reset_schema_cache_for_tests()
    AuthStore.clear_shared_for_tests()
    AppSettingsStore.clear_shared_for_tests()
    monkeypatch.setenv("AI_CRASH_FIX_DATA_DIR", str(tmp_path))
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(tmp_path / "registry.db"))

    store = AuthStore()
    assert store.backend == "sqlite"
    for _ in range(400):
        assert store.count_users() == 0
    # If connections leaked, this open would eventually fail with
    # "unable to open database file" under a low FD limit.
    assert store.count_users() == 0


def test_app_settings_store_is_singleton_per_path(tmp_path: Path, monkeypatch) -> None:
    reset_schema_cache_for_tests()
    AppSettingsStore.clear_shared_for_tests()
    db = tmp_path / "repo_registry.db"
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(db))

    a = AppSettingsStore()
    b = AppSettingsStore()
    assert a is b
    a.set(k="LLM_PROVIDER", v="gosi-brain")
    assert b.get(k="LLM_PROVIDER") == "gosi-brain"


def test_settings_resolver_reads_settings_from_cache(tmp_path: Path, monkeypatch) -> None:
    reset_schema_cache_for_tests()
    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()
    db = tmp_path / "repo_registry.db"
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(db))
    monkeypatch.setenv("LLM_PROVIDER", "gemini")

    store = AppSettingsStore()
    store.set(k="LLM_PROVIDER", v="gosi-brain")
    store.set(k="GOSI_BRAIN_MODEL", v="gosi_brain_agent")

    r = SettingsResolver()
    assert r.effective_llm_provider() == "gosi-brain"
    assert r.effective_gosi_brain().get("model") == "gosi_brain_agent"
