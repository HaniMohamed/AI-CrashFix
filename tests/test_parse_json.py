import pytest

from app.utils.llm_helpers import is_ollama_base_url, parse_json


def test_is_ollama_base_url():
    assert is_ollama_base_url("http://192.168.1.25:11434/v1")
    assert is_ollama_base_url("http://localhost:11434/v1")
    assert not is_ollama_base_url("https://api.openai.com/v1")
    assert not is_ollama_base_url("https://api.groq.com/openai/v1")


def test_parse_json_clean():
    assert parse_json('{"approved": true, "summary": "ok"}') == {
        "approved": True,
        "summary": "ok",
    }


def test_parse_json_markdown_fences():
    raw = """```json
{"root_cause": "null deref", "confidence": 0.8}
```"""
    parsed = parse_json(raw)
    assert parsed["root_cause"] == "null deref"
    assert parsed["confidence"] == 0.8


def test_parse_json_with_preamble():
    raw = 'Here is the JSON:\n{"risk": "low", "fix": "insufficient evidence"}'
    parsed = parse_json(raw)
    assert parsed["risk"] == "low"


def test_parse_json_repair_trailing_comma():
    raw = '{"approved": false, "summary": "needs work",}'
    parsed = parse_json(raw)
    assert parsed["approved"] is False


def test_parse_json_fix_field_unescaped_quotes():
    raw = (
        '{"fix": "--- a/lib/foo.dart\n+++ b/lib/foo.dart\n@@ -1 +1 @@\n-  final x = "bad";\n+  final x = \\"ok\\";", '
        '"impacted_files": ["lib/foo.dart"], "rationale": "test", "risk": "low", "tests": []}'
    )
    parsed = parse_json(raw)
    assert "lib/foo.dart" in parsed["fix"]
    assert parsed["impacted_files"] == ["lib/foo.dart"]


def test_parse_json_empty_raises():
    with pytest.raises(ValueError, match="Empty"):
        parse_json("")
