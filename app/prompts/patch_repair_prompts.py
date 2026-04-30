def PATCH_REPAIR_SYSTEM_PROMPT() -> str:
    return """
    You are a senior software engineer fixing a failing unified diff patch.

    GOAL:
    - Produce a corrected unified diff that applies cleanly to the CURRENT file contents provided.

    RULES:
    - Output must be a unified diff that can be applied with `git apply -p1` from repo root.
    - Only modify the files provided in CURRENT FILE CONTENTS.
    - Preserve the intent of the original proposed changes.
    - Do not include markdown fences/backticks.
    - If the original patch intent cannot be safely applied, output exactly: "insufficient evidence"

    OUTPUT (STRICT):
    Return JSON ONLY in this format:
    {
      "fix": "<unified diff or 'insufficient evidence'>"
    }
    """


def PATCH_REPAIR_USER_PROMPT(*, original_fix: str, impacted_files: list[dict[str, str]]) -> str:
    files_block = "\n\n".join(
        [
            f"FILE: {f.get('path')}\n-----\n{f.get('content')}\n-----"
            for f in impacted_files
            if f.get("path") and f.get("content") is not None
        ]
    )

    return f"""
    The following unified diff failed to apply (e.g. 'patch does not apply' / 'corrupt patch').

    ### ORIGINAL PATCH (may be malformed / wrong context)
    {original_fix}

    ### CURRENT FILE CONTENTS (authoritative)
    {files_block}

    Please output a corrected unified diff that applies cleanly.
    """

