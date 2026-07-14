from __future__ import annotations

import gzip
import http.client
import json
import logging
import re
import socket
import ssl
import time
import urllib.error
from typing import Any
from urllib.parse import urlparse

from app.services.llm_providers.base import LLMProvider

log = logging.getLogger(__name__)


class GosiBrainPayloadRejectedError(RuntimeError):
    """Raised when APIGee rejects the request (often HTTP 200 with an HTML body)."""

    def __init__(self, message: str, *, request_bytes: int = 0, status: int = 0) -> None:
        super().__init__(message)
        self.request_bytes = request_bytes
        self.status = status


class GosiBrainTimeoutError(RuntimeError):
    """Raised when the GOSI Brain HTTP call times out."""

    def __init__(
        self,
        message: str,
        *,
        request_bytes: int = 0,
        elapsed_ms: int = 0,
        connect_timeout: int = 0,
        read_timeout: int = 0,
    ) -> None:
        super().__init__(message)
        self.request_bytes = request_bytes
        self.elapsed_ms = elapsed_ms
        self.connect_timeout = connect_timeout
        self.read_timeout = read_timeout


_APIGEE_HTML_MARKERS = (
    "<!doctype",
    "<html",
    "request rejected",
    "payload too large",
    "request size",
    "body size",
    "exceeds maximum",
)


def _looks_like_apigee_rejection(text: str) -> bool:
    if not text:
        return False
    lower = text[:2000].lower()
    if any(marker in lower for marker in _APIGEE_HTML_MARKERS):
        return True
    if re.search(r"<\s*html[\s>]", lower):
        return True
    return False


def _is_timeout_error(exc: BaseException) -> bool:
    if isinstance(exc, socket.timeout):
        return True
    if isinstance(exc, TimeoutError):
        return True
    if isinstance(exc, urllib.error.URLError) and isinstance(exc.reason, (socket.timeout, TimeoutError)):
        return True
    reason = getattr(exc, "reason", None)
    if isinstance(reason, str) and "timed out" in reason.lower():
        return True
    return False


def _read_response_text(resp_headers: dict[str, str], raw_bytes: bytes) -> str:
    data = raw_bytes
    enc = (resp_headers.get("content-encoding") or "").strip().lower()
    if enc == "gzip":
        try:
            data = gzip.decompress(raw_bytes)
        except OSError:
            data = raw_bytes
    return data.decode("utf-8", errors="replace").strip()


def _https_post(
    url: str,
    data: bytes,
    headers: dict[str, str],
    *,
    connect_timeout: float,
    read_timeout: float,
    ssl_context: ssl.SSLContext,
) -> tuple[int, bytes, dict[str, str]]:
    parsed = urlparse(url)
    if parsed.scheme != "https":
        raise RuntimeError(f"GOSI Brain URL must use https: {url}")
    host = parsed.hostname or ""
    port = parsed.port or 443
    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"

    conn = http.client.HTTPSConnection(
        host,
        port,
        timeout=connect_timeout,
        context=ssl_context,
    )
    try:
        conn.request("POST", path, body=data, headers=headers)
        if conn.sock is not None:
            conn.sock.settimeout(read_timeout)
        resp = conn.getresponse()
        status = int(resp.status)
        raw_bytes = resp.read()
        resp_headers = {k.lower(): v for k, v in resp.getheaders()}
        return status, raw_bytes, resp_headers
    finally:
        conn.close()


def _raise_timeout_error(
    *,
    url: str,
    request_bytes: int,
    elapsed_ms: int,
    connect_timeout: float,
    read_timeout: float,
    cause: BaseException | None = None,
) -> None:
    raise GosiBrainTimeoutError(
        "GOSI Brain request timed out. Check corporate VPN/network access to "
        f"{url}. If the model is slow, increase GOSI_BRAIN_TIMEOUT "
        f"(current read={int(read_timeout)}s, connect={int(connect_timeout)}s). "
        f"Elapsed={elapsed_ms}ms, request_bytes={request_bytes}.",
        request_bytes=request_bytes,
        elapsed_ms=elapsed_ms,
        connect_timeout=int(connect_timeout),
        read_timeout=int(read_timeout),
    ) from cause


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
        timeout: float = 300,
        connect_timeout: float = 30,
        gzip_request: bool = False,
    ):
        self._url = (url or "").strip()
        self._model = (model or "").strip() or None
        self._authorization = (authorization or "").strip()
        self._api_key = (api_key or "").strip()
        self._oauth_domain = (oauth_domain or "MobileDomain").strip() or "MobileDomain"
        self._temperature = float(temperature)
        self._timeout = max(1.0, float(timeout))
        self._connect_timeout = max(1.0, float(connect_timeout))
        self._gzip_request = bool(gzip_request)

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
        request_bytes = len(body_json)
        log.info(
            "GOSI Brain request size: %d bytes (connect_timeout=%ss read_timeout=%ss gzip=%s)",
            request_bytes,
            int(self._connect_timeout),
            int(self._timeout),
            self._gzip_request,
        )

        post_data = body_json
        headers = {
            "Authorization": self._authorization,
            "Content-Type": "application/json",
            "x-oauth-identity-domain-name": self._oauth_domain,
            "Accept-Charset": "UTF-8",
            "x-apikey": self._api_key,
        }
        if self._gzip_request:
            try:
                post_data = gzip.compress(body_json)
                headers["Content-Encoding"] = "gzip"
            except OSError:
                post_data = body_json

        ssl_context = ssl.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE
        started = time.monotonic()
        try:
            status, raw_bytes, resp_headers = _https_post(
                self._url,
                post_data,
                headers,
                connect_timeout=self._connect_timeout,
                read_timeout=self._timeout,
                ssl_context=ssl_context,
            )
            raw = _read_response_text(resp_headers, raw_bytes)
        except (TimeoutError, socket.timeout) as e:
            elapsed_ms = int((time.monotonic() - started) * 1000)
            _raise_timeout_error(
                url=self._url,
                request_bytes=request_bytes,
                elapsed_ms=elapsed_ms,
                connect_timeout=self._connect_timeout,
                read_timeout=self._timeout,
                cause=e,
            )
        except OSError as e:
            elapsed_ms = int((time.monotonic() - started) * 1000)
            if _is_timeout_error(e) or getattr(e, "errno", None) in (60, 110):
                _raise_timeout_error(
                    url=self._url,
                    request_bytes=request_bytes,
                    elapsed_ms=elapsed_ms,
                    connect_timeout=self._connect_timeout,
                    read_timeout=self._timeout,
                    cause=e,
                )
            raise RuntimeError(f"GOSI Brain request failed: {e}") from e

        elapsed_ms = int((time.monotonic() - started) * 1000)
        log.info("GOSI Brain response received in %dms (HTTP %d)", elapsed_ms, status)

        if status >= 400:
            preview = raw[:500] + ("…" if len(raw) > 500 else "")
            if _looks_like_apigee_rejection(raw):
                raise GosiBrainPayloadRejectedError(
                    f"GOSI Brain request rejected by API gateway (payload too large). "
                    f"HTTP {status}. Response preview: {preview[:200]!r}",
                    request_bytes=request_bytes,
                    status=status,
                )
            raise RuntimeError(f"GOSI Brain HTTP {status}: {preview or 'no body'}")

        if _looks_like_apigee_rejection(raw):
            preview = raw[:200] + ("…" if len(raw) > 200 else "")
            raise GosiBrainPayloadRejectedError(
                "GOSI Brain request rejected by API gateway (payload too large). "
                f"HTTP status={status}. Response preview: {preview!r}",
                request_bytes=request_bytes,
                status=status,
            )

        if not raw:
            raise RuntimeError(f"GOSI Brain returned an empty body. HTTP status={status}.")

        try:
            parsed = json.loads(raw.lstrip("\ufeff"))
        except json.JSONDecodeError as e:
            preview = raw[:400] + ("…" if len(raw) > 400 else "")
            if _looks_like_apigee_rejection(raw):
                raise GosiBrainPayloadRejectedError(
                    "GOSI Brain request rejected by API gateway (payload too large). "
                    f"HTTP status={status}. Response preview: {preview!r}",
                    request_bytes=request_bytes,
                    status=status,
                ) from e
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
