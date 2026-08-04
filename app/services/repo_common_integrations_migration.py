"""One-time cleanup of legacy repo-scoped integration base credentials."""

from __future__ import annotations

import logging

from app.services.repo_registry_store import RepoRegistryStore

_log = logging.getLogger(__name__)

_MIGRATION_FLAG = "repo_common_integrations_cleanup_v1"


def migrate_repo_common_integrations_cleanup(*, force: bool = False) -> dict[str, int]:
    """
    Clear legacy repo-level Jira base settings (server/email/token).

    Jira base credentials are global/common settings now.
    Idempotent via app_state flag.
    """
    reg = RepoRegistryStore()
    if not force and (reg.get_app_state(_MIGRATION_FLAG) or "").strip() == "1":
        return {"repos_updated": 0, "skipped": 1}

    updated = 0
    for entry in reg.list_repos():
        if not (
            (entry.jira_server_url or "").strip()
            or (entry.jira_email or "").strip()
            or entry.has_jira_token
        ):
            continue
        reg.clear_legacy_repo_jira_base_config(entry.repo_key)
        updated += 1

    reg.set_app_state(_MIGRATION_FLAG, "1")
    if updated:
        _log.info("Cleared legacy repo Jira base credentials on %s repo(s)", updated)
    return {"repos_updated": updated, "skipped": 0}

