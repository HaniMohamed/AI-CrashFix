from __future__ import annotations

import json
import re
from typing import Any, Dict, List

from app.utils.fix_json import fix_corrupted_json

try:
    from json_repair import loads as json_repair_loads
    from json_repair import repair_json
except ImportError:  # pragma: no cover
    json_repair_loads = None
    repair_json = None


def is_ollama_base_url(base_url: str | None) -> bool:
    """True when the OpenAI-compatible endpoint is a local/remote Ollama server."""
    u = (base_url or "").strip().lower()
    return "11434" in u or "ollama" in u


def extract_top_commits(repo_context: List[Dict], limit: int = 5):
    """
    Extract most relevant commits across all frames.
    Prioritize:
    1. Likely introducing commits
    2. Recent commits
    3. Risky commits (refactor, null, async)
    """

    scored_commits = []

    for frame in repo_context:
        commits = frame.get("recent_commits", [])
        likely = frame.get("likely_introducing_commit")

        # 1. Add likely introducing commit with highest priority
        if likely:
            scored_commits.append({
                "commit": likely,
                "score": 1.0,
                "file": frame.get("file")
            })

        # 2. Add recent commits
        for c in commits:
            score = 0.5

            msg = c.get("message", "").lower()

            if any(k in msg for k in ["refactor", "null", "async", "state"]):
                score += 0.3

            scored_commits.append({
                "commit": c,
                "score": score,
                "file": frame.get("file")
            })

    # Sort by score descending
    scored_commits.sort(key=lambda x: x["score"], reverse=True)

    # Deduplicate by commit hash
    seen = set()
    unique = []

    for item in scored_commits:
        c = item["commit"]
        if not c:
            continue

        commit_id = c.get("hash") or c.get("message")

        if commit_id in seen:
            continue

        seen.add(commit_id)
        unique.append(c)

        if len(unique) >= limit:
            break

    return unique


def _strip_markdown_fences(text: str) -> str:
    text = text.strip()
    text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\s*```\s*$", "", text)
    return text.strip()


def _json_candidates(text: str) -> list[str]:
    """Build ordered parse candidates from raw LLM output."""
    seen: set[str] = set()
    out: list[str] = []

    def add(candidate: str | None) -> None:
        if not candidate:
            return
        c = candidate.strip()
        if not c or c in seen:
            return
        seen.add(c)
        out.append(c)

    stripped = _strip_markdown_fences(text)
    add(stripped)
    add(fix_corrupted_json(stripped))

    match = re.search(r"\{.*\}", stripped, re.DOTALL)
    if match:
        block = match.group(0)
        add(block)
        add(fix_corrupted_json(block))

    return out


def _try_parse(candidate: str) -> Any | None:
    try:
        return json.loads(candidate)
    except json.JSONDecodeError:
        pass

    if json_repair_loads is not None:
        try:
            return json_repair_loads(candidate)
        except Exception:
            pass

    if repair_json is not None:
        try:
            repaired = repair_json(candidate)
            if isinstance(repaired, str):
                return json.loads(repaired)
            return repaired
        except Exception:
            pass

    return None


def parse_json(text: str):
    """
    Extract and parse JSON from LLM response safely.
    Handles:
    - markdown code blocks
    - extra text before/after JSON
    - minor corruption (json-repair + fix_corrupted_json for diff fields)
    """

    if not text:
        raise ValueError("Empty LLM response")

    for candidate in _json_candidates(text):
        parsed = _try_parse(candidate)
        if parsed is not None:
            return parsed

    raise ValueError(f"Failed to parse JSON from LLM output:\n{text}")
