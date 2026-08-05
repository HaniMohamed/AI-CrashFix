from __future__ import annotations

import http.client
import json
import logging
import random
import re
import socket
import ssl
import string
import time
from typing import Any
from urllib.parse import urlparse

from app.services.llm_providers.base import LLMProvider
from app.services.llm_providers.gosi_brain_waf import shield_message_content, strip_shield_chars

log = logging.getLogger(__name__)

_SALVAGE_MIN_CHARS = 400
_STREAMING_CACHE: dict[str, bool] = {}
_COOKIE_JAR: dict[str, dict[str, str]] = {}


class GosiBrainPayloadRejectedError(RuntimeError):
    """Raised when ASM rejects the request (HTML with Request Rejected / support ID)."""

    def __init__(self, message: str, *, request_bytes: int = 0, status: int = 0) -> None:
        super().__init__(message)
        self.request_bytes = request_bytes
        self.status = status


class GosiBrainTimeoutError(RuntimeError):
    """Raised when the GOSI Brain HTTP call or stream idle times out."""

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


class GosiBrainGatewayError(RuntimeError):
    """Raised for HTML gateway pages that are not ASM content rejection."""

    pass


class GosiBrainRateLimitError(RuntimeError):
    """Raised on HTTP 429."""

    pass


class GosiBrainEmptyStreamError(RuntimeError):
    """SSE finished (or [DONE]) without any assistant content deltas."""

    pass


_ASM_MARKERS = (
    "request rejected",
    "support id is:",
    "payload too large",
    "exceeds maximum",
)


def _looks_like_html(text: str) -> bool:
    if not text:
        return False
    lower = text[:2000].lower()
    return "<!doctype" in lower or bool(re.search(r"<\s*html[\s>]", lower))


def _looks_like_asm_rejection(text: str) -> bool:
    if not text:
        return False
    lower = text[:4000].lower()
    return any(m in lower for m in _ASM_MARKERS)


def _is_timeout_error(exc: BaseException) -> bool:
    if isinstance(exc, (socket.timeout, TimeoutError)):
        return True
    reason = getattr(exc, "reason", None)
    if isinstance(reason, str) and "timed out" in reason.lower():
        return True
    return getattr(exc, "errno", None) in (60, 110)


def _new_session_id() -> str:
    rand = "".join(random.choices(string.ascii_lowercase + string.digits, k=8))
    return f"{int(time.time() * 1000)}-{rand}"


def _host_key(url: str) -> str:
    parsed = urlparse(url)
    host = parsed.hostname or ""
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    return f"{host}:{port}"


def _parse_set_cookie(headers: list[tuple[str, str]]) -> dict[str, str]:
    out: dict[str, str] = {}
    for name, value in headers:
        if name.lower() != "set-cookie":
            continue
        part = value.split(";", 1)[0].strip()
        if "=" not in part:
            continue
        k, v = part.split("=", 1)
        k = k.strip()
        if k:
            out[k] = v.strip()
    return out


def _cookie_header(host: str) -> str | None:
    jar = _COOKIE_JAR.get(host) or {}
    if not jar:
        return None
    return "; ".join(f"{k}={v}" for k, v in jar.items())


def _seed_cookies(host: str, cookie_header: str | None) -> None:
    """Seed jar from a Cookie header string (e.g. from Postman / env)."""
    raw = (cookie_header or "").strip()
    if not raw:
        return
    jar = _COOKIE_JAR.setdefault(host, {})
    for part in raw.split(";"):
        part = part.strip()
        if "=" not in part:
            continue
        k, v = part.split("=", 1)
        k = k.strip()
        if k:
            jar[k] = v.strip()


def _normalize_authorization(value: str) -> str:
    """Ensure Authorization is a Bearer token (Postman/curl style)."""
    v = (value or "").strip()
    if not v:
        return v
    lower = v.lower()
    if lower.startswith("bearer "):
        return "Bearer " + v[7:].strip()
    # Raw JWT
    if v.count(".") >= 2 and " " not in v:
        return f"Bearer {v}"
    return v


def _store_cookies(host: str, headers: list[tuple[str, str]]) -> None:
    parsed = _parse_set_cookie(headers)
    if not parsed:
        return
    jar = _COOKIE_JAR.setdefault(host, {})
    jar.update(parsed)


def _headers_dict(resp_headers: list[tuple[str, str]]) -> dict[str, str]:
    return {k.lower(): v for k, v in resp_headers}


def _read_response_text(resp_headers: dict[str, str], raw_bytes: bytes) -> str:
    """Decode body; defensively decompress gzip/deflate when Content-Encoding says so."""
    data = raw_bytes
    enc = (resp_headers.get("content-encoding") or "").strip().lower()
    if enc == "gzip":
        try:
            import gzip

            data = gzip.decompress(raw_bytes)
        except OSError:
            data = raw_bytes
    elif enc == "deflate":
        try:
            import zlib

            data = zlib.decompress(raw_bytes)
        except zlib.error:
            try:
                import zlib

                data = zlib.decompress(raw_bytes, -zlib.MAX_WBITS)
            except Exception:
                data = raw_bytes
    return data.decode("utf-8", errors="replace")


def _extract_chat_completion_content(parsed: Any) -> str:
    if not isinstance(parsed, dict):
        # Alternate top-level shapes
        if isinstance(parsed, str):
            return parsed.strip()
        return ""
    choices = parsed.get("choices")
    if isinstance(choices, list) and choices:
        first = choices[0]
        if isinstance(first, dict):
            msg = first.get("message")
            if isinstance(msg, dict):
                c = _coerce_text_content(msg.get("content"))
                if c.strip():
                    return c.strip()
            t = _coerce_text_content(first.get("text"))
            if t.strip():
                return t.strip()
    for key in ("content", "answer", "result", "message"):
        v = parsed.get(key)
        if isinstance(v, str) and v.strip():
            return v.strip()
        if isinstance(v, dict):
            c = _coerce_text_content(v.get("content"))
            if c.strip():
                return c.strip()
        coerced = _coerce_text_content(v)
        if coerced.strip():
            return coerced.strip()
    data = parsed.get("data")
    if isinstance(data, dict):
        return _extract_chat_completion_content(data)
    return ""


def _coerce_text_content(value: Any) -> str:
    """Normalize OpenAI-style content (string or text parts list) to a string."""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        parts: list[str] = []
        for item in value:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                t = item.get("text")
                if isinstance(t, str):
                    parts.append(t)
                elif item.get("type") == "text" and isinstance(item.get("content"), str):
                    parts.append(item["content"])
        return "".join(parts)
    return ""


def _delta_content(chunk: dict[str, Any]) -> str:
    # Top-level shortcuts some gateways use on SSE frames
    top = _coerce_text_content(chunk.get("content"))
    if top:
        return top

    choices = chunk.get("choices")
    if not isinstance(choices, list) or not choices:
        return ""
    first = choices[0]
    if not isinstance(first, dict):
        return ""
    delta = first.get("delta")
    if isinstance(delta, dict):
        c = _coerce_text_content(delta.get("content"))
        if c:
            return c
        # Some agent models only emit text under these late in the stream
        for key in ("text", "output_text"):
            t = _coerce_text_content(delta.get(key))
            if t:
                return t
    # Some gateways put content on message mid-stream
    msg = first.get("message")
    if isinstance(msg, dict):
        c = _coerce_text_content(msg.get("content"))
        if c:
            return c
    t = _coerce_text_content(first.get("text"))
    if t:
        return t
    return ""


def _ssl_context() -> ssl.SSLContext:
    ctx = ssl.create_default_context()
    # Internal / self-signed gateway certs
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def _open_https(
    url: str,
    *,
    connect_timeout: float,
) -> tuple[http.client.HTTPSConnection, str]:
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
        context=_ssl_context(),
    )
    return conn, path


class GosiBrainProvider(LLMProvider):
    def __init__(
        self,
        *,
        url: str | None = None,
        model: str | None = None,
        authorization: str | None = None,
        api_key: str | None = None,
        oauth_domain: str | None = None,
        user_id: str | None = None,
        cookie: str | None = None,
        send_oauth_domain: bool = False,
        temperature: float = 0.7,
        timeout: float = 300,
        connect_timeout: float = 30,
        idle_timeout: float = 120,
        streaming_mode: str = "auto",
        waf_content_shield: bool = True,
        gzip_request: bool = False,
    ):
        self._url = (url or "").strip()
        self._model = (model or "").strip() or None
        self._authorization = _normalize_authorization(authorization or "")
        self._api_key = (api_key or "").strip()
        self._oauth_domain = (oauth_domain or "").strip() or None
        self._send_oauth_domain = bool(send_oauth_domain) and bool(self._oauth_domain)
        self._user_id = (user_id or "").strip() or None
        self._temperature = float(temperature)
        self._timeout = max(1.0, float(timeout))
        self._connect_timeout = max(1.0, float(connect_timeout))
        self._idle_timeout = max(1.0, float(idle_timeout))
        mode = (streaming_mode or "auto").strip().lower()
        self._streaming_mode = mode if mode in ("auto", "on", "off") else "auto"
        self._waf_content_shield = bool(waf_content_shield)
        self._gzip_request = bool(gzip_request)
        if self._url:
            _seed_cookies(_host_key(self._url), cookie)

    def call(self, system_prompt: str, user_prompt: str) -> str:
        self._require_config()
        temp = max(0.0, min(1.0, float(self._temperature)))
        model = self._model or "model"

        sys_c = shield_message_content(system_prompt, enabled=self._waf_content_shield)
        usr_c = shield_message_content(user_prompt, enabled=self._waf_content_shield)

        want_stream = self._resolve_want_stream(model)
        body_base: dict[str, Any] = {
            "custom_session": {
                "user_id": self._user_id,
                "session_id": _new_session_id(),
            },
            "model": model,
            "temperature": temp,
            "messages": [
                {"role": "system", "content": sys_c},
                {"role": "user", "content": usr_c},
            ],
        }

        content = self._call_with_stream_mode(body_base, want_stream=want_stream)
        return strip_shield_chars(content)

    def _require_config(self) -> None:
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
        if not self._user_id:
            raise RuntimeError(
                "Missing GOSI_BRAIN_USER_ID for custom_session.user_id. "
                "Set it in Settings (LLM → GOSI Brain) or environment."
            )

    def _resolve_want_stream(self, model: str) -> bool:
        if self._streaming_mode == "off":
            return False
        if self._streaming_mode == "on":
            return True
        cached = _STREAMING_CACHE.get(model)
        if cached is not None:
            return cached
        return True

    def _call_with_stream_mode(self, body_base: dict[str, Any], *, want_stream: bool) -> str:
        model = str(body_base.get("model") or "model")
        try:
            return self._post_once({**body_base, "stream": want_stream})
        except GosiBrainEmptyStreamError as e:
            # Agent models often finish SSE with tool/reasoning frames and no
            # content deltas; buffered JSON usually still has the final answer.
            if want_stream:
                log.warning("GOSI Brain empty SSE (%s); retrying with stream=false", e)
                return self._post_once({**body_base, "stream": False})
            raise
        except GosiBrainGatewayError as e:
            if want_stream and self._streaming_mode != "on":
                log.warning("GOSI Brain stream failed (%s); retrying with stream=false", e)
                _STREAMING_CACHE[model] = False
                return self._post_once({**body_base, "stream": False})
            raise
        except GosiBrainPayloadRejectedError:
            raise
        except Exception as e:
            msg = str(e).lower()
            if want_stream and self._streaming_mode != "on" and (
                "stream" in msg or "event-stream" in msg or "invalid json" in msg
            ):
                log.warning("GOSI Brain stream error; retrying with stream=false: %s", e)
                _STREAMING_CACHE[model] = False
                return self._post_once({**body_base, "stream": False})
            raise

    def _build_headers(self, *, stream: bool) -> list[tuple[str, str]]:
        host = _host_key(self._url)
        accept = "text/event-stream, application/json" if stream else "application/json"
        # Docs §4.2: always send identity last — gzip/SSE breaks delta parsing.
        # Still decode Content-Encoding defensively on buffered bodies.
        headers: list[tuple[str, str]] = [
            ("Content-Type", "application/json;charset=UTF-8"),
            ("Accept", accept),
            ("Authorization", self._authorization),
            ("x-apikey", self._api_key),
        ]
        if self._send_oauth_domain and self._oauth_domain:
            headers.append(("x-oauth-identity-domain-name", self._oauth_domain))
        cookie = _cookie_header(host)
        if cookie:
            headers.append(("Cookie", cookie))
        headers.append(("Accept-Encoding", "identity"))
        return headers

    def _post_once(self, body: dict[str, Any]) -> str:
        stream = bool(body.get("stream"))
        body_json = json.dumps(body, ensure_ascii=False).encode("utf-8")
        request_bytes = len(body_json)
        log.info(
            "GOSI Brain request size=%d bytes stream=%s idle=%ss connect=%ss",
            request_bytes,
            stream,
            int(self._idle_timeout),
            int(self._connect_timeout),
        )

        # Cookie challenge: one retry after storing Set-Cookie
        last_gateway: GosiBrainGatewayError | None = None
        for attempt in range(2):
            try:
                return self._execute_request(
                    body_json,
                    stream=stream,
                    request_bytes=request_bytes,
                )
            except GosiBrainGatewayError as e:
                last_gateway = e
                if attempt == 0:
                    log.warning("GOSI Brain gateway HTML/cookie challenge; retrying once")
                    continue
                raise
            except GosiBrainRateLimitError as e:
                if attempt == 0:
                    time.sleep(5.0)
                    continue
                raise RuntimeError(str(e)) from e

        if last_gateway:
            raise last_gateway
        raise RuntimeError("GOSI Brain request failed unexpectedly")

    def _execute_request(
        self,
        body_json: bytes,
        *,
        stream: bool,
        request_bytes: int,
    ) -> str:
        host = _host_key(self._url)
        headers = self._build_headers(stream=stream)
        started = time.monotonic()
        conn: http.client.HTTPSConnection | None = None
        try:
            conn, path = _open_https(self._url, connect_timeout=self._connect_timeout)
            conn.request("POST", path, body=body_json, headers=dict(headers))
            if conn.sock is not None:
                # Idle timeout for reading response / SSE chunks
                conn.sock.settimeout(self._idle_timeout if stream else self._timeout)
            resp = conn.getresponse()
            status = int(resp.status)
            resp_headers_list = resp.getheaders()
            _store_cookies(host, resp_headers_list)
            hdrs = _headers_dict(resp_headers_list)
            ctype = (hdrs.get("content-type") or "").lower()

            if status == 429 or "429" in ctype:
                body_preview = resp.read(2000).decode("utf-8", errors="replace")
                raise GosiBrainRateLimitError(
                    f"GOSI Brain rate limited (HTTP {status}). Preview: {body_preview[:200]!r}"
                )

            if status >= 400:
                raw_bytes = resp.read()
                raw = _read_response_text(hdrs, raw_bytes)
                if status == 401:
                    raise RuntimeError(
                        "GOSI Brain HTTP 401 Unauthorized. "
                        "Copy the Cookie header from a working Postman/curl request into "
                        "GOSI_BRAIN_COOKIE (F5 TS* session cookie is often required), "
                        "confirm GOSI_BRAIN_MODEL matches Postman (e.g. gosi_brain_agent), "
                        "and that GOSI_BRAIN_AUTHORIZATION is a Bearer JWT. "
                        f"Body: {raw[:400]!r}"
                    )
                self._raise_from_error_body(raw, status=status, request_bytes=request_bytes)

            if stream and "text/event-stream" in ctype:
                content = self._read_sse(conn, resp, request_bytes=request_bytes, started=started)
                _STREAMING_CACHE[str(self._model)] = True
                return content

            # Buffered JSON (or stream ignored by gateway)
            raw = _read_response_text(hdrs, resp.read()).strip()
            if _looks_like_asm_rejection(raw):
                raise GosiBrainPayloadRejectedError(
                    f"GOSI Brain ASM rejected request. HTTP {status}. Preview: {raw[:200]!r}",
                    request_bytes=request_bytes,
                    status=status,
                )
            if _looks_like_html(raw):
                raise GosiBrainGatewayError(
                    f"GOSI Brain returned HTML gateway page (HTTP {status}). Check VPN/cookies."
                )
            if not raw:
                raise RuntimeError(f"GOSI Brain returned an empty body. HTTP status={status}.")
            try:
                parsed = json.loads(raw.lstrip("\ufeff"))
            except json.JSONDecodeError as e:
                if stream:
                    raise GosiBrainGatewayError(
                        f"GOSI Brain stream requested but body is not SSE/JSON: {e}"
                    ) from e
                raise RuntimeError(
                    f"GOSI Brain returned invalid JSON: {e}. Body preview: {raw[:400]!r}"
                ) from e
            content = _extract_chat_completion_content(parsed)
            if not content:
                raise RuntimeError("GOSI Brain returned an empty or unrecognized completion.")
            if stream:
                # Gateway returned JSON while stream=true — still valid; cache no-stream preference
                _STREAMING_CACHE[str(self._model)] = False
            elapsed_ms = int((time.monotonic() - started) * 1000)
            log.info("GOSI Brain buffered response in %dms (HTTP %d)", elapsed_ms, status)
            return content

        except (TimeoutError, socket.timeout) as e:
            elapsed_ms = int((time.monotonic() - started) * 1000)
            raise GosiBrainTimeoutError(
                "GOSI Brain request timed out. Check VPN or increase GOSI_BRAIN_IDLE_TIMEOUT / "
                f"GOSI_BRAIN_TIMEOUT (idle={int(self._idle_timeout)}s, read={int(self._timeout)}s). "
                f"Elapsed={elapsed_ms}ms, request_bytes={request_bytes}.",
                request_bytes=request_bytes,
                elapsed_ms=elapsed_ms,
                connect_timeout=int(self._connect_timeout),
                read_timeout=int(self._idle_timeout if stream else self._timeout),
            ) from e
        except OSError as e:
            if _is_timeout_error(e):
                elapsed_ms = int((time.monotonic() - started) * 1000)
                raise GosiBrainTimeoutError(
                    "GOSI Brain request timed out. Check VPN or increase timeouts. "
                    f"Elapsed={elapsed_ms}ms, request_bytes={request_bytes}.",
                    request_bytes=request_bytes,
                    elapsed_ms=elapsed_ms,
                    connect_timeout=int(self._connect_timeout),
                    read_timeout=int(self._idle_timeout if stream else self._timeout),
                ) from e
            raise RuntimeError(f"GOSI Brain request failed: {e}") from e
        finally:
            if conn is not None:
                try:
                    conn.close()
                except Exception:
                    pass

    def _raise_from_error_body(self, raw: str, *, status: int, request_bytes: int) -> None:
        if _looks_like_asm_rejection(raw):
            raise GosiBrainPayloadRejectedError(
                f"GOSI Brain ASM rejected request. HTTP {status}. Preview: {raw[:200]!r}",
                request_bytes=request_bytes,
                status=status,
            )
        if _looks_like_html(raw):
            raise GosiBrainGatewayError(
                f"GOSI Brain returned HTML gateway page (HTTP {status}). Check VPN/cookies."
            )
        raise RuntimeError(f"GOSI Brain HTTP {status}: {raw[:500] or 'no body'}")

    def _read_sse(
        self,
        conn: http.client.HTTPSConnection,
        resp: http.client.HTTPResponse,
        *,
        request_bytes: int,
        started: float,
    ) -> str:
        parts: list[str] = []
        buffer = b""
        try:
            while True:
                if conn.sock is not None:
                    conn.sock.settimeout(self._idle_timeout)
                chunk = resp.read(1024)
                if not chunk:
                    break
                buffer += chunk
                while b"\n" in buffer:
                    line_b, buffer = buffer.split(b"\n", 1)
                    line = line_b.decode("utf-8", errors="replace").rstrip("\r")
                    if not line:
                        continue
                    if not line.startswith("data:"):
                        continue
                    payload = line[5:].strip()
                    if payload == "[DONE]":
                        text = "".join(parts).strip()
                        if not text:
                            raise GosiBrainEmptyStreamError(
                                "GOSI Brain SSE ended with empty content."
                            )
                        elapsed_ms = int((time.monotonic() - started) * 1000)
                        log.info(
                            "GOSI Brain SSE complete in %dms (%d chars)",
                            elapsed_ms,
                            len(text),
                        )
                        return text
                    try:
                        obj = json.loads(payload)
                    except json.JSONDecodeError:
                        continue
                    if isinstance(obj, dict):
                        # Late error object
                        err = obj.get("error")
                        if err:
                            raise RuntimeError(f"GOSI Brain stream error: {err}")
                        # Full completion frame mid-stream (non-delta)
                        full = _extract_chat_completion_content(obj)
                        if full and not _delta_content(obj):
                            parts.append(full)
                            continue
                        delta = _delta_content(obj)
                        if delta:
                            parts.append(delta)
        except (TimeoutError, socket.timeout) as e:
            text = "".join(parts).strip()
            if len(text) >= _SALVAGE_MIN_CHARS:
                log.warning(
                    "GOSI Brain SSE idle timeout; salvaging %d chars of partial content",
                    len(text),
                )
                return text
            elapsed_ms = int((time.monotonic() - started) * 1000)
            raise GosiBrainTimeoutError(
                "GOSI Brain SSE idle timeout with insufficient content. "
                f"Elapsed={elapsed_ms}ms, partial_chars={len(text)}, "
                f"idle={int(self._idle_timeout)}s.",
                request_bytes=request_bytes,
                elapsed_ms=elapsed_ms,
                connect_timeout=int(self._connect_timeout),
                read_timeout=int(self._idle_timeout),
            ) from e

        text = "".join(parts).strip()
        if text:
            return text
        # Maybe buffered JSON was mislabeled — try leftover buffer
        leftover = buffer.decode("utf-8", errors="replace").strip()
        if leftover and not _looks_like_html(leftover):
            try:
                parsed = json.loads(leftover.lstrip("\ufeff"))
                content = _extract_chat_completion_content(parsed)
                if content:
                    return content
            except json.JSONDecodeError:
                pass
        if _looks_like_html(leftover) or _looks_like_asm_rejection(leftover):
            if _looks_like_asm_rejection(leftover):
                raise GosiBrainPayloadRejectedError(
                    f"GOSI Brain ASM rejected during stream. Preview: {leftover[:200]!r}",
                    request_bytes=request_bytes,
                )
            raise GosiBrainGatewayError("GOSI Brain returned HTML during SSE read.")
        preview = leftover[:240].replace("\n", "\\n") if leftover else ""
        raise GosiBrainEmptyStreamError(
            "GOSI Brain SSE stream ended without content."
            + (f" Body preview: {preview!r}" if preview else "")
        )
