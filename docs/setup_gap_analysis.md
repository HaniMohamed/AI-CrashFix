# Fresh-Install Setup Gap Analysis

_Generated 2026-10-06. Read-only audit — no code, config, or data changed._

## Current state

The product works end-to-end, but the path from `git clone` to "fixing a crash" is scattered
across three contradictory docs, and LLM-provider support falls short of "any provider,
including self-hosted."

## Key gaps

### 1. Docs don't match reality (biggest first-run blocker)
- Root `README.md` implies `pip install && uvicorn && flutter run` gets you a working
  dashboard. In reality every run is gated by `AuthGate` → Database-setup → Sign-in
  (create admin, one-time password, 12-char minimum) → Setup Wizard. None of that is
  mentioned in the README — only in `docs/buyer_setup.md`, framed as "buyer-oriented"
  (optional-sounding) rather than mandatory for everyone, including developers.
- `docs/gosi-brain-integration.md` and parts of `host_app_launch.md` /
  `macos_packaging.md` hardcode one customer's (GOSI) internal hostnames/WAF config
  inside what's presented as the generic "Advanced provider" path.

### 2. LLM providers: only 3 exist, not "any provider"
- Only Gemini, OpenAI, and the GOSI-specific "gosi-brain" gateway are implemented.
  **No Anthropic, no Azure OpenAI** — a hard code gap, not a doc gap
  (`app/services/ai_service.py` raises `ValueError` for anything else; the Settings API
  at `app/api/server.py` whitelists only those 3 provider strings).
- Self-hosted (Ollama/vLLM/LM Studio): only reachable today by misusing the "OpenAI"
  slot and manually overriding the base URL. A bug forces a fake API key even for
  key-less local servers (`app/services/llm_providers/openai_provider.py` hard-requires
  a non-empty key). Zero UI copy, zero `.env.example` line, zero wizard placeholder
  mentions this path.

### 3. Backend setup is broken for one documented path
- `psycopg` is imported by 6 Postgres-backed services
  (`app/services/app_settings_postgres.py`, `auth_store_postgres.py`,
  `crash_store_postgres.py`, `repo_registry_postgres.py`, `postgres_schema.py`,
  `crash_feedback_store.py`) but is **missing from `requirements.txt`**. Following
  `docs/buyer_setup.md`'s own "Team Postgres" instructions crashes with
  `ModuleNotFoundError: psycopg`.
- No root-level `docker-compose.yml` for the full stack (only Postgres alone, under
  `infra/postgres/`). No version pins in `requirements.txt`. `pyproject.toml` is an
  empty 2-byte placeholder with no project metadata.

### 4. Repo registration is generically fine, but "any Flutter repo" isn't validated
- Cloning an arbitrary git URL works regardless of language
  (`app/services/project_service.py`). But there's no `pubspec.yaml` check at
  registration — a non-Flutter repo clones silently, then produces poor/empty results
  later (Dart AST indexing, stacktrace mapping) with no clear error telling the user
  "this isn't a Flutter repo."

## Proposed fix plan (ordered by impact)

1. **Add Anthropic + Azure OpenAI providers** — new provider classes, wired into
   `ai_service.py` dispatch, the Settings API whitelist, and the wizard's provider
   selector.
2. **Fix self-hosted/custom provider support** — make the API key optional when a
   custom `base_url` is set, add a clearly-labeled "Custom / Self-hosted
   (OpenAI-compatible)" option in the wizard with an Ollama example placeholder
   (`http://localhost:11434/v1`), and genericize the "Advanced" gateway option away
   from GOSI-specific framing.
3. **Fix the Postgres path** — add `psycopg[binary]` to `requirements.txt`, pin
   dependency versions.
4. **Rewrite the root README** to include the mandatory auth/wizard flow as step 1
   (not an aside), and fold in the "mock-first" fastest-demo path from
   `buyer_setup.md`.
5. **Add a `pubspec.yaml` check** at repo registration time with a clear warning
   (not a hard block) if the target repo doesn't look like a Flutter project.
6. **Optional**: a single root `docker-compose.yml` (or a `./scripts/dev_up.sh`) that
   starts Postgres + backend and reminds the user to run Flutter, to cut the
   "3 separate toolchains" friction.

## Open questions for the user
- Proceed with all items above, or a subset first (e.g. just LLM provider work)?
- Confirm `.env`, `db/*.db`, and `workspace_projects/` stay fully off-limits
  (read-only) — only `.env.example` and docs/code get new additions.
