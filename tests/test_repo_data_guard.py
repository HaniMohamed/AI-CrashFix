from __future__ import annotations

import pytest
from fastapi import HTTPException

from app.services.app_settings_store import AppSettingsStore
from app.services.repo_data_guard import ensure_repo_data_writable, is_repo_data_readonly
from app.services.repo_registry_store import RepoRegistryStore
from app.services.sqlite_util import reset_schema_cache_for_tests


@pytest.fixture(autouse=True)
def _clear_stores(tmp_path, monkeypatch):
    reset_schema_cache_for_tests()
    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()
    db = tmp_path / "repo_registry.db"
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(db))
    monkeypatch.delenv("AI_CRASH_FIX_REPO_DATA_READONLY", raising=False)


def test_is_repo_data_readonly_false_by_default():
    assert is_repo_data_readonly() is False


def test_is_repo_data_readonly_from_app_settings():
    store = AppSettingsStore()
    store.set(k="REPO_DATA_READONLY", v=True)
    assert is_repo_data_readonly() is True


def test_is_repo_data_readonly_string_truthy():
    store = AppSettingsStore()
    store.set(k="REPO_DATA_READONLY", v="true")
    assert is_repo_data_readonly() is True


def test_ensure_repo_data_writable_raises_when_readonly():
    AppSettingsStore().set(k="REPO_DATA_READONLY", v=True)
    with pytest.raises(HTTPException) as exc:
        ensure_repo_data_writable()
    assert exc.value.status_code == 403
