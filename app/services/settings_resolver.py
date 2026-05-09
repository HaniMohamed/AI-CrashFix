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


@dataclass(frozen=True)
class EffectiveJiraConfig:
    server_url: str | None
    verify_ssl: str | None
    token: str | None
    project_key: str | None


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
    """

    def __init__(self) -> None:
        self._app = AppSettingsStore()
        self._repos = RepoRegistryStore()

    def _app_str(self, key: str) -> str | None:
        v = self._app.get(k=key)
        if isinstance(v, str):
            s = v.strip()
            return s or None
        return None

    def _app_secret(self, key: str) -> str | None:
        # Stored as plain string; never returned in /api/settings but used here.
        return self._app_str(key)

    def effective_google_application_credentials(self) -> str | None:
        return self._app_str("GOOGLE_APPLICATION_CREDENTIALS") or (cfg.GOOGLE_APPLICATION_CREDENTIALS or None)

    def effective_llm_provider(self) -> str:
        return self._app_str("LLM_PROVIDER") or (cfg.LLM_PROVIDER or "gemini")

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
        return EffectiveCrashlyticsConfig(
            backend=(backend or "bigquery").strip().lower(),
            bq_dataset=(dataset or "firebase_crashlytics").strip(),
            bq_android_table=(android_table or "").strip(),
            bq_ios_table=(ios_table or "").strip(),
        )

    def effective_jira(self, *, repo_key: str | None) -> EffectiveJiraConfig:
        repo = self._repos.get_repo((repo_key or "").strip()) if (repo_key or "").strip() else None
        return EffectiveJiraConfig(
            server_url=self._app_str("JIRA_SERVER_URL") or cfg.JIRA_SERVER_URL,
            verify_ssl=self._app_str("JIRA_VERIFY_SSL") or cfg.JIRA_VERIFY_SSL,
            token=self._app_secret("JIRA_TOKEN") or cfg.JIRA_TOKEN,
            project_key=(repo.jira_project_key if repo else None) or cfg.JIRA_PROJECT_KEY,
        )

    def effective_gitlab(self, *, repo_key: str | None) -> EffectiveGitlabConfig:
        repo = self._repos.get_repo((repo_key or "").strip()) if (repo_key or "").strip() else None
        return EffectiveGitlabConfig(
            server_url=self._app_str("GITLAB_SERVER_URL") or cfg.GITLAB_SERVER_URL,
            verify_ssl=self._app_str("GITLAB_VERIFY_SSL") or cfg.GITLAB_VERIFY_SSL,
            token=self._app_secret("GITLAB_TOKEN") or cfg.GITLAB_TOKEN,
            ca_bundle=self._app_str("GITLAB_SSL_CA_BUNDLE") or cfg.GITLAB_SSL_CA_BUNDLE,
            project=(repo.gitlab_project if repo else None) or cfg.GITLAB_PROJECT,
        )

