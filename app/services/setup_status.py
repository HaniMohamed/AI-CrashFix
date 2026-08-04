"""Setup readiness checklist for Fixora self-serve onboarding."""

from __future__ import annotations

from typing import Any

from app.services.crash_store import crash_store_health, uses_postgres_crash_store
from app.services.repo_registry_store import RepoRegistryStore
from app.services.settings_resolver import SettingsResolver
from app.services.user_context import resolve_user_id

SETUP_PATH_KEY = "setup_path"
SETUP_COMPLETED_KEY = "setup_completed_at"


def _truthy_secret(value: Any) -> bool:
    return bool((value or "").strip()) if isinstance(value, str) else bool(value)


def compute_setup_status() -> dict[str, Any]:
    """
    Structured readiness used by the Setup Wizard and Help UI.

    ``next_step`` codes: welcome | llm | crashlytics | integrations | repo | first_run | done
    """
    try:
        return _compute_setup_status_inner()
    except Exception as exc:
        store_health = {"ok": False, "error": str(exc), "backend": "unknown"}
        try:
            store_health = crash_store_health()
        except Exception:
            pass
        return {
            "product": "Fixora",
            "setup_path": None,
            "setup_completed_at": None,
            "setup_complete": False,
            "next_step": "welcome",
            "missing": ["crash_store"],
            "checks": [
                {
                    "id": "crash_store",
                    "label": "Crash store",
                    "required": True,
                    "ok": False,
                    "detail": str(exc),
                }
            ],
            "provider": None,
            "user_id": None,
            "postgres": uses_postgres_crash_store(),
            "crash_store": store_health,
            "repo_count": 0,
            "has_active_repo": False,
            "error": str(exc),
        }


def _compute_setup_status_inner() -> dict[str, Any]:
    resolver = SettingsResolver()
    repos = RepoRegistryStore()
    store_health = crash_store_health()
    provider = resolver.effective_llm_provider()

    llm_ok = False
    llm_detail: str | None = None
    if provider == "gemini":
        llm_ok = _truthy_secret(resolver.effective_google().get("api_key"))
        llm_detail = None if llm_ok else "GOOGLE_API_KEY required for Gemini"
    elif provider == "openai":
        llm_ok = _truthy_secret(resolver.effective_openai().get("api_key"))
        llm_detail = None if llm_ok else "OPENAI_API_KEY required for OpenAI"
    elif provider == "gosi-brain":
        gb = resolver.effective_gosi_brain()
        has_auth = _truthy_secret(gb.get("authorization"))
        has_key = _truthy_secret(gb.get("api_key"))
        has_url = _truthy_secret(gb.get("url"))
        llm_ok = has_auth and has_key and has_url
        if not has_url:
            llm_detail = "GOSI_BRAIN_URL required"
        elif not has_auth:
            llm_detail = "GOSI_BRAIN_AUTHORIZATION required"
        elif not has_key:
            llm_detail = "GOSI_BRAIN_API_KEY required"
    else:
        llm_detail = f"Unknown LLM provider: {provider}"

    # Crashlytics / GCP is per-repo: project ID + SA JSON on the active repo
    # (else any configured repo). Mock path skips this requirement.
    active_for_gcp = repos.get_active_repo()
    gcp_repo = active_for_gcp
    if gcp_repo is None:
        for candidate in repos.list_repos():
            if (candidate.firebase_project_id or "").strip() or candidate.has_google_application_credentials:
                gcp_repo = candidate
                break
    gcp_repo_key = gcp_repo.repo_key if gcp_repo else None
    crash = resolver.effective_crashlytics(repo_key=gcp_repo_key)
    creds = crash.google_application_credentials
    bq_project = crash.firebase_project_id
    crashlytics_ok = bool((creds or "").strip()) and bool(bq_project)

    jira = resolver.effective_jira(repo_key=None)
    gitlab = resolver.effective_gitlab(repo_key=None)
    jira_partial = bool((jira.server_url or "").strip()) or bool((jira.token or "").strip())
    jira_ok = bool((jira.server_url or "").strip()) and bool((jira.token or "").strip())
    gitlab_partial = bool((gitlab.server_url or "").strip()) or bool((gitlab.token or "").strip())
    gitlab_ok = bool((gitlab.server_url or "").strip()) and bool((gitlab.token or "").strip())

    repo_list = repos.list_repos()
    has_repo = len(repo_list) > 0
    active = repos.get_active_repo()
    index_ok = False
    index_detail: str | None = None
    if active is not None:
        st = repos.get_index_status(active.repo_key)
        if st is not None and (st.indexed_sha or "").strip() and not (st.last_error or "").strip():
            index_ok = True
        elif st is not None and (st.last_error or "").strip():
            index_detail = st.last_error
        else:
            index_detail = "Repo not indexed yet — use Refresh in Manage repos"

    setup_path = repos.get_app_state(SETUP_PATH_KEY)  # mock | production | None
    completed_at = repos.get_app_state(SETUP_COMPLETED_KEY)

    postgres = uses_postgres_crash_store()
    user_id = resolve_user_id(required=False)
    user_id_ok = (not postgres) or bool((user_id or "").strip())

    store_ok = store_health.get("ok") is True

    checks: list[dict[str, Any]] = [
        {
            "id": "crash_store",
            "label": "Crash store",
            "required": True,
            "ok": store_ok,
            "detail": None if store_ok else store_health.get("error"),
        },
        {
            "id": "user_id",
            "label": "Machine user ID",
            "required": postgres,
            "ok": user_id_ok,
            "detail": None
            if user_id_ok
            else "Set AI_CRASH_FIX_USER_ID when using the Postgres store",
        },
        {
            "id": "llm",
            "label": "LLM provider",
            "required": True,
            "ok": llm_ok,
            "detail": llm_detail,
            "provider": provider,
        },
        {
            "id": "crashlytics",
            "label": "Crashlytics / GCP",
            "required": setup_path != "mock",
            "ok": crashlytics_ok if setup_path != "mock" else True,
            "detail": None
            if crashlytics_ok or setup_path == "mock"
            else (
                "On the Flutter repository, set Firebase/GCP project ID and upload a "
                "service account JSON (Manage repos or Setup wizard)."
            ),
            "has_credentials": bool((creds or "").strip()),
            "has_bq_project": bool(bq_project),
            "repo_key": gcp_repo_key,
        },
        {
            "id": "jira",
            "label": "Jira (optional)",
            "required": False,
            "ok": jira_ok or not jira_partial,
            "detail": None
            if jira_ok or not jira_partial
            else "Jira URL or token incomplete — finish both or clear both",
            "configured": jira_ok,
        },
        {
            "id": "gitlab",
            "label": "GitLab (optional)",
            "required": False,
            "ok": gitlab_ok or not gitlab_partial,
            "detail": None
            if gitlab_ok or not gitlab_partial
            else "GitLab URL or token incomplete — finish both or clear both",
            "configured": gitlab_ok,
        },
        {
            "id": "repo",
            "label": "Flutter repository",
            "required": True,
            "ok": has_repo,
            "detail": None if has_repo else "Add at least one Flutter app repository",
            "count": len(repo_list),
        },
        {
            "id": "index",
            "label": "Symbol index",
            "required": has_repo,
            "ok": (not has_repo) or index_ok,
            "detail": index_detail if has_repo and not index_ok else None,
        },
    ]

    missing = [c["id"] for c in checks if c.get("required") and not c.get("ok")]

    if not llm_ok:
        next_step = "llm"
    elif setup_path is None and not completed_at:
        next_step = "welcome"
    elif setup_path != "mock" and not crashlytics_ok:
        next_step = "crashlytics"
    elif not has_repo:
        next_step = "repo"
    elif has_repo and not index_ok:
        next_step = "repo"
    elif not completed_at:
        next_step = "first_run"
    else:
        next_step = "done"

    # Welcome takes priority only when nothing configured yet
    if not llm_ok and setup_path is None and not has_repo and not completed_at:
        next_step = "welcome"

    setup_complete = bool(completed_at) and not missing
    # Allow mock path to complete without crashlytics
    if setup_path == "mock" and llm_ok and has_repo and completed_at:
        setup_complete = True
        missing = [m for m in missing if m != "crashlytics"]

    # Legacy installs (pre-wizard): already have LLM + repo → treat as onboarded.
    if not completed_at and llm_ok and has_repo:
        setup_complete = True
        next_step = "done"
        missing = [m for m in missing if m not in ("repo", "index", "crashlytics")]

    return {
        "product": "Fixora",
        "setup_path": setup_path,
        "setup_completed_at": completed_at,
        "setup_complete": setup_complete,
        "next_step": next_step,
        "missing": missing,
        "checks": checks,
        "provider": provider,
        "user_id": user_id,
        "postgres": postgres,
        "crash_store": store_health,
        "repo_count": len(repo_list),
        "has_active_repo": active is not None,
    }
