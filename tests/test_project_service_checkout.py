from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock

from app.services.project_service import ProjectService


def test_checkout_ref_resets_local_branch_to_origin(monkeypatch, tmp_path: Path) -> None:
    calls: list[list[str]] = []

    def fake_run(cmd, **kwargs):
        calls.append(list(cmd))
        # rev-parse --verify origin/uat succeeds
        m = MagicMock()
        m.returncode = 0
        m.stdout = "abc\n"
        return m

    def fake_check_output(cmd, **kwargs):
        calls.append(list(cmd))
        return "ok\n"

    monkeypatch.setattr("app.services.project_service.subprocess.run", fake_run)
    monkeypatch.setattr("app.services.project_service.subprocess.check_output", fake_check_output)

    svc = ProjectService(base_dir=str(tmp_path))
    svc._checkout_ref(tmp_path, ref="uat", clone_cmd=["git"])

    assert any(
        cmd[:5] == ["git", "checkout", "--force", "-B", "uat"] and cmd[5] == "origin/uat"
        for cmd in calls
    )


def test_checkout_ref_falls_back_when_no_origin(monkeypatch, tmp_path: Path) -> None:
    calls: list[list[str]] = []

    def fake_run(cmd, **kwargs):
        calls.append(list(cmd))
        m = MagicMock()
        # origin/uat missing
        m.returncode = 1
        m.stdout = ""
        return m

    def fake_check_output(cmd, **kwargs):
        calls.append(list(cmd))
        return "ok\n"

    monkeypatch.setattr("app.services.project_service.subprocess.run", fake_run)
    monkeypatch.setattr("app.services.project_service.subprocess.check_output", fake_check_output)

    # Make first rev_parse_ok for bare ref also fail so fetch is attempted —
    # _rev_parse_ok is called twice: origin/uat then ref.
    results = [1, 1]  # both fail → try fetch then checkout

    def fake_run2(cmd, **kwargs):
        calls.append(list(cmd))
        m = MagicMock()
        m.returncode = results.pop(0) if results else 1
        m.stdout = ""
        return m

    monkeypatch.setattr("app.services.project_service.subprocess.run", fake_run2)

    svc = ProjectService(base_dir=str(tmp_path))
    svc._checkout_ref(tmp_path, ref="deadbeef", clone_cmd=["git"])

    assert any(cmd[:3] == ["git", "checkout", "--force"] and "deadbeef" in cmd for cmd in calls)
