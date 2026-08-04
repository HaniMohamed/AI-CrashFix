from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from app import config as cfg
from app.services.app_settings_store import AppSettingsStore
from app.services.repo_registry_store import RepoRegistryStore


@dataclass(frozen=True)
class EffectiveCrashlyticsConfig:
    backend: str
    bq_dataset: str
    bq_android_table: str
    bq_ios_table: str
    android_package_default: str | None
    ios_bundle_id_default: str | None
    firebase_project_id: str | None
    google_application_credentials: str | None


@dataclass(frozen=True)
class EffectiveJiraConfig:
    server_url: str | None
    email: str | None
    verify_ssl: str | None
    auth: str | None
    token: str | None
    project_key: str | None
    issue_type: str | None
    create_fields_json: str | None
    create_mode: str | None
    parent_issue_key: str | None


@dataclass(frozen=True)
class EffectiveGitlabConfig:
    server_url: str | None
    verify_ssl: str | None
    token: str | None
    ca_bundle: str | None
    project: str | None


class SettingsResolver:
    """
    Resolve effective configuration using precedence:
      repo-scoped (if repo_key provided) -> global app_settings -> env (.env via app.config)

    GCP project ID and service-account JSON are repo-owned (plus bootstrap .env for CLI).
    """

    def __init__(self) -> None:
        self._app = AppSettingsStore()
        self._repos = RepoRegistryStore()
        # One SQLite read for all keys (cached in AppSettingsStore until next set).
        self._kv = self._app.get_all()

    def _app_get(self, key: str) -> Any | None:
        return self._kv.get(key)

    def _app_str(self, key: str) -> str | None:
        v = self._app_get(key)
        if isinstance(v, str):
            s = v.strip()
            return s or None
        return None

    def _app_secret(self, key: str) -> str | None:
        # Stored as plain string; never returned in /api/settings but used here.
        return self._app_str(key)

    def effective_google_application_credentials(
        self, *, repo_key: str | None = None
    ) -> str | None:
        rk = (repo_key or "").strip()
        if rk:
            path = self._repos.get_google_application_credentials(rk)
            if path:
                return path
        # Bootstrap / CLI only — not app_settings (product UI is per-repo).
        return (cfg.GOOGLE_APPLICATION_CREDENTIALS or "").strip() or None

    def effective_firebase_project_id(self, *, repo_key: str | None = None) -> str | None:
        rk = (repo_key or "").strip()
        if rk:
            repo = self._repos.get_repo(rk)
            if repo and (repo.firebase_project_id or "").strip():
                return (repo.firebase_project_id or "").strip()
        return (cfg.BQ_PROJECT_ID or "").strip() or None

    def effective_llm_provider(self) -> str:
        raw = self._app_str("LLM_PROVIDER") or (cfg.LLM_PROVIDER or "gemini")
        return (raw or "gemini").strip().lower()

    def effective_openai(self) -> dict[str, Any]:
        return {
            "api_key": self._app_secret("OPENAI_API_KEY") or cfg.OPENAI_API_KEY,
            "model": self._app_str("OPENAI_MODEL") or cfg.OPENAI_MODEL,
            "url": self._app_str("OPENAI_URL") or cfg.OPENAI_URL,
        }

    def effective_google(self) -> dict[str, Any]:
        return {
            "api_key": self._app_secret("GOOGLE_API_KEY") or cfg.GOOGLE_API_KEY,
            "model": self._app_str("GEMINI_MODEL") or cfg.GEMINI_MODEL,
        }

    def _app_number(self, key: str) -> int | float | None:
        v = self._app_get(key)
        if isinstance(v, bool):
            return None
        if isinstance(v, int) and not isinstance(v, bool):
            return v
        if isinstance(v, float):
            return v
        if isinstance(v, str) and v.strip():
            s = v.strip()
            try:
                if "." in s or "e" in s.lower():
                    return float(s)
                return int(s)
            except ValueError:
                return None
        return None

    def effective_gosi_brain(self) -> dict[str, Any]:
        url = self._app_str("GOSI_BRAIN_URL") or cfg.GOSI_BRAIN_URL
        model_store = self._app_str("GOSI_BRAIN_MODEL")
        model = (model_store or (cfg.GOSI_BRAIN_MODEL or "") or "").strip() or None
        oauth = (
            self._app_str("GOSI_BRAIN_OAUTH_IDENTITY_DOMAIN_NAME")
            or cfg.GOSI_BRAIN_OAUTH_IDENTITY_DOMAIN_NAME
        )
        oauth = (oauth or "").strip() or None
        send_oauth_raw = self._app_str("GOSI_BRAIN_SEND_OAUTH_DOMAIN")
        if send_oauth_raw is not None:
            send_oauth = send_oauth_raw.strip().lower() in ("1", "true", "yes", "on")
        else:
            send_oauth = bool(cfg.GOSI_BRAIN_SEND_OAUTH_DOMAIN)
        t_raw = self._app_number("GOSI_BRAIN_TEMPERATURE")
        if isinstance(t_raw, (int, float)):
            temperature = float(t_raw)
        else:
            temperature = float(cfg.GOSI_BRAIN_TEMPERATURE)
    
        max_bytes_raw = self._app_number("GOSI_BRAIN_MAX_REQUEST_BYTES")
        if isinstance(max_bytes_raw, (int, float)) and max_bytes_raw > 0:
            max_request_bytes = int(max_bytes_raw)
        else:
            max_request_bytes = int(cfg.GOSI_BRAIN_MAX_REQUEST_BYTES)

        compaction = (
            self._app_str("GOSI_BRAIN_PROMPT_COMPACTION") or cfg.GOSI_BRAIN_PROMPT_COMPACTION or "auto"
        )
        compaction = (compaction or "auto").strip().lower()

        timeout_raw = self._app_number("GOSI_BRAIN_TIMEOUT")
        if isinstance(timeout_raw, (int, float)) and timeout_raw > 0:
            timeout = int(timeout_raw)
        else:
            timeout = int(cfg.GOSI_BRAIN_TIMEOUT)

        connect_raw = self._app_number("GOSI_BRAIN_CONNECT_TIMEOUT")
        if isinstance(connect_raw, (int, float)) and connect_raw > 0:
            connect_timeout = int(connect_raw)
        else:
            connect_timeout = int(cfg.GOSI_BRAIN_CONNECT_TIMEOUT)

        gzip_raw = self._app_str("GOSI_BRAIN_GZIP_REQUEST")
        if gzip_raw is not None:
            gzip_request = gzip_raw.strip().lower() in ("1", "true", "yes", "on")
        else:
            gzip_request = bool(cfg.GOSI_BRAIN_GZIP_REQUEST)

        # Single identity: AI_CRASH_FIX_USER_ID wins everywhere; ignore GOSI_BRAIN_USER_ID.
        from app.services.user_context import ai_crash_fix_user_id_raw

        crash_fix_uid = ai_crash_fix_user_id_raw()
        if crash_fix_uid:
            user_id = crash_fix_uid
        else:
            user_id = self._app_str("GOSI_BRAIN_USER_ID") or cfg.GOSI_BRAIN_USER_ID
        cookie = self._app_secret("GOSI_BRAIN_COOKIE") or cfg.GOSI_BRAIN_COOKIE

        idle_raw = self._app_number("GOSI_BRAIN_IDLE_TIMEOUT")
        if isinstance(idle_raw, (int, float)) and idle_raw > 0:
            idle_timeout = int(idle_raw)
        else:
            idle_timeout = int(cfg.GOSI_BRAIN_IDLE_TIMEOUT)

        streaming = (
            self._app_str("GOSI_BRAIN_STREAMING") or cfg.GOSI_BRAIN_STREAMING or "auto"
        )
        streaming = (streaming or "auto").strip().lower()
        if streaming not in ("auto", "on", "off"):
            streaming = "auto"

        waf_raw = self._app_str("GOSI_BRAIN_WAF_CONTENT_SHIELD")
        if waf_raw is not None:
            waf_shield = waf_raw.strip().lower() not in ("0", "false", "no", "off")
        else:
            waf_shield = bool(cfg.GOSI_BRAIN_WAF_CONTENT_SHIELD)

        return {
            "url": (url or "").strip() or None,
            "model": model,
            "authorization": self._app_secret("GOSI_BRAIN_AUTHORIZATION") or cfg.GOSI_BRAIN_AUTHORIZATION,
            "api_key": self._app_secret("GOSI_BRAIN_API_KEY") or cfg.GOSI_BRAIN_API_KEY,
            "oauth_domain": oauth,
            "send_oauth_domain": send_oauth,
            "user_id": (user_id or "").strip() or None,
            "cookie": (cookie or "").strip() or None,
            "temperature": temperature,
            "max_request_bytes": max_request_bytes,
            "prompt_compaction": compaction,
            "timeout": timeout,
            "connect_timeout": connect_timeout,
            "idle_timeout": idle_timeout,
            "streaming_mode": streaming,
            "waf_content_shield": waf_shield,
            "gzip_request": gzip_request,
        }

    def effective_crashlytics(self, *, repo_key: str | None) -> EffectiveCrashlyticsConfig:
        repo = self._repos.get_repo((repo_key or "").strip()) if (repo_key or "").strip() else None
        backend = (
            (repo.crashlytics_fetch_backend if repo else None)
            or self._app_str("CRASHLYTICS_FETCH_BACKEND")
            or cfg.CRASHLYTICS_FETCH_BACKEND
        )
        dataset = (
            (repo.bq_dataset if repo else None)
            or self._app_str("BQ_DATASET")
            or cfg.BQ_DATASET
        )
        android_table = (
            (repo.bq_android_table if repo else None)
            or self._app_str("BQ_CRASHLYTICS_ANDROID_TABLE")
            or cfg.BQ_CRASHLYTICS_ANDROID_TABLE
        )
        ios_table = (
            (repo.bq_ios_table if repo else None)
            or self._app_str("BQ_CRASHLYTICS_IOS_TABLE")
            or cfg.BQ_CRASHLYTICS_IOS_TABLE
        )
        android_pkg = (
            (repo.crashlytics_android_package if repo else None)
            or self._app_str("CRASHLYTICS_ANDROID_PACKAGE")
            or cfg.CRASHLYTICS_ANDROID_PACKAGE_DEFAULT
        )
        ios_bundle = (
            (repo.crashlytics_ios_bundle_id if repo else None)
            or self._app_str("CRASHLYTICS_IOS_BUNDLE_ID")
            or cfg.CRASHLYTICS_IOS_BUNDLE_ID_DEFAULT
        )
        fpid = self.effective_firebase_project_id(repo_key=repo_key)
        creds = self.effective_google_application_credentials(repo_key=repo_key)
        return EffectiveCrashlyticsConfig(
            backend=(backend or "bigquery").strip().lower(),
            bq_dataset=(dataset or "firebase_crashlytics").strip(),
            bq_android_table=(android_table or "").strip(),
            bq_ios_table=(ios_table or "").strip(),
            android_package_default=(android_pkg or "").strip() or None,
            ios_bundle_id_default=(ios_bundle or "").strip() or None,
            firebase_project_id=fpid,
            google_application_credentials=creds,
        )

    def effective_jira(self, *, repo_key: str | None) -> EffectiveJiraConfig:
        rk = (repo_key or "").strip()
        repo = self._repos.get_repo(rk) if rk else None
        repo_token = self._repos.get_jira_token(rk) if rk else None
        issue_default = (cfg.JIRA_ISSUE_TYPE or "Bug").strip() or "Bug"
        it_raw = (repo.jira_issue_type if repo else None) or self._app_str("JIRA_ISSUE_TYPE") or issue_default
        it_norm = (it_raw or "Bug").strip() or "Bug"
        from app.services.repo_registry_store import normalize_jira_create_mode

        return EffectiveJiraConfig(
            server_url=(repo.jira_server_url if repo else None)
            or self._app_str("JIRA_SERVER_URL")
            or cfg.JIRA_SERVER_URL,
            email=(repo.jira_email if repo else None) or self._app_str("JIRA_EMAIL") or cfg.JIRA_EMAIL,
            verify_ssl=self._app_str("JIRA_VERIFY_SSL") or cfg.JIRA_VERIFY_SSL,
            auth=self._app_str("JIRA_AUTH") or cfg.JIRA_AUTH,
            token=repo_token or self._app_secret("JIRA_TOKEN") or cfg.JIRA_TOKEN,
            project_key=(repo.jira_project_key if repo else None)
            or self._app_str("JIRA_PROJECT_KEY")
            or cfg.JIRA_PROJECT_KEY,
            issue_type=it_norm,
            create_fields_json=(repo.jira_create_fields if repo else None)
            or self._app_str("JIRA_CREATE_FIELDS")
            or cfg.JIRA_CREATE_FIELDS,
            create_mode=normalize_jira_create_mode(repo.jira_create_mode if repo else None),
            parent_issue_key=(repo.jira_parent_issue_key if repo else None),
        )

    def effective_gitlab(self, *, repo_key: str | None) -> EffectiveGitlabConfig:
        from app.utils.gitlab_url import (
            derive_gitlab_project_path_from_repo_url,
            derive_gitlab_server_url_from_repo_url,
        )

        rk = (repo_key or "").strip()
        repo = self._repos.get_repo(rk) if rk else None
        gl_project = (repo.gitlab_project if repo else None) or None
        if not gl_project and repo and repo.repo_url:
            gl_project = derive_gitlab_project_path_from_repo_url(repo.repo_url)
        # Prefer explicit global setting; otherwise derive from the repo remote URL
        # (Manage repos stores the full git URL, not GITLAB_SERVER_URL).
        derived_server = (
            derive_gitlab_server_url_from_repo_url(repo.repo_url)
            if repo and repo.repo_url
            else None
        )
        repo_token = self._repos.get_access_token(rk) if rk else None
        return EffectiveGitlabConfig(
            server_url=self._app_str("GITLAB_SERVER_URL")
            or cfg.GITLAB_SERVER_URL
            or derived_server,
            verify_ssl=self._app_str("GITLAB_VERIFY_SSL") or cfg.GITLAB_VERIFY_SSL,
            token=self._app_secret("GITLAB_TOKEN") or cfg.GITLAB_TOKEN or repo_token,
            ca_bundle=self._app_str("GITLAB_SSL_CA_BUNDLE") or cfg.GITLAB_SSL_CA_BUNDLE,
            project=gl_project or cfg.GITLAB_PROJECT,
        )

