"""One-shot repair prompt for a unified diff that failed `git apply`.

Used by `generate_pr_node` when the originally generated diff's context lines no
longer match the target file (the file drifted between analysis and apply time,
or the model's line context was slightly off). Given the actual current file
content, the model re-derives a diff that applies cleanly instead of failing outright.
"""

from __future__ import annotations

from typing import Mapping


def DIFF_REPAIR_SYSTEM_PROMPT() -> str:
    return (
        "You are repairing a unified diff that failed to apply with `git apply` because the "
        "target file's current content no longer matches the diff's context lines. "
        "You will receive the failed diff, the git apply error, and the CURRENT full content "
        "of each impacted file. Produce a corrected unified diff that implements the SAME fix "
        "intent but applies cleanly against the CURRENT file content shown below.\n\n"
        "Each line of the CURRENT file content is prefixed with its real 1-indexed file line "
        "number followed by `: ` (e.g. `480: final x = foo();`). Use these exact numbers for "
        "the `@@ -start,count +start,count @@` hunk headers. The `N: ` prefix is reference "
        "only — never include it in the diff's `-`/`+`/context line content itself.\n\n"
        'Return strict JSON only: {"fix": "<corrected unified diff>"}. '
        'If the fix is no longer applicable at all, return {"fix": "insufficient evidence"}.'
    )


def DIFF_REPAIR_PROMPT_INPUT(
    *,
    root_cause: str,
    fix_rationale: str,
    failed_patch: str,
    error_message: str,
    current_files: Mapping[str, str],
) -> str:
    files_block = "\n\n".join(
        f"--- CURRENT CONTENT: {path} ---\n{content}" for path, content in current_files.items()
    )
    return (
        f"Root cause:\n{root_cause}\n\n"
        f"Intended fix:\n{fix_rationale}\n\n"
        f"Failed diff:\n{failed_patch}\n\n"
        f"git apply error:\n{error_message}\n\n"
        f"Current file content:\n{files_block}\n\n"
        "Regenerate a corrected unified diff that applies cleanly to the CURRENT content above."
    )
