from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def auth_client(monkeypatch, tmp_path):
    monkeypatch.setenv("AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(tmp_path / "registry.db"))
    monkeypatch.delenv("AI_CRASH_FIX_CRASH_DB_URL", raising=False)
    import app.config as cfg

    monkeypatch.setattr(cfg, "AI_CRASH_FIX_CRASH_STORE_BACKEND", "sqlite")
    monkeypatch.setattr(cfg, "AI_CRASH_FIX_CRASH_DB_URL", None)

    from app.services.auth_store import AuthStore
    from app.services.app_settings_store import AppSettingsStore
    from app.services.repo_registry_store import RepoRegistryStore

    AuthStore.clear_shared_for_tests()
    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()

    from app.api.server import app

    client = TestClient(app)
    yield client
    AuthStore.clear_shared_for_tests()
    AppSettingsStore.clear_shared_for_tests()
    RepoRegistryStore.clear_shared_for_tests()


def test_bootstrap_admin_when_empty(auth_client: TestClient):
    r = auth_client.get("/api/auth/bootstrap-status")
    assert r.status_code == 200
    assert r.json()["needs_admin"] is True

    r2 = auth_client.post(
        "/api/auth/bootstrap-admin",
        json={"username": "admin", "tenant_user_id": "admin.local"},
    )
    assert r2.status_code == 200
    body = r2.json()
    assert body["temp_password"]
    assert body["user"]["role"] == "admin"
    assert body["user"]["must_change_password"] is True

    r3 = auth_client.get("/api/auth/bootstrap-status")
    assert r3.json()["needs_admin"] is False


def test_bootstrap_admin_rejected_when_users_exist(auth_client: TestClient):
    auth_client.post(
        "/api/auth/bootstrap-admin",
        json={"username": "admin"},
    )
    r = auth_client.post(
        "/api/auth/bootstrap-admin",
        json={"username": "other"},
    )
    assert r.status_code == 400


def test_login_and_protected_route(auth_client: TestClient):
    boot = auth_client.post(
        "/api/auth/bootstrap-admin",
        json={"username": "alice", "tenant_user_id": "alice"},
    ).json()
    temp = boot["temp_password"]

    login = auth_client.post(
        "/api/auth/login",
        json={"username": "alice", "password": temp},
    )
    assert login.status_code == 200
    token = login.json()["token"]

    denied = auth_client.get("/api/repos")
    assert denied.status_code == 401

    blocked = auth_client.get("/api/repos", headers={"Authorization": f"Bearer {token}"})
    assert blocked.status_code == 403

    changed = auth_client.post(
        "/api/auth/change-password",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "current_password": temp,
            "new_password": "super-secure-pass-12",
        },
    )
    assert changed.status_code == 200
    assert changed.json()["user"]["must_change_password"] is False

    repos = auth_client.get("/api/repos", headers={"Authorization": f"Bearer {token}"})
    assert repos.status_code == 200


def test_admin_create_user_reset_password(auth_client: TestClient):
    boot = auth_client.post(
        "/api/auth/bootstrap-admin",
        json={"username": "admin"},
    ).json()
    temp = boot["temp_password"]
    login = auth_client.post(
        "/api/auth/login",
        json={"username": "admin", "password": temp},
    ).json()
    token = login["token"]
    headers = {"Authorization": f"Bearer {token}"}
    auth_client.post(
        "/api/auth/change-password",
        headers=headers,
        json={"current_password": temp, "new_password": "admin-secure-pass-12"},
    )

    created = auth_client.post(
        "/api/auth/users",
        headers=headers,
        json={"username": "bob", "role": "user"},
    )
    assert created.status_code == 200
    user_temp = created.json()["temp_password"]
    user_id = created.json()["user"]["id"]

    reset = auth_client.post(
        f"/api/auth/users/{user_id}/reset-password",
        headers=headers,
    )
    assert reset.status_code == 200
    assert reset.json()["temp_password"]
    assert reset.json()["user"]["must_change_password"] is True

    blocked = auth_client.patch(
        f"/api/auth/users/{user_id}",
        headers=headers,
        json={"status": "blocked"},
    )
    assert blocked.status_code == 200
    assert blocked.json()["user"]["status"] == "blocked"

    fail_login = auth_client.post(
        "/api/auth/login",
        json={"username": "bob", "password": user_temp},
    )
    assert fail_login.status_code == 401
