"""One-time seed of per-repo GCP fields from legacy global settings / env."""

from __future__ import annotations

import logging
from pathlib import Path

from app import config as cfg
from app.services.app_settings_store import AppSettingsStore
from app.services.repo_registry_store import RepoRegistryStore

_log = logging.getLogger(__name__)

_MIGRATION_FLAG = "gcp_creds_migrated_to_repos_v1"


def migrate_global_gcp_to_repos(*, force: bool = False) -> dict[str, int]:
    """
    Copy global BQ_PROJECT_ID / GOOGLE_APPLICATION_CREDENTIALS onto repos that
    are missing those fields. Idempotent via app_state flag.
    """
    reg = RepoRegistryStore()
    if not force and (reg.get_app_state(_MIGRATION_FLAG) or "").strip() == "1":
        return {"repos_updated": 0, "skipped": 1}

    store = AppSettingsStore()
    global_fpid = None
    raw_bq = store.get(k="BQ_PROJECT_ID")
    if isinstance(raw_bq, str) and raw_bq.strip():
        global_fpid = raw_bq.strip()
    if not global_fpid:
        global_fpid = (cfg.BQ_PROJECT_ID or "").strip() or None

    global_creds = None
    raw_creds = store.get(k="GOOGLE_APPLICATION_CREDENTIALS")
    if isinstance(raw_creds, str) and raw_creds.strip():
        global_creds = raw_creds.strip()
    if not global_creds:
        global_creds = (cfg.GOOGLE_APPLICATION_CREDENTIALS or "").strip() or None
    if global_creds and not Path(global_creds).expanduser().is_file():
        _log.warning("Global GCP credentials path missing on disk: %s", global_creds)
        global_creds = None

    updated = 0
    for entry in reg.list_repos():
        need_fpid = not (entry.firebase_project_id or "").strip() and bool(global_fpid)
        need_creds = (
            not entry.has_google_application_credentials and bool(global_creds)
        )
        if not need_fpid and not need_creds:
            continue
        if need_fpid:
            # Preserve other fields via upsert using current entry values.
            reg.upsert_repo(
                name=entry.name,
                repo_url=entry.repo_url,
                repo_ref=entry.repo_ref,
                firebase_project_id=global_fpid,
                packages_dirs=list(entry.packages_dirs or []),
                crashlytics_fetch_backend=entry.crashlytics_fetch_backend,
                bq_dataset=entry.bq_dataset,
                bq_android_table=entry.bq_android_table,
                bq_ios_table=entry.bq_ios_table,
                jira_project_key=entry.jira_project_key,
                jira_server_url=entry.jira_server_url,
                jira_email=entry.jira_email,
                jira_issue_type=entry.jira_issue_type,
                jira_create_fields=entry.jira_create_fields,
                jira_create_mode=entry.jira_create_mode,
                jira_parent_issue_key=entry.jira_parent_issue_key,
                gitlab_project=entry.gitlab_project,
                crashlytics_android_package=entry.crashlytics_android_package,
                crashlytics_ios_bundle_id=entry.crashlytics_ios_bundle_id,
            )
        if need_creds and global_creds:
            try:
                reg.set_google_application_credentials(entry.repo_key, global_creds)
            except LookupError:
                # Upsert may have changed key only if url/ref changed — shouldn't.
                pass
        updated += 1

    reg.set_app_state(_MIGRATION_FLAG, "1")
    if updated:
        _log.info("Migrated global GCP settings onto %s repo(s)", updated)
    return {"repos_updated": updated, "skipped": 0}
