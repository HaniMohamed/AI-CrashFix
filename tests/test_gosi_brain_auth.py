from __future__ import annotations

import base64
import json
import time

from app.services.gosi_brain_auth import check_gosi_brain_authorization


def _jwt(payload: dict) -> str:
    header = base64.urlsafe_b64encode(b'{"alg":"none"}').decode().rstrip("=")
    body = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
    return f"{header}.{body}.sig"


def test_check_gosi_brain_authorization_missing() -> None:
    status = check_gosi_brain_authorization(None)
    assert status.present is False
    assert status.expired is False


def test_check_gosi_brain_authorization_valid_future_exp() -> None:
    exp = int(time.time()) + 3600
    token = _jwt({"exp": exp})
    status = check_gosi_brain_authorization(f"Bearer {token}")
    assert status.present is True
    assert status.expired is False
    assert status.expires_at == exp


def test_check_gosi_brain_authorization_expired() -> None:
    exp = int(time.time()) - 120
    token = _jwt({"exp": exp})
    status = check_gosi_brain_authorization(token)
    assert status.present is True
    assert status.expired is True
    assert status.expires_at == exp


def test_check_gosi_brain_authorization_no_exp_claim() -> None:
    token = _jwt({"sub": "user"})
    status = check_gosi_brain_authorization(token)
    assert status.present is True
    assert status.expired is False
    assert status.expires_at is None
