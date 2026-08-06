from __future__ import annotations

import os
from pathlib import Path

from app.services.launch_settings import apply_launch_env_file


def test_apply_launch_env_file_auto_detects_home_default(
    monkeypatch, tmp_path: Path
) -> None:
    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    env_file = home / "crash_fix_gosi_brain_conf.env"
    env_file.write_text(
        "LLM_PROVIDER=gosi-brain\nGOSI_BRAIN_AUTHORIZATION=Bearer token\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("AI_CRASH_FIX_AUTO_LAUNCH_ENV", "1")
    monkeypatch.delenv("AI_CRASH_FIX_ENV_FILE", raising=False)
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    monkeypatch.delenv("GOSI_BRAIN_AUTHORIZATION", raising=False)
    monkeypatch.delenv("AI_CRASH_FIX_LAUNCH_ENV_KEYS", raising=False)

    applied = apply_launch_env_file()
    assert "LLM_PROVIDER" in applied
    assert os.environ["AI_CRASH_FIX_ENV_FILE"] == str(env_file.resolve())
    assert os.environ["LLM_PROVIDER"] == "gosi-brain"
    assert os.environ["GOSI_BRAIN_AUTHORIZATION"] == "Bearer token"


def test_apply_launch_env_file_prefers_fixora_env_over_legacy(
    monkeypatch, tmp_path: Path
) -> None:
    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    (home / "crash_fix_gosi_brain_conf.env").write_text(
        "LLM_PROVIDER=gosi-brain\n",
        encoding="utf-8",
    )
    fixora = home / "fixora.env"
    fixora.write_text(
        "AI_CRASH_FIX_CRASH_STORE_BACKEND=sqlite\nLLM_PROVIDER=openai\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("AI_CRASH_FIX_AUTO_LAUNCH_ENV", "1")
    monkeypatch.delenv("AI_CRASH_FIX_ENV_FILE", raising=False)
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    monkeypatch.delenv("AI_CRASH_FIX_LAUNCH_ENV_KEYS", raising=False)

    applied = apply_launch_env_file()
    assert "LLM_PROVIDER" in applied
    assert os.environ["AI_CRASH_FIX_ENV_FILE"] == str(fixora.resolve())
    assert os.environ["LLM_PROVIDER"] == "openai"
    assert os.environ["AI_CRASH_FIX_CRASH_STORE_BACKEND"] == "sqlite"


def test_gosi_brain_launch_health_never_hard_blocks(monkeypatch, tmp_path: Path) -> None:
    """Standalone product: missing/expired GOSI creds must not gate the UI."""
    import app.config as cfg
    from app.services.app_settings_store import AppSettingsStore
    from app.services.gosi_brain_launch import gosi_brain_launch_health

    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    db = tmp_path / "repo_registry.db"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(db))
    monkeypatch.delenv("AI_CRASH_FIX_ENV_FILE", raising=False)
    monkeypatch.delenv("GOSI_BRAIN_AUTHORIZATION", raising=False)
    monkeypatch.setattr(cfg, "GOSI_BRAIN_AUTHORIZATION", None)
    AppSettingsStore.clear_shared_for_tests()
    store = AppSettingsStore()
    store.set(k="LLM_PROVIDER", v="gosi-brain")

    health = gosi_brain_launch_health()
    assert health["required"] is False
    assert health["ok"] is True
    assert health["provider"] == "gosi-brain"
    assert health["reason"] == "authorization_missing"


def test_gosi_brain_launch_health_reports_settings_auth(
    monkeypatch, tmp_path: Path
) -> None:
    import base64
    import json
    import time

    import app.config as cfg
    from app.services.app_settings_store import AppSettingsStore
    from app.services.gosi_brain_launch import gosi_brain_launch_health

    def _jwt(exp: int) -> str:
        header = base64.urlsafe_b64encode(b'{"alg":"none"}').decode().rstrip("=")
        payload = (
            base64.urlsafe_b64encode(json.dumps({"exp": exp}).encode())
            .decode()
            .rstrip("=")
        )
        return f"{header}.{payload}.x"

    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    (tmp_path / "home").mkdir(exist_ok=True)
    monkeypatch.setenv("AI_CRASH_FIX_REPO_REGISTRY_DB", str(tmp_path / "registry.db"))
    monkeypatch.delenv("AI_CRASH_FIX_ENV_FILE", raising=False)
    monkeypatch.delenv("GOSI_BRAIN_AUTHORIZATION", raising=False)
    monkeypatch.setattr(cfg, "GOSI_BRAIN_AUTHORIZATION", None)
    AppSettingsStore.clear_shared_for_tests()

    store = AppSettingsStore()
    store.set(k="LLM_PROVIDER", v="gosi-brain")
    store.set(
        k="GOSI_BRAIN_AUTHORIZATION",
        v=f"Bearer {_jwt(int(time.time()) + 3600)}",
    )

    health = gosi_brain_launch_health()
    assert health["required"] is False
    assert health["ok"] is True
    assert health["authorization_present"] is True
    assert health["authorization_expired"] is False
