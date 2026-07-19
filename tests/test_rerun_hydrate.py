from __future__ import annotations

from app.api.runner import _hydrate_rerun_state


class _FakeStore:
    def __init__(self, row: dict | None):
        self._row = row

    def get_crash(self, crash_id: str, *, include_result: bool = True):
        return self._row


def test_hydrate_reuses_jira_from_store_column() -> None:
    store = _FakeStore(
        {
            "jira_issue_id": "DE-42",
            "result": {"skip_jira_creation": True, "jira_issue_id": "DE-42"},
        }
    )
    state = {"skip_jira_creation": True, "jira_issue_id": None}
    out = _hydrate_rerun_state(
        state,
        crash_store=store,  # type: ignore[arg-type]
        crash_id="c1",
        skip_jira_creation=True,
    )
    assert out["jira_issue_id"] == "DE-42"
    # Existing ticket forces Jira path on so create no-ops / PR keeps the key.
    assert out["skip_jira_creation"] is False


def test_hydrate_reuses_jira_from_result_when_column_empty() -> None:
    store = _FakeStore(
        {
            "jira_issue_id": None,
            "result": {"skip_jira_creation": False, "jira_issue_id": "DE-99"},
        }
    )
    state = {"skip_jira_creation": True, "jira_issue_id": None}
    out = _hydrate_rerun_state(
        state,
        crash_store=store,  # type: ignore[arg-type]
        crash_id="c1",
        skip_jira_creation=True,
    )
    assert out["jira_issue_id"] == "DE-99"
    assert out["skip_jira_creation"] is False


def test_hydrate_forces_jira_on_when_previous_did_not_skip() -> None:
    store = _FakeStore(
        {
            "jira_issue_id": None,
            "result": {"skip_jira_creation": False},
        }
    )
    state = {"skip_jira_creation": True, "jira_issue_id": None}
    out = _hydrate_rerun_state(
        state,
        crash_store=store,  # type: ignore[arg-type]
        crash_id="c1",
        skip_jira_creation=True,
    )
    assert out["jira_issue_id"] is None
    assert out["skip_jira_creation"] is False


def test_hydrate_keeps_request_skip_when_previous_skipped() -> None:
    store = _FakeStore(
        {
            "jira_issue_id": None,
            "result": {"skip_jira_creation": True},
        }
    )
    state = {"skip_jira_creation": False, "jira_issue_id": None}
    out = _hydrate_rerun_state(
        state,
        crash_store=store,  # type: ignore[arg-type]
        crash_id="c1",
        skip_jira_creation=True,
    )
    assert out["jira_issue_id"] is None
    assert out["skip_jira_creation"] is True


def test_hydrate_noop_when_crash_unknown() -> None:
    store = _FakeStore(None)
    state = {"skip_jira_creation": True, "jira_issue_id": None}
    out = _hydrate_rerun_state(
        state,
        crash_store=store,  # type: ignore[arg-type]
        crash_id="missing",
        skip_jira_creation=True,
    )
    assert out["skip_jira_creation"] is True
    assert out["jira_issue_id"] is None
