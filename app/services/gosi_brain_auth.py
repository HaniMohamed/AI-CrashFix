from __future__ import annotations

import base64
import json
import time
from dataclasses import dataclass


@dataclass(frozen=True)
class GosiBrainAuthStatus:
    present: bool
    expired: bool
    expires_at: int | None
    error: str | None = None


def extract_jwt_token(authorization: str | None) -> str | None:
    if not authorization:
        return None
    s = authorization.strip()
    if not s:
        return None
    if s.lower().startswith("bearer "):
        s = s[7:].strip()
    return s or None


def check_gosi_brain_authorization(
    authorization: str | None,
    *,
    skew_seconds: int = 60,
) -> GosiBrainAuthStatus:
    """
    Best-effort JWT expiry check for launch-time UX (no signature verification).
    """
    token = extract_jwt_token(authorization)
    if not token:
        return GosiBrainAuthStatus(present=False, expired=False, expires_at=None)

    parts = token.split(".")
    if len(parts) != 3:
        return GosiBrainAuthStatus(
            present=True,
            expired=True,
            expires_at=None,
            error="invalid_jwt_format",
        )

    try:
        payload_b64 = parts[1]
        padding = "=" * (-len(payload_b64) % 4)
        payload_json = base64.urlsafe_b64decode(payload_b64 + padding)
        payload = json.loads(payload_json)
    except Exception:
        return GosiBrainAuthStatus(
            present=True,
            expired=True,
            expires_at=None,
            error="invalid_jwt_payload",
        )

    exp = payload.get("exp")
    if exp is None:
        return GosiBrainAuthStatus(present=True, expired=False, expires_at=None)

    try:
        exp_int = int(exp)
    except (TypeError, ValueError):
        return GosiBrainAuthStatus(
            present=True,
            expired=True,
            expires_at=None,
            error="invalid_exp",
        )

    now = int(time.time())
    expired = now >= (exp_int - skew_seconds)
    return GosiBrainAuthStatus(present=True, expired=expired, expires_at=exp_int)
