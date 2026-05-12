from __future__ import annotations

import gzip
import json
import urllib.error
import urllib.request
from typing import Any

from app.services.llm_providers.base import LLMProvider


def _read_response_text(resp: Any, raw_bytes: bytes) -> str:
    data = raw_bytes
    enc = (resp.headers.get("Content-Encoding") or "").strip().lower()
    if enc == "gzip":
        try:
            data = gzip.decompress(raw_bytes)
        except OSError:
            data = raw_bytes
    return data.decode("utf-8", errors="replace").strip()


class GosiBrainProvider(LLMProvider):
    def __init__(
        self,
        *,
        url: str | None = None,
        model: str | None = None,
        authorization: str | None = None,
        api_key: str | None = None,
        oauth_domain: str | None = None,
        temperature: float = 0.7,
    ):
        self._url = (url or "").strip()
        self._model = (model or "").strip() or None
        self._authorization = (authorization or "").strip()
        self._api_key = (api_key or "").strip()
        self._oauth_domain = (oauth_domain or "MobileDomain").strip() or "MobileDomain"
        self._temperature = float(temperature)

    def call(self, system_prompt: str, user_prompt: str) -> str:
        if not self._url:
            raise RuntimeError(
                "Missing GOSI_BRAIN_URL. Set it in Settings UI or environment to use GOSI Brain."
            )
        if not self._authorization:
            raise RuntimeError(
                "Missing GOSI_BRAIN_AUTHORIZATION. Set it in Settings UI or environment to use GOSI Brain."
            )
        if not self._api_key:
            raise RuntimeError(
                "Missing GOSI_BRAIN_API_KEY. Set it in Settings UI or environment to use GOSI Brain."
            )
        if not self._model:
            raise RuntimeError(
                "Missing GOSI_BRAIN_MODEL. Set it in Settings UI or environment to use GOSI Brain."
            )

        temp = max(0.0, min(1.0, float(self._temperature)))

        body: dict[str, Any] = {
            "stream": False,
            "model": self._model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": temp,
        }
        body_json = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers = {
            "Authorization": self._authorization,
            "Content-Type": "application/json",
            "x-oauth-identity-domain-name": self._oauth_domain,
            "Accept-Charset": "UTF-8",
            "x-apikey": self._api_key,
        }

        req = urllib.request.Request(self._url, data=body_json, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                status = int(getattr(resp, "status", None) or resp.getcode() or 0)
                raw_bytes = resp.read()
                raw = _read_response_text(resp, raw_bytes)
        except urllib.error.HTTPError as e:
            snippet = ""
            try:
                snippet = e.read().decode("utf-8", errors="replace")[:500]
            except Exception:
                pass
            raise RuntimeError(f"GOSI Brain HTTP {e.code}: {snippet or e.reason}") from e
        except urllib.error.URLError as e:
            raise RuntimeError(f"GOSI Brain request failed: {e.reason}") from e

        if not raw:
            raise RuntimeError(f"GOSI Brain returned an empty body. HTTP status={status}.")

        try:
            parsed = json.loads(raw.lstrip("\ufeff"))
        except json.JSONDecodeError as e:
            preview = raw[:400] + ("…" if len(raw) > 400 else "")
            raise RuntimeError(
                f"GOSI Brain returned invalid JSON: {e}. HTTP status={status}. Body preview: {preview!r}"
            ) from e

        content = _extract_chat_completion_content(parsed)
        if not content:
            raise RuntimeError("GOSI Brain returned an empty or unrecognized completion.")
        return content


def _extract_chat_completion_content(parsed: Any) -> str:
    if not isinstance(parsed, dict):
        return ""
    choices = parsed.get("choices")
    if not isinstance(choices, list) or not choices:
        return ""
    first = choices[0]
    if not isinstance(first, dict):
        return ""
    msg = first.get("message")
    if isinstance(msg, dict):
        c = msg.get("content")
        return c.strip() if isinstance(c, str) else ""
    t = first.get("text")
    return t.strip() if isinstance(t, str) else ""
