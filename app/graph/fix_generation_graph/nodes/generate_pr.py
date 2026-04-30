from app.graph.state import CrashState
from app.prompts.pr_fix_prompts import PR_FIX_PROMPT_INPUT, PR_SYSTEM_PROMPT
from app.prompts.patch_repair_prompts import PATCH_REPAIR_SYSTEM_PROMPT, PATCH_REPAIR_USER_PROMPT
from app.services.ai_service import LLMService
from app.services.git_service import GitService
from app.utils.llm_helpers import parse_json

def generate_pr_node(state: CrashState):
    # LangGraph nodes must return a dict update (state), not a routing string.
    # Treat PR creation as "best effort": record errors in state and continue.
    state.pop("pr_error", None)

    if not state.get("generated_diff"):
        state["pr_title"] = state.get("pr_title") or "No fix generated"
        state["pr_body"] = state.get("pr_body") or "No fix generated"
        state["pr_error"] = "Missing generated_diff; skipping PR creation."
        return state

    jira_issue_id = state.get("jira_issue_id")
    if not jira_issue_id:
        state["pr_error"] = "Missing jira_issue_id; skipping PR creation."
        return state

    try:
        # 1) Generate PR title and body
        llm = LLMService()
        response = llm.call(
            system_prompt=PR_SYSTEM_PROMPT(),
            user_prompt=PR_FIX_PROMPT_INPUT(state),
        )
        parsed = parse_json(response)
        state["pr_title"] = parsed["pr_title"]
        state["pr_body"] = parsed["pr_body"]

        # 2) Create branch from main
        git_service = GitService()
        pr_title = state.get("pr_title") or "CrashLens fix"
        pr_body = state.get("pr_body") or ""

        # 3) Create branch from main
        branch_info = git_service.create_branch_from_main(jira_ticket_id=jira_issue_id, title=pr_title)
        state["pr_branch"] = branch_info.get("branch")

        # 4) Apply the generated diff into the working tree
        diff_text = state.get("generated_diff") or ""
        try:
            git_service.apply_unified_diff(diff_text)
        except Exception as e:
            msg = str(e)
            is_apply_failure = any(
                needle in msg.lower()
                for needle in [
                    "patch does not apply",
                    "patch failed",
                    "corrupt patch",
                    "failed to apply diff",
                ]
            )
            if not is_apply_failure:
                raise

            impacted_files = state.get("fix_impacted_files") or git_service._extract_paths_from_diff(diff_text)
            file_payload: list[dict[str, str]] = []
            for p in impacted_files[:5]:
                try:
                    file_payload.append({"path": p, "content": git_service.read_repo_file(p)})
                except Exception:
                    continue

            if not file_payload:
                raise RuntimeError(f"Patch failed to apply and no impacted files could be loaded.\n\n{msg}") from e

            repaired_raw = llm.call(
                system_prompt=PATCH_REPAIR_SYSTEM_PROMPT(),
                user_prompt=PATCH_REPAIR_USER_PROMPT(original_fix=diff_text, impacted_files=file_payload),
            )
            repaired_parsed = parse_json(repaired_raw)
            repaired_fix = (repaired_parsed.get("fix") or "").strip()
            if not repaired_fix or repaired_fix == "insufficient evidence":
                raise RuntimeError(f"Patch repair returned insufficient evidence.\n\nOriginal error:\n{msg}")

            state["generated_diff"] = repaired_fix
            git_service.apply_unified_diff(repaired_fix)

        # 5) Commit + push the fix
        commit_msg = f"{jira_issue_id.strip().upper()}: {pr_title.strip()}"
        git_service.commit_all(commit_msg)
        git_service.push_current_branch(branch_name=state["pr_branch"])

        # 6) Create PR (GitLab merge request) after pushed commit exists
        mr = git_service.create_merge_request(
            source_branch=state["pr_branch"],
            target_branch=branch_info.get("base") or "main",
            title=commit_msg,
            body=pr_body,
            draft=True,
        )
        state["pr_url"] = mr.get("pr_url")
    except Exception as e:
        state["pr_error"] = str(e)

    return state