"""Authentication business logic: passwords, sessions, user lifecycle."""

from __future__ import annotations

import hashlib
import re
import secrets
import string
from datetime import datetime, timedelta, timezone
from typing import Any

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

from app.services.auth_context import AuthenticatedSession
from app.services.auth_models import AuthUserRecord
from app.services.auth_store import AuthStore
from app.services.user_context import normalize_user_id

_ph = PasswordHasher()

# Defaults (overridable via auth_settings)
DEFAULT_SESSION_HOURS = 24
DEFAULT_MAX_FAILED_LOGINS = 5
DEFAULT_LOCKOUT_MINUTES = 15
DEFAULT_MIN_PASSWORD_LENGTH = 12

_COMMON_PASSWORDS = frozenset(
    {
        "password12345",
        "changeme12345",
        "fixora123456",
        "admin12345678",
    }
)

_USERNAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{2,63}$")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _parse_dt(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        s = str(raw).strip()
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def hash_password(password: str) -> str:
    return _ph.hash(password)


def verify_password(password_hash: str, password: str) -> bool:
    try:
        return _ph.verify(password_hash, password)
    except VerifyMismatchError:
        return False


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def generate_token() -> str:
    return secrets.token_urlsafe(32)


def generate_temp_password(length: int = 16) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def normalize_username(username: str) -> str:
    return (username or "").strip().lower()


def validate_username(username: str) -> str:
    uname = normalize_username(username)
    if not _USERNAME_RE.match(uname):
        raise ValueError(
            "Username must be 3–64 chars: lowercase letters, digits, . _ -"
        )
    return uname


def validate_new_password(
    password: str,
    *,
    min_length: int = DEFAULT_MIN_PASSWORD_LENGTH,
    reject: str | None = None,
) -> str:
    pwd = (password or "").strip()
    if len(pwd) < min_length:
        raise ValueError(f"Password must be at least {min_length} characters")
    if pwd.lower() in _COMMON_PASSWORDS:
        raise ValueError("Password is too common; choose a stronger password")
    if reject and pwd == reject:
        raise ValueError("New password must differ from the temporary password")
    return pwd


class AuthService:
    def __init__(self, store: AuthStore | None = None) -> None:
        self._store = store or AuthStore()

    def _session_hours(self) -> int:
        raw = self._store.get_setting("session_hours", str(DEFAULT_SESSION_HOURS))
        try:
            return max(1, min(168, int(raw or DEFAULT_SESSION_HOURS)))
        except ValueError:
            return DEFAULT_SESSION_HOURS

    def _max_failed_logins(self) -> int:
        raw = self._store.get_setting("max_failed_logins", str(DEFAULT_MAX_FAILED_LOGINS))
        try:
            return max(3, min(20, int(raw or DEFAULT_MAX_FAILED_LOGINS)))
        except ValueError:
            return DEFAULT_MAX_FAILED_LOGINS

    def _lockout_minutes(self) -> int:
        raw = self._store.get_setting("lockout_minutes", str(DEFAULT_LOCKOUT_MINUTES))
        try:
            return max(5, min(120, int(raw or DEFAULT_LOCKOUT_MINUTES)))
        except ValueError:
            return DEFAULT_LOCKOUT_MINUTES

    def _min_password_length(self) -> int:
        raw = self._store.get_setting("min_password_length", str(DEFAULT_MIN_PASSWORD_LENGTH))
        try:
            return max(8, min(128, int(raw or DEFAULT_MIN_PASSWORD_LENGTH)))
        except ValueError:
            return DEFAULT_MIN_PASSWORD_LENGTH

    def bootstrap_status(self) -> dict[str, Any]:
        from app.services.store_bootstrap import (
            can_configure_store_without_auth,
            current_store_config_public,
            is_store_setup_complete,
        )

        store_complete = is_store_setup_complete()
        count = 0
        try:
            count = self._store.count_users()
        except Exception:
            count = 0
        # Auth users imply the store is in use even if bootstrap file is missing
        # (e.g. launch-env Postgres fell back to SQLite mid-session).
        if count > 0:
            store_complete = True
        needs_admin = store_complete and count == 0
        return {
            "needs_store_setup": not store_complete,
            "needs_admin": needs_admin,
            "has_users": count > 0,
            "user_count": count,
            "store_setup_complete": store_complete,
            "can_configure_store_without_auth": can_configure_store_without_auth(),
            "store": current_store_config_public(),
        }

    def bootstrap_admin(
        self,
        *,
        username: str,
        tenant_user_id: str | None = None,
        temp_password: str | None = None,
    ) -> dict[str, Any]:
        from app.services.store_bootstrap import is_store_setup_complete

        if not is_store_setup_complete():
            raise ValueError(
                "Configure the database before creating an administrator"
            )
        if self._store.count_users() > 0:
            raise ValueError("Administrator already exists")
        uname = validate_username(username)
        tenant = normalize_user_id(tenant_user_id) or uname
        if not tenant:
            raise ValueError("tenant_user_id is required")
        temp = (temp_password or "").strip() or generate_temp_password()
        if len(temp) < 8:
            raise ValueError("Temporary password must be at least 8 characters")
        user = self._store.create_user(
            username=uname,
            tenant_user_id=tenant,
            role="admin",
            password_hash=hash_password(temp),
            must_change_password=True,
            created_by_user_id=None,
        )
        self._store.write_audit(
            actor_user_id=user.id,
            action="bootstrap_admin",
            target_user_id=user.id,
        )
        return {
            "user": user.to_public_dict(),
            "temp_password": temp,
        }

    def login(
        self,
        username: str,
        password: str,
        *,
        user_agent: str | None = None,
    ) -> dict[str, Any]:
        uname = normalize_username(username)
        user = self._store.get_user_by_username(uname)
        if user is None:
            raise ValueError("Invalid username or password")
        if user.status == "blocked":
            raise ValueError("Account is blocked")
        locked_until = _parse_dt(user.locked_until)
        if locked_until and locked_until > _now():
            raise ValueError("Account is temporarily locked; try again later")
        if not verify_password(user.password_hash, password):
            max_fail = self._max_failed_logins()
            lock_min = self._lockout_minutes()
            new_count = user.failed_login_count + 1
            lock_iso: str | None = None
            if new_count >= max_fail:
                lock_iso = (_now() + timedelta(minutes=lock_min)).isoformat()
            self._store.record_failed_login(user.id, lock_iso)
            raise ValueError("Invalid username or password")
        self._store.clear_failed_login(user.id)
        token = generate_token()
        expires = (_now() + timedelta(hours=self._session_hours())).isoformat()
        session = self._store.create_session(
            user_id=user.id,
            token_hash=hash_token(token),
            expires_at=expires,
            user_agent=user_agent,
        )
        fresh = self._store.get_user_by_id(user.id)
        assert fresh is not None
        self._store.write_audit(
            actor_user_id=fresh.id,
            action="login",
            target_user_id=fresh.id,
        )
        return {
            "token": token,
            "session_id": session.id,
            "user": fresh.to_public_dict(),
            "must_change_password": fresh.must_change_password,
        }

    def authenticate_token(self, token: str) -> AuthenticatedSession | None:
        raw = (token or "").strip()
        if not raw:
            return None
        session = self._store.get_session_by_token_hash(hash_token(raw))
        if session is None or session.revoked_at:
            return None
        expires = _parse_dt(session.expires_at)
        if expires is None or expires <= _now():
            return None
        user = self._store.get_user_by_id(session.user_id)
        if user is None or user.status == "blocked":
            return None
        self._store.touch_session(session.id)
        return AuthenticatedSession(user=user, session_id=session.id, token=raw)

    def logout(self, session_id: str, actor_id: str) -> None:
        self._store.revoke_session(session_id)
        self._store.write_audit(
            actor_user_id=actor_id,
            action="logout",
            target_user_id=actor_id,
        )

    def change_password(
        self,
        user: AuthUserRecord,
        *,
        current_password: str | None,
        new_password: str,
    ) -> AuthUserRecord:
        if user.must_change_password:
            # Session proves the user already authenticated (e.g. with a temp password).
            reject_temp: str | None = None
        else:
            current = (current_password or "").strip()
            if not current:
                raise ValueError("Current password is required")
            if not verify_password(user.password_hash, current):
                raise ValueError("Current password is incorrect")
            reject_temp = current
        min_len = self._min_password_length()
        new_pwd = validate_new_password(
            new_password,
            min_length=min_len,
            reject=reject_temp,
        )
        updated = self._store.update_user_password(
            user.id,
            hash_password(new_pwd),
            must_change_password=False,
        )
        if updated is None:
            raise ValueError("User not found")
        self._store.write_audit(
            actor_user_id=user.id,
            action="change_password",
            target_user_id=user.id,
        )
        return updated

    def list_users_public(self) -> list[dict[str, Any]]:
        return [u.to_public_dict() for u in self._store.list_users()]

    def create_user(
        self,
        actor: AuthUserRecord,
        *,
        username: str,
        tenant_user_id: str | None = None,
        role: str = "user",
    ) -> dict[str, Any]:
        if actor.role != "admin":
            raise PermissionError("Admin only")
        uname = validate_username(username)
        if self._store.get_user_by_username(uname):
            raise ValueError("Username already exists")
        tenant = normalize_user_id(tenant_user_id) or uname
        if role not in ("admin", "user"):
            raise ValueError("role must be admin or user")
        temp = generate_temp_password()
        user = self._store.create_user(
            username=uname,
            tenant_user_id=tenant,
            role=role,
            password_hash=hash_password(temp),
            must_change_password=True,
            created_by_user_id=actor.id,
        )
        self._store.write_audit(
            actor_user_id=actor.id,
            action="create_user",
            target_user_id=user.id,
            details={"username": uname, "role": role},
        )
        return {"user": user.to_public_dict(), "temp_password": temp}

    def update_user(
        self,
        actor: AuthUserRecord,
        target_id: str,
        *,
        status: str | None = None,
        role: str | None = None,
    ) -> AuthUserRecord:
        if actor.role != "admin":
            raise PermissionError("Admin only")
        target = self._store.get_user_by_id(target_id)
        if target is None:
            raise ValueError("User not found")
        if status is not None:
            if status not in ("active", "blocked"):
                raise ValueError("status must be active or blocked")
            if target.id == actor.id and status == "blocked":
                raise ValueError("Cannot block your own account")
            self._store.update_user_status(target_id, status)
            if status == "blocked":
                self._store.revoke_all_sessions_for_user(target_id)
            self._store.write_audit(
                actor_user_id=actor.id,
                action="update_user_status",
                target_user_id=target_id,
                details={"status": status},
            )
        if role is not None:
            if role not in ("admin", "user"):
                raise ValueError("role must be admin or user")
            admins = [u for u in self._store.list_users() if u.role == "admin"]
            if target.role == "admin" and role != "admin" and len(admins) <= 1:
                raise ValueError("Cannot remove the last admin")
            if target.id == actor.id and role != "admin":
                raise ValueError("Cannot demote your own admin role")
            self._store.update_user_role(target_id, role)
            self._store.write_audit(
                actor_user_id=actor.id,
                action="update_user_role",
                target_user_id=target_id,
                details={"role": role},
            )
        updated = self._store.get_user_by_id(target_id)
        if updated is None:
            raise ValueError("User not found")
        return updated

    def delete_user(self, actor: AuthUserRecord, target_id: str) -> None:
        if actor.role != "admin":
            raise PermissionError("Admin only")
        if actor.id == target_id:
            raise ValueError("Cannot delete your own account")
        target = self._store.get_user_by_id(target_id)
        if target is None:
            raise ValueError("User not found")
        if target.role == "admin":
            admins = [u for u in self._store.list_users() if u.role == "admin"]
            if len(admins) <= 1:
                raise ValueError("Cannot delete the last admin")
        self._store.revoke_all_sessions_for_user(target_id)
        if not self._store.delete_user(target_id):
            raise ValueError("User not found")
        self._store.write_audit(
            actor_user_id=actor.id,
            action="delete_user",
            target_user_id=target_id,
        )

    def reset_password(self, actor: AuthUserRecord, target_id: str) -> dict[str, Any]:
        if actor.role != "admin":
            raise PermissionError("Admin only")
        target = self._store.get_user_by_id(target_id)
        if target is None:
            raise ValueError("User not found")
        temp = generate_temp_password()
        updated = self._store.update_user_password(
            target_id,
            hash_password(temp),
            must_change_password=True,
        )
        if updated is None:
            raise ValueError("User not found")
        self._store.revoke_all_sessions_for_user(target_id)
        self._store.write_audit(
            actor_user_id=actor.id,
            action="reset_password",
            target_user_id=target_id,
        )
        return {"user": updated.to_public_dict(), "temp_password": temp}

    def get_security_settings(self) -> dict[str, Any]:
        return {
            "session_hours": self._session_hours(),
            "max_failed_logins": self._max_failed_logins(),
            "lockout_minutes": self._lockout_minutes(),
            "min_password_length": self._min_password_length(),
        }

    def update_security_settings(
        self,
        actor: AuthUserRecord,
        *,
        session_hours: int | None = None,
        max_failed_logins: int | None = None,
        lockout_minutes: int | None = None,
        min_password_length: int | None = None,
    ) -> dict[str, Any]:
        if actor.role != "admin":
            raise PermissionError("Admin only")
        if session_hours is not None:
            self._store.set_setting("session_hours", str(max(1, min(168, session_hours))))
        if max_failed_logins is not None:
            self._store.set_setting(
                "max_failed_logins", str(max(3, min(20, max_failed_logins)))
            )
        if lockout_minutes is not None:
            self._store.set_setting(
                "lockout_minutes", str(max(5, min(120, lockout_minutes)))
            )
        if min_password_length is not None:
            self._store.set_setting(
                "min_password_length", str(max(8, min(128, min_password_length)))
            )
        self._store.write_audit(actor_user_id=actor.id, action="update_security_settings")
        return self.get_security_settings()

    def list_audit(self, actor: AuthUserRecord, limit: int = 100) -> list[dict[str, Any]]:
        if actor.role != "admin":
            raise PermissionError("Admin only")
        return self._store.list_audit(limit=limit)
