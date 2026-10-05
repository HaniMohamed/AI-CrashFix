from app.brand import PR_BODY_FOOTER as _PR_BODY_AI_FOOTER
from app.brand import PR_TITLE_PREFIX as _PR_TITLE_AI_HEADER
from app.graph.state import CrashState
from app.prompts.pr_fix_prompts import PR_FIX_PROMPT_INPUT, PR_SYSTEM_PROMPT
from app.services.ai_service import LLMService
from app.services.crash_store import CrashStore
from app.services.git_service import GitService
from app.utils.llm_helpers import parse_json_object
from app import config as cfg


def generate_pr_node(state: CrashState):
    """
    Best-effort GitLab draft MR from a unified diff.

    Order: validate inputs → LLM for PR title, body, and commit message (title seeds the feature-branch slug) →
    branch from main → apply patch → normalize title/body for storage and GitLab → commit scoped paths →
    push → open draft MR.

    Failures are recorded on `pr_error`; the node always returns updated `state` so the graph can finish.
    """
    state.pop("pr_error", None)
    crash_id = state.get("crash_id")

    # --- Preconditions: must have an applyable patch and a Jira key (MR workflow keys off it). ---
    patch = (state.get("generated_fix") or "").strip()
    if not patch or patch.lower() == "insufficient evidence":
        state["pr_title"] = state.get("pr_title") or "No fix generated"
        state["pr_body"] = state.get("pr_body") or "No fix generated"
        state["pr_error"] = "Missing or insufficient generated_fix; skipping PR creation."
        return state

    jira_issue_id = state.get("jira_issue_id")
    if state.get("skip_jira_creation"):
        jira_issue_id = ""
    if not state.get("skip_jira_creation") and (not jira_issue_id or not str(jira_issue_id).strip()):
        state["pr_error"] = "Missing jira_issue_id; skipping PR creation."
        return state

    try:
        jira = str(jira_issue_id).strip().upper() or "NOJIRA"

        repo_root = (state.get("repo_root") or cfg.REPO_ROOT or "").strip()
        repo_key = (state.get("repo_key") or "").strip() or None
        git = GitService(repo_root=repo_root, repo_key=repo_key)
        fpid = (state.get("firebase_project_id") or "").strip() or None
        crash_store = CrashStore(repo_key=repo_key, project_id=fpid)

        # --- Step 1: LLM proposes MR title, description, and git commit subject (title is used for branch slug). ---
        llm = LLMService()
        pr_meta = parse_json_object(
            llm.call(
                system_prompt=PR_SYSTEM_PROMPT(),
                user_prompt=PR_FIX_PROMPT_INPUT(state),
            ),
            context="generate_pr",
        )
        state["pr_title"] = pr_meta.get("pr_title") or ""
        state["pr_body"] = pr_meta.get("pr_body") or ""
        state["commit_message"] = (pr_meta.get("commit_message") or "").strip() or None

        # --- Step 2: reuse the existing feature branch on a feedback regeneration; otherwise branch from main. ---
        is_regeneration = bool((state.get("pr_branch") or "").strip() and (state.get("pr_url") or "").strip())
        base_branch = (state.get("repo_ref") or "").strip() or None
        if is_regeneration:
            branch = state["pr_branch"].strip()
            git.checkout_existing_branch(branch)
            branch_info = {"branch": branch, "base": base_branch or "main"}
        else:
            branch_slug_title = (state["pr_title"] or "").strip() or "CrashLens fix"
            branch_info = git.create_branch_from_main(
                jira_ticket_id=jira,
                title=branch_slug_title,
                base_branch=base_branch,
            )
            branch = branch_info["branch"]
            state["pr_branch"] = branch
        if crash_id:
            crash_store.set_pipeline_flags(crash_id, branch_created=True)

        # --- Step 3: apply the fixer's unified diff to REPO_ROOT (normalization + git apply inside GitService). ---
        git.apply_unified_diff(patch)
        if crash_id:
            crash_store.set_pipeline_flags(crash_id, diff_applied=True)

        # --- Step 4: normalize copy for storage and GitLab (prefix stored title, append disclosure footer on body). ---
        pr_title = (state["pr_title"] or "CrashLens fix").strip()
        pr_title = (_PR_TITLE_AI_HEADER + pr_title) if pr_title else _PR_TITLE_AI_HEADER.strip()
        pr_body = (state["pr_body"] or "").strip()
        pr_body = (pr_body + _PR_BODY_AI_FOOTER) if pr_body else _PR_BODY_AI_FOOTER.strip()
        state["pr_body"] = pr_body
        state["pr_title"] = pr_title

        # --- Step 5: commit only fix paths, push branch, open draft MR. ---
        commit_msg = state.get("commit_message") or f"{jira}: {pr_title}"
        impacted = state.get("fix_impacted_files") or []
        git.commit_changes(commit_msg, impacted if isinstance(impacted, list) else [])
        git.push_current_branch(branch_name=branch)

        if is_regeneration:
            existing_mr = git.find_open_merge_request(branch)
            if not existing_mr or not existing_mr.get("iid"):
                raise RuntimeError(f"No open merge request found for branch {branch!r} to update.")
            mr = git.update_merge_request(
                existing_mr["iid"],
                title=pr_title,
                description=pr_body,
            )
            state["pr_url"] = mr.get("web_url") or state.get("pr_url")
        else:
            mr = git.create_merge_request(
                source_branch=branch,
                target_branch=branch_info.get("base") or "main",
                title=pr_title,
                body=pr_body,
                draft=True,
            )
            state["pr_url"] = mr.get("pr_url")
        state["generated_diff"] = patch
        if crash_id:
            crash_store.set_pipeline_flags(
                crash_id,
                mr_created=True,
                pr_url=state.get("pr_url"),
            )
    except Exception as e:
        # LLM JSON parse, branch creation, git apply, commit, push, or GitLab API errors surface here for observability.
        state["pr_error"] = str(e)

    return state
