from typing import List, Dict

import re
import json


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


def parse_json(text: str):
    """
    Extract and parse JSON from LLM response safely.
    Handles:
    - markdown code blocks
    - extra text before/after JSON
    - partial corruption (best effort)
    """

    if not text:
        raise ValueError("Empty LLM response")

    # 1. Remove markdown fences
    text = text.strip()
    text = re.sub(r"```json", "", text)
    text = re.sub(r"```", "", text)

    # 2. Try direct parse
    try:
        return json.loads(text)
    except:
        pass

    # 3. Extract JSON block using regex
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(0))
        except:
            pass

    # 4. Hard failure fallback
    raise ValueError(f"Failed to parse JSON from LLM output:\n{text}")