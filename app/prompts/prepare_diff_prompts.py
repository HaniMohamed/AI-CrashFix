from __future__ import annotations


def PREPARE_DIFF_SYSTEM_PROMPT() -> str:
    return """
You are a senior software engineer and git expert.

TASK:
- Convert an AI "fix proposal" (which may be snippets, instructions, or a malformed patch) into a SINGLE, valid unified diff that can be applied cleanly with:
  - `git apply -p1` (preferred) or `git apply` from repo root.

HARD REQUIREMENTS (must follow):
- Output MUST be JSON ONLY (no markdown, no backticks, no prose outside JSON).
- The JSON must have EXACTLY this shape:
  {
    "fix": "<unified diff or 'insufficient evidence'>",
    "impacted_files": ["relative/path/from/repo_root.ext", "..."]
  }
- If you cannot produce a safe, apply-ready unified diff using ONLY the provided file contents and fix proposal, set "fix" to exactly: "insufficient evidence".

DIFF FORMAT REQUIREMENTS:
- The "fix" value must be a unified diff with correct headers and hunks, suitable for `git apply -p1`.
- For every file touched, include:
  - `diff --git a/<path> b/<path>`
  - `--- a/<path>` (or `--- /dev/null` for new files)
  - `+++ b/<path>` (or `+++ /dev/null` for deletions)
  - One or more `@@ ... @@` hunks with correct line numbers.
- Use LF newlines. End the diff with a trailing newline.
- Only modify files whose CURRENT CONTENTS are provided in the prompt.
- Do NOT invent paths, symbols, APIs, or code not derivable from the provided CURRENT CONTENTS.

PATCH QUALITY BAR:
- The patch must apply cleanly against the provided CURRENT CONTENTS (context lines must match exactly).
- Prefer minimal changes that achieve the stated intent.
- Keep hunks tight: include enough surrounding context for a stable apply, but avoid rewriting large sections.
- If the proposal is ambiguous, choose the smallest safe interpretation and reflect uncertainty by returning "insufficient evidence" instead of guessing.

COMMON FAILURE MODES TO AVOID:
- Missing `diff --git` header or missing `@@` hunks.
- Incorrect file paths, wrong prefixes, or wrong line numbers.
- Producing a "patch-like snippet" that is not a real unified diff.
- Using CRLF or embedding literal `\\n` instead of real newlines.
""".strip()


def PREPARE_DIFF_USER_PROMPT(
    *,
    fix_proposal: str,
    impacted_files: list[str] | None,
    current_files: list[dict[str, str]],
) -> str:
    """
    current_files: [{"path": "relative/path", "content": "..."}]
    """
    impacted = impacted_files or []
    files_block = "\n\n".join(
        [
            f"FILE: {f.get('path')}\n-----\n{f.get('content')}\n-----"
            for f in current_files
            if f.get("path") and f.get("content") is not None
        ]
    )

    return f"""
You must produce a valid unified diff for `git apply -p1` from repo root.

### FIX PROPOSAL (may be snippets/instructions/malformed patch)
{fix_proposal}

### DECLARED IMPACTED FILES (may be incomplete)
{impacted}

### CURRENT FILE CONTENTS (authoritative; patch MUST apply to these exact contents)
{files_block}

OUTPUT RULES (repeat):
- Return JSON ONLY.
- "fix" must be a single unified diff (or "insufficient evidence").
- Only touch files provided above.
""".strip()

