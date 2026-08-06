from __future__ import annotations


def test_auth_store_falls_back_to_sqlite_when_postgres_down(monkeypatch, tmp_path):
    monkeypatch.setenv("AI_CRASH_FIX_DATA_DIR", str(tmp_path))
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "postgres")
    monkeypatch.setenv(
        "AI_CRASH_FIX_CRASH_DB_URL",
        "postgresql://ai_crash_fix:bad@127.0.0.1:1/ai_crash_fix",
    )
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(tmp_path / "registry.db"))
    import app.config as cfg

    monkeypatch.setattr(cfg, "AI_CRASH_FIX_CRASH_STORE_BACKEND", "postgres")
    monkeypatch.setattr(
        cfg,
        "AI_CRASH_FIX_CRASH_DB_URL",
        "postgresql://ai_crash_fix:bad@127.0.0.1:1/ai_crash_fix",
    )

    from app.services.auth_store import AuthStore
    from app.services.app_settings_store import AppSettingsStore
    from app.services.repo_registry_store import RepoRegistryStore

    AuthStore.clear_shared_for_tests()
    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()

    store = AuthStore()
    assert store.backend == "sqlite"
    assert store.count_users() == 0
    # Second construction must reuse the healthy singleton (not retry Postgres).
    store2 = AuthStore()
    assert store2 is store
    assert store2.backend == "sqlite"
