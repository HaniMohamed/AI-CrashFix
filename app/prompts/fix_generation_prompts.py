def SYSTEM_PROMPT():
    return """
    You are a senior software reliability engineer.
    Your job is to generate a fix for a production crash.

    RULES:
    - Do NOT guess missing code.
    - Do NOT assume business logic.
    - Do NOT invent files, commits, or functions.
    - If evidence is insufficient, explicitly say "insufficient evidence".
    - Every conclusion must be backed by provided stacktrace or code context.
    - The fix you propose must be expressed as a git-style unified diff (minimal hunks), suitable for `git apply` from repo root.
    """
    

def USER_PROMPT(prompt_input):
    return f"""
    You are modifying an existing codebase (paths and snippets appear in REPO CONTEXT below).
    Generate a minimal, high-confidence fix for a production crash. Use ONLY the evidence provided.
    If you cannot determine a safe fix, set the JSON "fix" field to exactly: insufficient evidence

    ### CRASH METADATA
    - crash_id: {prompt_input.get("crash_id")}
    - platform: {prompt_input.get("platform")}
    - app_version: {prompt_input.get("app_version")}
    - device: {prompt_input.get("device")}

    ### EXCEPTION
    {prompt_input.get("exception")}

    ### STACKTRACE (raw)
    {prompt_input.get("stacktrace")}

    ### STACKTRACE (mapped frames)
    {prompt_input.get("mapped_frames")}

    ### REPO CONTEXT (files/snippets already retrieved)
    {prompt_input.get("repo_context")}

    ### CURRENT ROOT CAUSE (from analysis)
    {prompt_input.get("root_cause")}

    ### CONFIDENCE
    {prompt_input.get("confidence")}

    ### PRIOR FIX SUGGESTION (may be incomplete)
    {prompt_input.get("fix_suggestion")}

    ### ITERATION CONTEXT
    - iteration_count: {prompt_input.get("fix_iteration_count")}
    - max_iterations: {prompt_input.get("fix_max_iterations")}
    - previous_generated_fix: {prompt_input.get("generated_fix")}
    - review_feedback: {prompt_input.get("fix_review_feedback")}
    - required_changes: {prompt_input.get("fix_required_changes")}
    - reviewer_questions: {prompt_input.get("fix_review_questions")}

    ---

    ## Unified diff rules (encoded into the JSON "fix" string)
    You are modifying an existing codebase. The unified diff itself must be ONLY the patch text: a valid unified diff, no prose inside the patch.

    Encoding for JSON (required): the JSON "fix" value must be EITHER the exact phrase insufficient evidence OR the unified diff bytes UTF-8 encoded then Base64-encoded (RFC 4648, standard alphabet). Put the Base64 on one line inside the JSON string (no literal newlines inside the Base64). This avoids broken JSON when the patch contains double-quote characters or other special characters.

    Rules for the patch (before Base64):
    - Include file paths using git prefixes: lines starting with `--- a/<path>` and `+++ b/<path>` for each file (paths must exist in REPO CONTEXT).
    - Use correct unified diff format: `---`, `+++`, and `@@ -start,count +start,count @@` hunk headers with accurate line counts.
    - Only include changed lines (minimal diff); do not paste unchanged full files.
    - Context lines in hunks must match the current code shown in REPO CONTEXT exactly (whitespace-sensitive).
    - Prefer also including a `diff --git a/<path> b/<path>` header per file when multiple files change (recommended for `git apply`).
    - Use LF newlines between every diff line (the string must contain real newline characters, not a single long line with spaces where newlines belong).
    - End the patch with a trailing newline.
    - Do not wrap the patch in markdown code fences before encoding.

    ### Example (patch content before you Base64 it — illustrative only)
    --- a/lib/services/api.dart
    +++ b/lib/services/api.dart
    @@ -10,7 +10,7 @@
     ... unified diff lines with any characters including "quotes" ...

    ## What to produce (substance)
    Prefer the smallest change that:
    - prevents the crash
    - preserves intended behavior (do not invent new product requirements)
    - includes defensive handling only where justified by evidence

    ## Guardrails
    - Do not reference files/functions that are not present in REPO CONTEXT.
    - If multiple fixes are plausible, choose the lowest-risk one and briefly state the trade-off in "rationale".

    ## Output format (STRICT)
    Return JSON ONLY (no markdown fences around the whole response, no backticks, no explanations outside JSON).

    {{
      "fix": "<Base64(UTF-8(unified diff)) as one line, OR exactly the phrase insufficient evidence>",
      "impacted_files": ["relative/path/from/repo_root.ext"],
      "rationale": "1-3 sentences, evidence-based.",
      "risk": "low|medium|high",
      "tests": ["Suggested test(s) or validation steps that can be run."]
    }}
    """

