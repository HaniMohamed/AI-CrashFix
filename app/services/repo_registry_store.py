from __future__ import annotations

import hashlib
import json
import os
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any, ClassVar


def _data_dir() -> Path | None:
    raw = (os.environ.get("AI_CRASH_FIX_DATA_DIR") or "").strip()
    if not raw:
        return None
    try:
        return Path(raw).expanduser().resolve()
    except Exception:
        return None


def resolve_repo_registry_db_path(db_path: str | None = None) -> str:
    path = (db_path or os.environ.get("AI_CRASH_FIX_REPO_REGISTRY_DB") or "").strip()
    if not path:
        base = _data_dir()
        if base is not None:
            path = os.fspath((base / "db" / "repo_registry.db").resolve())
        else:
            path = "db/repo_registry.db"
    p = Path(path).expanduser().resolve()
    p.parent.mkdir(parents=True, exist_ok=True)
    return str(p)


def compute_repo_key(*, repo_url: str, repo_ref: str | None) -> str:
    """
    Stable 12-char key derived from repo_url + repo_ref.
    Must match the key used by ProjectService.prepare_repo().
    """
    url = (repo_url or "").strip()
    ref = (repo_ref or "").strip() or ""
    if not url:
        raise ValueError("repo_url is required")
    key = f"{url}@{ref}".encode("utf-8")
    return hashlib.sha1(key).hexdigest()[:12]


@dataclass(frozen=True)
class RepoEntry:
    repo_key: str
    name: str
    repo_url: str
    repo_ref: str | None
    firebase_project_id: str | None
    has_token: bool
    packages_dirs: list[str]
    crashlytics_fetch_backend: str | None
    bq_dataset: str | None
    bq_android_table: str | None
    bq_ios_table: str | None
    jira_server_url: str | None
    jira_email: str | None
    has_jira_token: bool
    jira_issue_type: str | None
    jira_project_key: str | None
    jira_create_fields: str | None
    jira_create_mode: str | None
    jira_parent_issue_key: str | None
    gitlab_project: str | None
    crashlytics_android_package: str | None
    crashlytics_ios_bundle_id: str | None
    has_google_application_credentials: bool
    created_at: str
    updated_at: str
    last_selected_at: str | None


@dataclass(frozen=True)
class RepoIndexStatus:
    repo_key: str
    indexed_sha: str | None
    last_indexed_at: str | None
    last_error: str | None


def normalize_jira_create_mode(value: str | None) -> str:
    mode = (value or "").strip().lower()
    if mode in {"under_parent", "sub_issue", "subtask", "sub-bug", "child"}:
        return "under_parent"
    return "standalone"


def normalize_packages_dirs(value: str | list[str] | None) -> list[str]:
    """
    Normalize user-provided package roots (repo-scoped).

    Accepts:
    - None
    - list[str]
    - JSON-encoded list[str] (stored format)
    - comma-separated string (legacy / UI convenience)
    """
    if value is None:
        return []
    raw: list[str] = []
    if isinstance(value, list):
        raw = [str(x) for x in value]
    else:
        s = str(value).strip()
        if not s:
            return []
        # Prefer JSON storage format.
        if s.startswith("[") and s.endswith("]"):
            try:
                parsed = json.loads(s)
                if isinstance(parsed, list):
                    raw = [str(x) for x in parsed]
                else:
                    raw = []
            except Exception:
                raw = []
        else:
            raw = [p.strip() for p in s.split(",")]

    out: list[str] = []
    seen: set[str] = set()
    for p in raw:
        p = (p or "").strip().strip("/").strip()
        if not p:
            continue
        # Keep it safe: repo-relative only.
        if p.startswith(("/", "\\")):
            continue
        if ".." in p.split("/"):
            continue
        if p in seen:
            continue
        seen.add(p)
        out.append(p)
    return out


def _row_get(row: Any, key: str) -> Any:
    if hasattr(row, "keys"):
        keys = row.keys()
        if key not in keys:
            return None
        return row[key]
    if isinstance(row, dict):
        return row.get(key)
    return None


def _ts_field(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value.strip() or None
    try:
        return value.isoformat()
    except Exception:
        s = str(value).strip()
        return s or None


def row_to_repo_entry(row: Any) -> RepoEntry:
    pdirs = normalize_packages_dirs(_row_get(row, "packages_dirs"))
    access = _row_get(row, "access_token")
    jira_tok = _row_get(row, "jira_token")
    gcp_creds = _row_get(row, "google_application_credentials")
    created = _ts_field(_row_get(row, "created_at")) or ""
    updated = _ts_field(_row_get(row, "updated_at")) or ""
    return RepoEntry(
        repo_key=row["repo_key"],
        name=row["name"],
        repo_url=row["repo_url"],
        repo_ref=row["repo_ref"] if _row_get(row, "repo_ref") else None,
        firebase_project_id=row["firebase_project_id"] if _row_get(row, "firebase_project_id") else None,
        has_token=bool(access),
        packages_dirs=pdirs,
        crashlytics_fetch_backend=_row_get(row, "crashlytics_fetch_backend") or None,
        bq_dataset=_row_get(row, "bq_dataset") or None,
        bq_android_table=_row_get(row, "bq_android_table") or None,
        bq_ios_table=_row_get(row, "bq_ios_table") or None,
        jira_server_url=_row_get(row, "jira_server_url") or None,
        jira_email=_row_get(row, "jira_email") or None,
        has_jira_token=bool(jira_tok),
        jira_issue_type=_row_get(row, "jira_issue_type") or None,
        jira_project_key=_row_get(row, "jira_project_key") or None,
        jira_create_fields=_row_get(row, "jira_create_fields") or None,
        jira_create_mode=normalize_jira_create_mode(_row_get(row, "jira_create_mode")),
        jira_parent_issue_key=_row_get(row, "jira_parent_issue_key") or None,
        gitlab_project=_row_get(row, "gitlab_project") or None,
        crashlytics_android_package=_row_get(row, "crashlytics_android_package") or None,
        crashlytics_ios_bundle_id=_row_get(row, "crashlytics_ios_bundle_id") or None,
        has_google_application_credentials=bool(
            (str(gcp_creds).strip() if gcp_creds is not None else "")
        ),
        created_at=created,
        updated_at=updated,
        last_selected_at=_ts_field(_row_get(row, "last_selected_at")),
    )


def _singleton_key(db_path: str | None = None) -> str:
    from app.services.crash_store import uses_postgres_crash_store
    from app.services.user_context import resolve_user_id

    if uses_postgres_crash_store():
        user_id = resolve_user_id(required=True)
        return f"postgres:{user_id}"
    return f"sqlite:{resolve_repo_registry_db_path(db_path)}"


class RepoRegistryStore:
    """
    Repo registry facade (SQLite local files or shared Postgres).

    One process-wide instance is reused per backend + (user_id or db_path).
    """

    _shared: ClassVar[dict[str, RepoRegistryStore]] = {}
    _shared_lock: ClassVar[threading.Lock] = threading.Lock()

    def __new__(cls, db_path: str | None = None) -> RepoRegistryStore:
        key = _singleton_key(db_path)
        with cls._shared_lock:
            existing = cls._shared.get(key)
            if existing is not None:
                return existing
            obj = super().__new__(cls)
            cls._shared[key] = obj
            obj._singleton_ready = False  # type: ignore[attr-defined]
            obj._singleton_key = key  # type: ignore[attr-defined]
            return obj

    def __init__(self, db_path: str | None = None) -> None:
        if getattr(self, "_singleton_ready", False):
            return
        from app.services.crash_store import uses_postgres_crash_store

        if uses_postgres_crash_store():
            from app.services.repo_registry_postgres import PostgresRepoRegistryStore

            self._impl = PostgresRepoRegistryStore()
        else:
            from app.services.repo_registry_sqlite import SqliteRepoRegistryStore

            self._impl = SqliteRepoRegistryStore(db_path=db_path)
        self.db_path = self._impl.db_path
        self._singleton_ready = True

    @classmethod
    def clear_shared_for_tests(cls) -> None:
        with cls._shared_lock:
            cls._shared.clear()

    def list_repos(self) -> list[RepoEntry]:
        return self._impl.list_repos()

    def upsert_repo(
        self,
        *,
        name: str,
        repo_url: str,
        repo_ref: str | None,
        firebase_project_id: str | None = None,
        access_token: str | None = None,
        packages_dirs: str | list[str] | None = None,
        crashlytics_fetch_backend: str | None = None,
        bq_dataset: str | None = None,
        bq_android_table: str | None = None,
        bq_ios_table: str | None = None,
        jira_project_key: str | None = None,
        jira_server_url: str | None = None,
        jira_email: str | None = None,
        jira_token: str | None = None,
        jira_issue_type: str | None = None,
        jira_create_fields: str | None = None,
        jira_create_mode: str | None = None,
        jira_parent_issue_key: str | None = None,
        gitlab_project: str | None = None,
        crashlytics_android_package: str | None = None,
        crashlytics_ios_bundle_id: str | None = None,
    ) -> RepoEntry:
        return self._impl.upsert_repo(
            name=name,
            repo_url=repo_url,
            repo_ref=repo_ref,
            firebase_project_id=firebase_project_id,
            access_token=access_token,
            packages_dirs=packages_dirs,
            crashlytics_fetch_backend=crashlytics_fetch_backend,
            bq_dataset=bq_dataset,
            bq_android_table=bq_android_table,
            bq_ios_table=bq_ios_table,
            jira_project_key=jira_project_key,
            jira_server_url=jira_server_url,
            jira_email=jira_email,
            jira_token=jira_token,
            jira_issue_type=jira_issue_type,
            jira_create_fields=jira_create_fields,
            jira_create_mode=jira_create_mode,
            jira_parent_issue_key=jira_parent_issue_key,
            gitlab_project=gitlab_project,
            crashlytics_android_package=crashlytics_android_package,
            crashlytics_ios_bundle_id=crashlytics_ios_bundle_id,
        )

    def get_repo(self, repo_key: str) -> RepoEntry | None:
        return self._impl.get_repo(repo_key)

    def get_access_token(self, repo_key: str) -> str | None:
        return self._impl.get_access_token(repo_key)

    def get_jira_token(self, repo_key: str) -> str | None:
        return self._impl.get_jira_token(repo_key)

    def get_google_application_credentials(self, repo_key: str) -> str | None:
        return self._impl.get_google_application_credentials(repo_key)

    def set_google_application_credentials(self, repo_key: str, path: str | None) -> RepoEntry:
        return self._impl.set_google_application_credentials(repo_key, path)

    def clear_legacy_repo_jira_base_config(self, repo_key: str) -> RepoEntry:
        """
        Clear legacy repo-scoped Jira base settings (server/email/token).

        Jira base config is now owned by global/common settings only.
        """
        return self._impl.clear_legacy_repo_jira_base_config(repo_key)

    def get_active_repo_key(self) -> str | None:
        return self._impl.get_active_repo_key()

    def set_active_repo(self, repo_key: str) -> RepoEntry:
        return self._impl.set_active_repo(repo_key)

    def get_active_repo(self) -> RepoEntry | None:
        return self._impl.get_active_repo()

    def delete_repo(self, repo_key: str) -> None:
        self._impl.delete_repo(repo_key)


    def get_app_state(self, key: str) -> str | None:
        return self._impl.get_app_state(key)

    def set_app_state(self, key: str, value: str | None) -> None:
        self._impl.set_app_state(key, value)

    def get_index_status(self, repo_key: str) -> RepoIndexStatus | None:
        return self._impl.get_index_status(repo_key)

    def upsert_index_status(
        self,
        *,
        repo_key: str,
        indexed_sha: str | None,
        last_indexed_at: str | None,
        last_error: str | None,
    ) -> RepoIndexStatus:
        return self._impl.upsert_index_status(
            repo_key=repo_key,
            indexed_sha=indexed_sha,
            last_indexed_at=last_indexed_at,
            last_error=last_error,
        )
