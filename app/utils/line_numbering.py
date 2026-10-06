"""Shared helper for showing an LLM real file line numbers.

`git apply` rejects a unified diff whose `@@ -start,count +start,count @@` headers
don't match the target file's actual line numbers. Code snippets handed to the
fix-generation and diff-repair prompts were previously raw text with no indication
of which absolute line each row sits on, so the model had to guess the hunk header
numbers — a frequent, silent cause of "patch does not apply" failures. Annotating
snippets with their real line number gives the model ground truth to work from.
"""

from __future__ import annotations


def annotate_with_line_numbers(text: str, *, start_line: int = 1) -> str:
    """Prefix each line of ``text`` with its real 1-indexed file line number."""
    if not text:
        return text
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    for i, line in enumerate(lines):
        no = start_line + i
        if line.endswith("\n"):
            out.append(f"{no}: {line[:-1]}\n")
        else:
            out.append(f"{no}: {line}")
    return "".join(out)
