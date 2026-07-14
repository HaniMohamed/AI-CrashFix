from __future__ import annotations

import json
from typing import Any, Mapping

from app.utils.llm_helpers import extract_top_commits

# Compaction levels: 0 = default gosi-brain trim, 1 = moderate, 2 = aggressive.
MAX_COMPACTION_LEVEL = 2

_LEVEL1_SNIPPET_LINES = 40
_LEVEL2_SNIPPET_LINES = 15
_LEVEL1_DIFF_LINES = 80
_LEVEL1_MAX_FRAMES = 5
_LEVEL2_MAX_FRAMES = 3
_LEVEL1_MAX_COMMITS = 3


def json_prompt(value: Any) -> str:
    """Compact JSON for LLM prompt sections."""
    if value is None:
        return "null"
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _trim_lines(text: str | None, max_lines: int) -> str | None:
    if not text or max_lines <= 0:
        return text
    lines = text.splitlines()
    if len(lines) <= max_lines:
        return text
    head = lines[:max_lines]
    return "\n".join(head) + f"\n… [{len(lines) - max_lines} lines truncated]"


def compact_diff_for_prompt(diff: str | None, max_lines: int = _LEVEL1_DIFF_LINES) -> str | None:
    if diff is None:
        return None
    t = diff.strip()
    if not t:
        return diff
    return _trim_lines(t, max_lines)


def compact_repo_context(
    repo_context: Any,
    level: int,
    *,
    omit_redundant_snippets: bool = False,
) -> list[dict[str, Any]]:
    if not isinstance(repo_context, list):
        return []

    out: list[dict[str, Any]] = []
    max_frames = _LEVEL2_MAX_FRAMES if level >= 2 else _LEVEL1_MAX_FRAMES
    snippet_lines = _LEVEL2_SNIPPET_LINES if level >= 2 else (_LEVEL1_SNIPPET_LINES if level >= 1 else None)
    max_commits = _LEVEL1_MAX_COMMITS if level >= 1 else 5

    for frame in repo_context[:max_frames]:
        if not isinstance(frame, dict):
            continue
        item = dict(frame)
        method_block = item.get("method_block")
        code_snippet = item.get("code_snippet")

        if omit_redundant_snippets and method_block:
            item.pop("code_snippet", None)
        elif snippet_lines is not None and isinstance(code_snippet, str):
            item["code_snippet"] = _trim_lines(code_snippet, snippet_lines)

        if snippet_lines is not None and isinstance(method_block, str):
            item["method_block"] = _trim_lines(method_block, snippet_lines)

        commits = item.get("recent_commits")
        if isinstance(commits, list) and len(commits) > max_commits:
            item["recent_commits"] = commits[:max_commits]

        out.append(item)
    return out


def compact_mapped_frames(mapped_frames: Any, level: int) -> list[dict[str, Any]]:
    if not isinstance(mapped_frames, list):
        return []
    max_frames = _LEVEL2_MAX_FRAMES if level >= 2 else _LEVEL1_MAX_FRAMES
    return [f for f in mapped_frames[:max_frames] if isinstance(f, dict)]


def compact_crash_prompt_input(
    state: Mapping[str, Any],
    level: int,
    *,
    include_previous_fix: bool = True,
) -> dict[str, Any]:
    """
    Build a prompt-safe dict from CrashState with progressive compaction.
    Level 0: drop redundant raw stacktrace when mapped frames exist; trim repo context.
    Level 1+: tighter snippets, diff caps, fewer commits.
    Level 2: fewer frames; optionally drop previous_generated_fix on generate_fix retries.
    """
    level = max(0, min(int(level), MAX_COMPACTION_LEVEL))
    mapped = compact_mapped_frames(state.get("mapped_frames"), level)
    repo_ctx = compact_repo_context(
        state.get("repo_context"),
        level,
        omit_redundant_snippets=True,
    )

    include_raw_stack = not mapped
    raw_stack = state.get("stacktrace") if include_raw_stack else None

    generated_fix = state.get("generated_fix")
    if level >= 1 and isinstance(generated_fix, str):
        generated_fix = compact_diff_for_prompt(generated_fix, _LEVEL1_DIFF_LINES)

    previous_fix = state.get("generated_fix")
    if level >= 1 and isinstance(previous_fix, str):
        previous_fix = compact_diff_for_prompt(previous_fix, _LEVEL1_DIFF_LINES)
    if level >= 2 or not include_previous_fix:
        previous_fix = None

    return {
        "crash_id": state.get("crash_id"),
        "platform": state.get("platform"),
        "app_version": state.get("app_version"),
        "device": state.get("device"),
        "exception": state.get("exception"),
        "stacktrace": raw_stack,
        "include_raw_stacktrace": include_raw_stack,
        "mapped_frames": mapped,
        "repo_context": repo_ctx,
        "root_cause": state.get("root_cause"),
        "confidence": state.get("confidence"),
        "fix_suggestion": state.get("fix_suggestion"),
        "fix_iteration_count": state.get("fix_iteration_count"),
        "fix_max_iterations": state.get("fix_max_iterations"),
        "generated_fix": generated_fix,
        "previous_generated_fix": previous_fix,
        "fix_review_feedback": state.get("fix_review_feedback"),
        "fix_required_changes": state.get("fix_required_changes"),
        "fix_review_questions": state.get("fix_review_questions"),
        "fix_impacted_files": state.get("fix_impacted_files"),
        "fix_rationale": state.get("fix_rationale"),
        "fix_risk": state.get("fix_risk"),
        "fix_tests": state.get("fix_tests"),
        "include_previous_fix": include_previous_fix and level < 2,
        "_compaction_level": level,
    }


def compact_analysis_prompt_input(state: Mapping[str, Any], level: int) -> dict[str, Any]:
    level = max(0, min(int(level), MAX_COMPACTION_LEVEL))
    repo_ctx = compact_repo_context(
        state.get("repo_context"),
        level,
        omit_redundant_snippets=True,
    )
    mapped = compact_mapped_frames(state.get("mapped_frames"), level)
    return {
        "mapped_frames": mapped,
        "repo_context": repo_ctx,
        "regression_analysis": repo_ctx,
        "top_commits": extract_top_commits(repo_ctx, limit=3 if level >= 1 else 5),
        "_compaction_level": level,
    }


def estimate_gosi_request_bytes(
    *,
    system_prompt: str,
    user_prompt: str,
    model: str = "model",
    temperature: float = 0.7,
) -> int:
    """UTF-8 size of the JSON body GOSI Brain would send."""
    body = {
        "stream": False,
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": temperature,
    }
    return len(json.dumps(body, ensure_ascii=False).encode("utf-8"))


def starting_compaction_level(
    *,
    system_prompt: str,
    user_prompt: str,
    max_request_bytes: int,
    compaction_mode: str,
    model: str = "model",
    temperature: float = 0.7,
) -> int:
    """Return 0, or 1 proactively when over budget and compaction is enabled."""
    mode = (compaction_mode or "auto").strip().lower()
    if mode == "off":
        return 0
    est = estimate_gosi_request_bytes(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        model=model,
        temperature=temperature,
    )
    if est > max_request_bytes:
        return 1
    return 0
