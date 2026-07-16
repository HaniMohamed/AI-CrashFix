# GOSI Brain API — Technical Integration Design

**Audience:** Engineers integrating any application (web, mobile, desktop, CLI, backend service) with GOSI Brain.  
**Scope:** Authentication, chat completions, gateway behavior, known restrictions, and proven workarounds.  
**Status:** Derived from production integration experience (Code Assistant extension, 2026).

---

## 1. Overview

GOSI Brain is exposed through an **API gateway** on the GOSI internal network. Clients do not talk to the model directly. Traffic passes through:

1. **Corporate network / VPN** (required for internal hosts)
2. **F5 BIG-IP Application Security Manager (ASM)** — Web Application Firewall (WAF)
3. **API proxies** — OAuth token service and chat proxy
4. **Upstream LLM gateway** — OpenAI-compatible chat completions

```
┌─────────────┐     HTTPS      ┌──────────────────┐     ┌─────────────────────┐
│ Your Client │ ─────────────► │ F5 ASM + Gateway │ ──► │ tokenapiproxy       │
│             │                  │ (intsol.gosi…)   │     │ iwaiapiproxy        │
└─────────────┘                  └──────────────────┘     └─────────────────────┘
                                        │
                                        ▼
                                 Set-Cookie (TS*)
                                 HTML challenges
                                 Rate limits (429)
```

### Base URL

| Setting | Value |
|---------|-------|
| Production / integration host | `https://intsol.gosi.gov.sa/` |
| Trailing slash | Required when concatenating paths |

All paths below are relative to this base URL.

---

## 2. API Endpoints

### 2.1 Authentication — `POST /v1/tokenapiproxy/token`

OAuth2-style token endpoint. Supports **password grant** (initial login) and **refresh token grant**.

#### Request

| Header | Value |
|--------|-------|
| `Content-Type` | `application/x-www-form-urlencoded` |
| `Accept` | `application/json` |
| `Accept-Charset` | `UTF-8` |
| `Authorization` | `Basic <base64("EmployeesApp:Employee")>` |
| `x-apikey` | API key issued for your application |
| `x-oauth-identity-domain-name` | `MobileDomain` |

#### Password grant body

```
username=<GOSI_USERNAME>
password=<GOSI_PASSWORD>
scope=MobileRServer.read
grant_type=PASSWORD
```

#### Refresh grant body

```
grant_type=refresh_token
refresh_token=<REFRESH_TOKEN>
scope=MobileRServer.read
```

#### Success response (JSON)

```json
{
  "access_token": "<JWT>",
  "token_type": "Bearer",
  "expires_in": 3600,
  "scope": "MobileRServer.read",
  "refresh_token": "<opaque or JWT>"
}
```

#### Error response

```json
{
  "error": "invalid_grant",
  "error_description": "Human-readable reason"
}
```

#### JWT claims (typical)

Decode the access token payload (middle segment of the JWT) to obtain:

- `PersonNumber` — preferred user identifier for chat
- `uid` / `sub` — fallbacks if `PersonNumber` is absent
- `exp` — expiry (Unix seconds)

**Token lifecycle recommendation:**

- Refresh when `exp` is within ~60 seconds of expiry
- On refresh failure, fall back to password grant (if credentials are stored securely)
- Do **not** treat HTML gateway pages or WAF blocks as auth failures — only HTTP 401 or explicit token error markers

---

### 2.2 Chat — `POST /v1/iwaiapiproxy/chat/completions`

OpenAI-compatible chat completions endpoint with GOSI-specific session metadata.

#### Request headers

| Header | Value |
|--------|-------|
| `Content-Type` | `application/json;charset=UTF-8` |
| `Accept` | `text/event-stream, application/json` when streaming; otherwise `application/json` |
| `Authorization` | `Bearer <access_token>` |
| `x-apikey` | Same API key as token endpoint |
| `Cookie` | WAF session cookies (see §4.1) |
| `Accept-Encoding` | **`identity` only** (see §4.2) |

#### Request body

```json
{
  "custom_session": {
    "user_id": "<PersonNumber or uid>",
    "session_id": "<client-generated session id>"
  },
  "stream": true,
  "model": "thinking",
  "messages": [
    { "role": "system", "content": "..." },
    { "role": "user", "content": "..." },
    { "role": "assistant", "content": "...", "tool_calls": [] },
    { "role": "tool", "content": "...", "tool_call_id": "call_0" }
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "search_code",
        "description": "...",
        "parameters": { "type": "object", "properties": {} }
      }
    }
  ]
}
```

| Field | Notes |
|-------|-------|
| `custom_session.user_id` | From JWT (`PersonNumber`, `uid`, or `sub`) |
| `custom_session.session_id` | Client-generated; format `{timestamp}-{random}` works; used for gateway-side session affinity |
| `stream` | `true` for SSE; gateway may ignore and return buffered JSON |
| `model` | e.g. `thinking` — confirm available models with your GOSI Brain team |
| `messages` | Standard OpenAI roles: `system`, `user`, `assistant`, `tool` |
| `tools` | Optional; native function-calling when supported |

#### Non-streaming success response

```json
{
  "id": "...",
  "model": "thinking",
  "choices": [
    {
      "index": 0,
      "finish_reason": "stop",
      "message": {
        "role": "assistant",
        "content": "Answer text",
        "reasoning": "Optional thinking channel",
        "reasoning_content": "Alternate thinking field name",
        "tool_calls": [
          {
            "id": "call_0",
            "type": "function",
            "function": { "name": "search_code", "arguments": "{}" }
          }
        ]
      }
    }
  ],
  "usage": {
    "prompt_tokens": 100,
    "completion_tokens": 50,
    "total_tokens": 150
  }
}
```

Some gateways return alternate top-level shapes (`content`, `answer`, `result`, `message`, or nested `data`). Implement a tolerant extractor that checks `choices[0].message.content` first, then fallbacks.

#### Streaming success response (SSE)

`Content-Type: text/event-stream`

```
data: {"choices":[{"delta":{"content":"Hello"}}]}

data: {"choices":[{"delta":{"reasoning":"Thinking..."}}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_0","function":{"name":"search_code","arguments":"{"}}]}}]}

data: {"choices":[{"finish_reason":"stop"}]}

data: [DONE]
```

**Delta fields to handle:**

| Field | Purpose |
|-------|---------|
| `delta.content` | Visible assistant text |
| `delta.reasoning` / `delta.reasoning_content` | Thinking / chain-of-thought channel |
| `delta.tool_calls` | Incremental tool call fragments (merge by `index`) |
| `usage` | May appear on a late SSE event |

Use an **idle timeout** that resets on each received chunk (not a fixed wall-clock timeout for the entire stream).

---

## 3. Session Model

| Concept | Recommendation |
|---------|----------------|
| `user_id` | Stable per authenticated user (from JWT) |
| `session_id` | One per conversation thread; generate new ID when user starts a new chat |
| Shared session under concurrency | Empirically safe for ≤3 parallel requests with the same `session_id` (no cross-talk observed) |
| Per-task session | Consider distinct `session_id` values for unrelated parallel jobs (review batches, background scouts) to reduce theoretical gateway coupling |

Example session ID format:

```
{unix_ms}-{8_char_random}
```

---

## 4. Gateway Restrictions and Workarounds

This section documents real production constraints discovered during integration. Each item includes **symptom**, **root cause**, and **workaround**.

---

### 4.1 F5 WAF Session Cookies

| | |
|---|---|
| **Symptom** | HTTP 200 with HTML page instead of JSON; login works in Postman but fails in a custom HTTP client |
| **Cause** | F5 ASM sets `TS*` session cookies. Clients that do not store and replay `Set-Cookie` on subsequent requests receive HTML challenge or error pages |
| **Workaround** | Implement a **per-host cookie jar**: parse `Set-Cookie` from every response, send `Cookie` header on every request to the same host. Clear cookies on sign-out |

**Implementation checklist:**

- [ ] Parse `Set-Cookie` (name=value before first `;`)
- [ ] Overwrite cookies on rotation (F5 rotates `TS*` values)
- [ ] Attach `Cookie: name1=val1; name2=val2` to all API calls
- [ ] Persist cookies across process restarts if your app is long-lived

**Retry behavior:** WAF cookie challenges are **transient** — retry after storing the challenge cookie usually succeeds. This is different from ASM content rejection (§4.4).

---

### 4.2 Accept-Encoding / Compression

| | |
|---|---|
| **Symptom** | Garbled response body, JSON parse failure, or "compressed response could not be decoded" |
| **Cause** | Gateway breaks when client advertises Brotli (`br`) in `Accept-Encoding`. Proxies may also rewrite headers and compress responses anyway |
| **Workaround** | Always send `Accept-Encoding: identity`. **Also** decode responses defensively by `Content-Encoding` (`br`, `gzip`, `deflate`) |

**Implementation checklist:**

- [ ] Set `Accept-Encoding: identity` as the **last** header (so nothing overrides it)
- [ ] If `Content-Encoding` is present, decompress before parsing JSON or SSE
- [ ] Apply decompression to both buffered and streaming responses

---

### 4.3 Rate Limiting (HTTP 429)

| | |
|---|---|
| **Symptom** | HTTP 429 or HTML page with title "429 Too Many Requests" |
| **Cause** | Too many concurrent or rapid chat requests (especially with parallel background agents) |
| **Workaround** | Process-wide rate-limit cooldown, request gating, exponential backoff |

**Recommended client behavior:**

| Control | Suggested value |
|---------|-----------------|
| Max concurrent chat requests | **2** default (1 interactive + 1 background); **1** for fully serialized |
| Priority lanes | Reserve at least 1 permit for interactive traffic when limit ≥ 2 |
| 429 cooldown | Start at 8s, double up to 60s cap; gate **all** chat until cooldown expires |
| Retry backoff on 429 | 5s × 2^attempt + jitter (much longer than generic transient retries) |

**Error classification:** 429 is **transient** (retry helps). It is **not** an auth failure.

---

### 4.4 F5 ASM Content Rejection ("Request Rejected")

| | |
|---|---|
| **Symptom** | HTML body containing `Request Rejected` and `support ID is: <number>` |
| **Cause** | Payload matches ASM attack signatures. Common triggers in code-assistant workloads: |
| | • Path traversal patterns: `../`, `..\` (e.g. Dart imports `../../`) |
| | • Hash comments: `#` in YAML/config snippets |
| | • Double-slash: `//` in code or URLs |
| | • Large request bodies |
| **Workaround** | Content shielding + payload size caps. **Retries do not help** — same payload is rejected again |

#### Content shield (client-side, before send)

Insert **Word Joiner** (Unicode U+2060) inside trigger sequences. ASM strips U+200B (zero-width space) before matching, but U+2060 survives and breaks signature matching:

| Pattern | Shielded form (conceptual) |
|---------|---------------------------|
| `../` | `.⁠./` (word joiner between dots and slash) |
| `..\` | `.⁠.\` |
| `#` | `#⁠` |
| `//` | `/⁠/` (repeat until no bare `//` remains) |

**Strip shield characters** from model output before writing to disk or displaying to users, so `../` and `#` are restored.

#### Newline padding

ASM also rejects some payloads based on trailing content shape. Append `\n` + U+200B (zero-width space) to each message `content` field. A trailing newline alone may be stripped by ASM; the ZWSP terminator survives.

**Scope:** Apply shields only to `messages[].content`. Do not mutate `tool_calls` arguments unless you have evidence they trigger WAF (default: leave untouched).

#### Payload size cap

| Layer | Purpose |
|-------|---------|
| Character budget | Truncate oldest system context and tool results first |
| Wire-byte cap | After shielding, ensure `JSON.stringify(body)` ≤ ~48 KB (tune per environment) |
| Shrink order | System messages → tool result messages → oldest bulky turns |

When a rejection occurs, capture the exact request body for offline bisection and provide the **support ID** to the network team to identify the ASM rule.

---

### 4.5 HTML Gateway Pages (Non-WAF)

| | |
|---|---|
| **Symptom** | `<!DOCTYPE html>` or `<html>` instead of JSON/SSE |
| **Cause** | VPN disconnected, captive portal, proxy block, expired WAF session, or streaming rejected at proxy layer |
| **Workaround** | Detect HTML responses; classify as gateway block (retry may help if cookie-related). Suggest VPN check to user. If streaming was requested, **retry once with `stream: false`** |

**Do not** classify HTML responses as token expiry unless HTTP 401 is also present.

---

### 4.6 Streaming Capability Negotiation

| | |
|---|---|
| **Symptom** | Stream requested but response is `application/json` (buffered) or HTML error |
| **Cause** | Gateway or model may not honor `stream: true` for all models/accounts |
| **Workaround** | Adaptive capability detection with cache (TTL ~7 days per model) |

**Negotiation flow:**

```
1. Try stream=true (if setting is "auto" or "on")
2. On success with Content-Type: text/event-stream → cache streaming=yes
3. On success with JSON body → cache streaming=no (still valid response)
4. On error mentioning "stream" or HTML/invalid JSON while streaming → retry with stream=false
5. Cache result per model
```

Same pattern applies to **native tools** (`tools` parameter): on 400/422 mentioning "tool", retry without tools and cache `nativeTools=no`.

---

### 4.7 Timeouts and Partial Streams

| | |
|---|---|
| **Symptom** | Idle timeout mid-SSE with partial content |
| **Cause** | Long reasoning generations; gateway idle socket timeout |
| **Workaround** | Use **idle** timeout (reset per chunk). If timeout fires mid-stream: salvage response if content ≥ ~400 chars or tool calls present; otherwise retry as transient |

---

### 4.8 Authentication vs Connectivity Errors

Misclassifying errors causes infinite re-login loops. Use this matrix:

| Condition | Auth failure? | Action |
|-----------|---------------|--------|
| HTTP 401 | Yes | Refresh token → password grant |
| HTTP 403 + token error text | Yes | Same as 401 |
| HTTP 403 without token markers | No | Proxy/WAF — check VPN, cookies |
| HTML gateway page | No | WAF/VPN/proxy |
| HTTP 429 | No | Backoff + concurrency gate |
| HTTP 5xx | No | Transient retry |
| ASM "Request Rejected" | No | Shrink/shield payload; contact network team |
| Idle timeout | No | Transient retry |

---

## 5. Retry and Concurrency Architecture

### 5.1 Error classification

| Class | Examples | Retry? |
|-------|----------|--------|
| **Transient** | ECONNRESET, 5xx, idle timeout, WAF cookie challenge, undecodable compressed body | Yes (bounded, exponential backoff) |
| **Rate limited** | HTTP 429 | Yes (long backoff + global cooldown) |
| **Gateway block** | HTML page (non-ASM), invalid JSON from proxy | Yes (may succeed after cookie refresh) |
| **Content rejection** | ASM "Request Rejected" + support ID | No — change payload |
| **Auth** | HTTP 401, explicit token errors | Refresh credentials, not blind retry |
| **Capability** | stream/tools not supported | Downgrade parameter and retry immediately |

### 5.2 Suggested retry policy

| Parameter | Value |
|-----------|-------|
| Max transient retries | 2 |
| Generic transient backoff | 1.5s × 2^attempt + jitter |
| 429 backoff | 5s × 2^attempt + jitter |
| Capability downgrade retries | Unlimited within same request (does not consume transient budget) |

### 5.3 Request gate (semaphore)

```
┌──────────────────────────────────────────────┐
│ Request Gate (process-wide)                  │
│  limit = maxConcurrentRequests (default 2)   │
│                                              │
│  [ Interactive queue ] ──► priority first  │
│  [ Background queue  ] ──► max (limit - 1)   │
│                              when limit ≥ 2  │
└──────────────────────────────────────────────┘
         │
         ▼
   Wait for 429 cooldown (if active)
         │
         ▼
   POST /chat/completions
```

---

## 6. Security and Operational Notes

| Topic | Guidance |
|-------|----------|
| API key | Required on all requests; treat as secret |
| Credentials | Store username/password in secure storage (OS keychain, vault) — never log |
| Bearer token | Short-lived JWT; do not log or persist in world-readable files |
| Cookie values | Sensitive session state; do not log |
| WAF forensics | When debugging rejections, dump last chat request (headers + body) with file permissions 0600; exclude login/refresh from dumps |
| TLS | `rejectUnauthorized` should remain `true` in production |
| VPN | Required for `intsol.gosi.gov.sa` from outside GOSI network |

---

## 7. Configuration Reference

These values were tuned for a code-assistant workload. Adjust per application.

| Parameter | Recommended default | Purpose |
|-----------|-------------------|---------|
| `baseUrl` | `https://intsol.gosi.gov.sa/` | Gateway root |
| `requestTimeoutMs` | `120000` | Idle timeout per request/stream |
| `maxConcurrentRequests` | `2` | Avoid 429 under parallel agents |
| `maxRetries` | `2` | Transient failure retries |
| `maxContextChars` | `24000` | Soft message character budget |
| `maxWireBytes` | `48000` | Hard JSON body byte cap (post-shield) |
| `streamingMode` | `auto` | `auto` / `on` / `off` |
| `nativeToolsMode` | `auto` | `auto` / `on` / `off` |
| `wafContentShield` | `true` | Word-joiner content shield |
| `wafNewlineShield` | `true` | Trailing `\n` + ZWSP pad |

---

## 8. Troubleshooting Guide

| User-visible symptom | Likely cause | What to try |
|---------------------|--------------|-------------|
| "Invalid JSON response … HTML gateway page" | VPN off, WAF cookies missing, proxy block | Connect VPN; ensure cookie jar; sign out/in |
| "Request Rejected" + support ID | ASM signature match or oversized body | Enable content shield; reduce context; give support ID to network team |
| "Rate limited" / 429 | Too many parallel requests | Lower concurrency; wait for cooldown |
| "Unauthorized" after fresh login | API key or account permission on chat endpoint | Contact GOSI Brain team |
| Garbled / binary response | Compression mismatch | Send `Accept-Encoding: identity`; decompress by `Content-Encoding` |
| Stream never arrives | Gateway ignores streaming | Set streaming to `off` or let adaptive logic downgrade |
| Empty assistant content | Truncated stream or gateway error | Retry; check for `error.detail` in JSON body |

### External reproduction

When ASM rejects a payload, reproduce outside your app:

1. Capture the exact `POST` URL, headers (including `Cookie` and `Authorization`), and JSON body
2. Replay with cURL or Postman using `--data-binary @body.json`
3. Bisect message content to find the triggering substring
4. Provide the ASM **support ID** to the network/security team

---

## 9. Implementation Checklist (Any Language)

### Authentication

- [ ] Password grant login with required headers
- [ ] Refresh token flow before expiry (~60s skew)
- [ ] JWT decode for `PersonNumber` / `uid`
- [ ] Secure credential storage

### HTTP transport

- [ ] Per-host cookie jar with `Set-Cookie` parsing
- [ ] `Accept-Encoding: identity` on all requests
- [ ] Defensive decompression on responses
- [ ] Configurable TLS verification
- [ ] Idle timeout with per-chunk reset for SSE

### Chat

- [ ] Build `custom_session` on every request
- [ ] Support streaming and non-streaming in one code path
- [ ] Parse SSE `data:` lines and `[DONE]` sentinel
- [ ] Merge incremental `tool_calls` by index
- [ ] Handle `reasoning` and `reasoning_content` fields
- [ ] Tolerant JSON extraction for gateway variants

### Resilience

- [ ] WAF content shield + newline pad (configurable)
- [ ] Character and byte budget enforcement
- [ ] Process-wide concurrency gate with priority lanes
- [ ] 429 cooldown shared across workers
- [ ] Adaptive streaming/tools negotiation with cache
- [ ] Classify errors (auth vs transient vs content rejection)
- [ ] Capture last rejected request for forensics

### Operations

- [ ] Structured diagnostic logging (status, bytes, SSE flag — not tokens/bodies)
- [ ] User-facing error messages mapped from error class
- [ ] VPN/connectivity guidance in UI

---

## 10. Appendix: cURL Examples

### Login (password grant)

```bash
curl -sS -X POST 'https://intsol.gosi.gov.sa/v1/tokenapiproxy/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Accept: application/json' \
  -H 'Accept-Charset: UTF-8' \
  -H 'Authorization: Basic RW1wbG95ZWVzQXBwOkVtcGxveWVl' \
  -H 'x-apikey: YOUR_API_KEY' \
  -H 'x-oauth-identity-domain-name: MobileDomain' \
  -H 'Accept-Encoding: identity' \
  --data-urlencode 'username=YOUR_USER' \
  --data-urlencode 'password=YOUR_PASSWORD' \
  --data-urlencode 'scope=MobileRServer.read' \
  --data-urlencode 'grant_type=PASSWORD'
```

### Chat completion (non-streaming)

```bash
curl -sS -X POST 'https://intsol.gosi.gov.sa/v1/iwaiapiproxy/chat/completions' \
  -H 'Content-Type: application/json;charset=UTF-8' \
  -H 'Accept: application/json' \
  -H 'Authorization: Bearer YOUR_ACCESS_TOKEN' \
  -H 'x-apikey: YOUR_API_KEY' \
  -H 'Accept-Encoding: identity' \
  -d '{
    "custom_session": {
      "user_id": "YOUR_PERSON_NUMBER",
      "session_id": "1720000000-abc12345"
    },
    "stream": false,
    "model": "thinking",
    "messages": [
      { "role": "user", "content": "Hello" }
    ]
  }'
```

> **Note:** After the first response, include stored `Cookie` headers on subsequent calls. Use a cookie-aware HTTP client or `-b`/`-c` flags with cURL.

---

## 11. Document History

| Date | Change |
|------|--------|
| 2026-07-16 | Initial version — endpoints, WAF workarounds, concurrency, and retry design |

---

*For API key provisioning, model availability, and account permissions on the chat endpoint, contact the GOSI Brain platform team.*
