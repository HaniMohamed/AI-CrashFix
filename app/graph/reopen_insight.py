"""AI-generated insight explaining why a crash reopened (recurred after being marked fixed).

Mirrors the single-LLM-call classifier pattern in `app.graph.feedback_regeneration`.
"""

from __future__ import annotations

from typing import Any, Dict

from app.prompts.reopen_insight_prompts import (
    REOPEN_INSIGHT_PROMPT_INPUT,
    REOPEN_INSIGHT_SYSTEM_PROMPT,
)
from app.services.ai_service import LLMService
from app.utils.llm_helpers import parse_json_object

_VALID_CONFIDENCE = frozenset({"low", "medium", "high"})
_VALID_CAUSES = frozenset(
    {"incomplete_fix", "new_code_path", "unrelated_regression", "fix_not_shipped", "unknown"}
)


def generate_reopen_insight(original_crash: Dict[str, Any], new_crash: Dict[str, Any]) -> Dict[str, Any]:
    """
    One LLM call explaining why ``new_crash`` likely reopened ``original_crash`` (which was
    previously marked fixed). Returns ``{summary, likely_cause, confidence}``.
    """
    llm = LLMService()
    parsed = parse_json_object(
        llm.call(
            system_prompt=REOPEN_INSIGHT_SYSTEM_PROMPT(),
            user_prompt=REOPEN_INSIGHT_PROMPT_INPUT(original_crash=original_crash, new_crash=new_crash),
        ),
        context="generate_reopen_insight",
    )
    likely_cause = str(parsed.get("likely_cause") or "").strip().lower()
    if likely_cause not in _VALID_CAUSES:
        likely_cause = "unknown"
    confidence = str(parsed.get("confidence") or "").strip().lower()
    if confidence not in _VALID_CONFIDENCE:
        confidence = "low"
    return {
        "summary": str(parsed.get("summary") or "").strip(),
        "likely_cause": likely_cause,
        "confidence": confidence,
    }


def run_reopen_insight(new_crash_id: str, original_crash: Dict[str, Any], new_crash: Dict[str, Any]) -> Dict[str, Any]:
    """Generate the insight and persist it as an AI message on the new (reopened) crash."""
    from app.services import crash_feedback_store

    insight = generate_reopen_insight(original_crash, new_crash)
    message = f"{insight['summary']}\n\nLikely cause: {insight['likely_cause']} (confidence: {insight['confidence']})"
    crash_feedback_store.add_message(new_crash_id, role="ai", message=message, status="reopen_analysis")
    return insight
