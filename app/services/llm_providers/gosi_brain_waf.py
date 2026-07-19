from __future__ import annotations

# Word Joiner survives ASM matching; ZWSP is stripped by ASM before match.
_WORD_JOINER = "\u2060"
_ZWSP = "\u200b"


def shield_content(text: str) -> str:
    """Insert Word Joiner into ASM trigger patterns in message content."""
    if not text:
        return text
    out = text
    # Path traversal
    out = out.replace("../", f".{_WORD_JOINER}./")
    out = out.replace("..\\", f".{_WORD_JOINER}.\\")
    # Hash comments
    out = out.replace("#", f"#{_WORD_JOINER}")
    # Double-slash (repeat until stable)
    while "//" in out:
        out = out.replace("//", f"/{_WORD_JOINER}/")
    return out


def pad_content_newline(text: str) -> str:
    """Append newline + ZWSP so ASM does not strip a trailing newline alone."""
    if text is None:
        return text
    return f"{text}\n{_ZWSP}"


def shield_message_content(text: str, *, enabled: bool = True) -> str:
    if not enabled:
        return text
    return pad_content_newline(shield_content(text))


def strip_shield_chars(text: str) -> str:
    """Remove Word Joiner / ZWSP from model output before returning to callers."""
    if not text:
        return text
    return text.replace(_WORD_JOINER, "").replace(_ZWSP, "")
