from __future__ import annotations

from app.services.llm_providers.gosi_brain_waf import (
    shield_content,
    shield_message_content,
    strip_shield_chars,
)
from app.utils.prompt_budget import estimate_gosi_request_bytes


def test_shield_breaks_path_traversal_and_hash():
    raw = "import '../../foo.dart'; # note\nhttps://example.com//x"
    shielded = shield_content(raw)
    assert "../" not in shielded
    assert "#" in shielded and "\u2060" in shielded
    assert "//" not in shielded


def test_shield_message_pads_newline_zwsp():
    out = shield_message_content("hello")
    assert out.endswith("\n\u200b")


def test_strip_shield_restores_readable_text():
    shielded = shield_message_content("a../b #c //d")
    cleaned = strip_shield_chars(shielded).rstrip("\n")
    assert "../" in cleaned or "../" in cleaned.replace("\u2060", "")
    # After strip, word joiner gone and path traversal restored
    assert "\u2060" not in cleaned
    assert "\u200b" not in cleaned
    assert "../" in cleaned
    assert "#" in cleaned
    assert "//" in cleaned


def test_estimate_gosi_request_includes_custom_session():
    n = estimate_gosi_request_bytes(system_prompt="s", user_prompt="u")
    assert n > 50
