from __future__ import annotations

import re
from typing import Any

_RE_HUNK_HEADER = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$")
_RE_OLD_FILE = re.compile(r"^--- (?:a/)?(\S+)")
_RE_NEW_FILE = re.compile(r"^\+\+\+ (?:b/)?(\S+)")


def _file_path_from_marker(marker: str) -> str | None:
    if not marker or marker == "/dev/null":
        return None
    return marker


def parse_unified_diff(diff_text: str) -> list[dict[str, Any]]:
    """
    Split a unified diff into one entry per file:
    ``{path, old_path, additions, deletions, hunks: [{header, lines: [{type, old_no, new_no, text}]}]}``.

    Reuses GitService's existing normalization/repair helpers so malformed LLM diffs
    (flattened newlines, bad hunk counts, overlapping hunks) are fixed up before parsing.
    """
    from app.services.git_service import (
        _repair_overlapping_hunks,
        _repair_unified_diff_hunk_counts,
        _unflatten_llm_unified_diff,
    )

    text = diff_text or ""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = _unflatten_llm_unified_diff(text)
    text = _repair_unified_diff_hunk_counts(text)
    text = _repair_overlapping_hunks(text)
    text = _repair_unified_diff_hunk_counts(text)

    files: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    current_hunk: dict[str, Any] | None = None
    old_no = 0
    new_no = 0

    def _close_hunk() -> None:
        nonlocal current_hunk
        if current is not None and current_hunk is not None:
            current["hunks"].append(current_hunk)
        current_hunk = None

    def _close_file() -> None:
        nonlocal current
        _close_hunk()
        if current is not None:
            files.append(current)
        current = None

    for line in text.split("\n"):
        if line.startswith("diff --git "):
            _close_file()
            continue

        m_old = _RE_OLD_FILE.match(line)
        if m_old:
            old_path = _file_path_from_marker(m_old.group(1))
            if current is None or current.get("old_path") is not None:
                _close_file()
                current = {
                    "path": None,
                    "old_path": old_path,
                    "additions": 0,
                    "deletions": 0,
                    "hunks": [],
                }
            else:
                current["old_path"] = old_path
            continue

        m_new = _RE_NEW_FILE.match(line)
        if m_new:
            new_path = _file_path_from_marker(m_new.group(1))
            if current is None:
                current = {
                    "path": new_path,
                    "old_path": None,
                    "additions": 0,
                    "deletions": 0,
                    "hunks": [],
                }
            else:
                current["path"] = new_path or current.get("old_path")
            continue

        m_hunk = _RE_HUNK_HEADER.match(line)
        if m_hunk:
            if current is None:
                current = {
                    "path": None,
                    "old_path": None,
                    "additions": 0,
                    "deletions": 0,
                    "hunks": [],
                }
            _close_hunk()
            old_no = int(m_hunk.group(1))
            new_no = int(m_hunk.group(3))
            current_hunk = {"header": line, "lines": []}
            continue

        if current_hunk is None:
            # Preamble (index lines, mode changes, etc.) between file headers and the first hunk.
            continue

        if not line:
            continue

        tag = line[0]
        text_part = line[1:]
        if tag == "+":
            current_hunk["lines"].append(
                {"type": "add", "old_no": None, "new_no": new_no, "text": text_part}
            )
            new_no += 1
            current["additions"] += 1
        elif tag == "-":
            current_hunk["lines"].append(
                {"type": "del", "old_no": old_no, "new_no": None, "text": text_part}
            )
            old_no += 1
            current["deletions"] += 1
        elif tag == "\\":
            # "\ No newline at end of file" — not a content line.
            continue
        else:
            current_hunk["lines"].append(
                {"type": "context", "old_no": old_no, "new_no": new_no, "text": text_part}
            )
            old_no += 1
            new_no += 1

    _close_file()

    for f in files:
        if not f.get("path"):
            f["path"] = f.get("old_path")

    return files


def diff_stats(files: list[dict[str, Any]]) -> dict[str, int]:
    return {
        "files_changed": len(files),
        "additions": sum(int(f.get("additions") or 0) for f in files),
        "deletions": sum(int(f.get("deletions") or 0) for f in files),
    }
