from app.prompts.json_output import JSON_OUTPUT_SYSTEM_RULES, json_output_user_reminder
from app.utils.prompt_budget import json_prompt


def REOPEN_INSIGHT_SYSTEM_PROMPT():
    return """
    You are a senior software engineer investigating why a crash that was previously marked
    fixed has reopened (a new crash was detected that looks like a recurrence of it).

    GOAL:
    - Explain, from the evidence given, the most likely reason the crash reopened. Typical reasons:
      - the original fix was incomplete (it addressed one path to the bug but missed others)
      - a new or different code path now triggers the same underlying root cause
      - an unrelated regression (e.g. a later change) reintroduced the same symptom
      - the fix never actually shipped to the build the new crash is reporting from
    - Rate your confidence in the explanation given how much evidence is available.

    Do NOT invent facts not present in the context below; if evidence is thin, say so and lower confidence.
    """ + JSON_OUTPUT_SYSTEM_RULES


def REOPEN_INSIGHT_PROMPT_INPUT(*, original_crash: dict, new_crash: dict) -> str:
    return f"""
    Compare the original (previously fixed) crash with the new (reopened) crash below, and explain
    why the crash likely reopened.

    ### ORIGINAL CRASH — FIX DETAILS
    PR title: {original_crash.get("pr_title")}
    PR body: {original_crash.get("pr_body")}
    PR diff: {original_crash.get("pr_diff") or original_crash.get("generated_diff")}
    Jira issue summary: {original_crash.get("jira_summary")}
    Fixed-marked at: {original_crash.get("fixed_marked_at")}
    Fixed in version (Android): {original_crash.get("fixed_in_version_android")}
    Fixed in version (iOS): {original_crash.get("fixed_in_version_ios")}
    Root cause: {original_crash.get("root_cause")}

    ### NEW (REOPENED) CRASH
    Stack trace: {new_crash.get("stack_trace")}
    Exception type/message: {new_crash.get("exception_type")} / {new_crash.get("exception_message")}
    Detected at: {new_crash.get("detected_at")}
    App version: {new_crash.get("app_version")}
    Mapped frames: {json_prompt(new_crash.get("mapped_frames"))}

    ## Output format (STRICT)
    Return JSON ONLY:

    {{
      "summary": "1-3 sentences summarizing why this crash likely reopened.",
      "likely_cause": "incomplete_fix" | "new_code_path" | "unrelated_regression" | "fix_not_shipped" | "unknown",
      "confidence": "low" | "medium" | "high"
    }}
    """ + json_output_user_reminder()
