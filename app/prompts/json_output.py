"""Shared instructions so LLM replies stay machine-parseable JSON."""

JSON_OUTPUT_SYSTEM_RULES = """
JSON OUTPUT (MANDATORY — downstream code uses a strict JSON parser):
- Reply with ONE JSON object only. No markdown, no code fences, no backticks.
- Do NOT write any text, labels, or commentary before or after the JSON.
- Your entire response MUST begin with `{` and end with `}`.
- Use standard JSON syntax: double-quoted keys and string values.
- Escape special characters inside JSON strings (e.g. newlines as \\n, quotes as \\" ).
- Never wrap the JSON in ```json ... ``` or any other delimiter.
"""


def json_output_user_reminder() -> str:
    return (
        "\n\nREMINDER: Output a single raw JSON object only. "
        "Start with `{` and end with `}`. No markdown fences or extra text."
    )
