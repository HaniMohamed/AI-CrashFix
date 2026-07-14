from __future__ import annotations

import logging
from collections.abc import Callable
from typing import Any

from app.services.settings_resolver import SettingsResolver
from app.utils.prompt_budget import MAX_COMPACTION_LEVEL, starting_compaction_level

log = logging.getLogger(__name__)


class LLMService:
    """
    Resolves provider + credentials from SQLite app_settings (UI) with .env fallback
    on each call so graph runs pick up saved settings without restarting uvicorn.
    """

    def __init__(self) -> None:
        self._provider = None
        self._sig: tuple[Any, ...] | None = None

    def _config_sig(self, resolver: SettingsResolver) -> tuple[Any, ...]:
        name = resolver.effective_llm_provider()
        if name == "openai":
            o = resolver.effective_openai()
            return ("openai", o.get("api_key"), o.get("model"), o.get("url"))
        if name == "gosi-brain":
            gb = resolver.effective_gosi_brain()
            return (
                "gosi-brain",
                gb.get("url"),
                gb.get("model"),
                gb.get("authorization"),
                gb.get("api_key"),
                gb.get("oauth_domain"),
                gb.get("temperature"),
                gb.get("max_request_bytes"),
                gb.get("prompt_compaction"),
                gb.get("timeout"),
                gb.get("connect_timeout"),
                gb.get("gzip_request"),
            )
        g = resolver.effective_google()
        return ("gemini", g.get("api_key"), g.get("model"))

    def _ensure_provider(self, resolver: SettingsResolver) -> None:
        sig = self._config_sig(resolver)
        if self._provider is not None and self._sig == sig:
            return
        self._sig = sig
        name = resolver.effective_llm_provider()
        if name == "openai":
            from app.services.llm_providers.openai_provider import OpenAIProvider

            o = resolver.effective_openai()
            self._provider = OpenAIProvider(
                api_key=o.get("api_key"),
                base_url=o.get("url"),
                model=o.get("model"),
            )
        elif name == "gosi-brain":
            from app.services.llm_providers.gosi_brain_provider import GosiBrainProvider

            gb = resolver.effective_gosi_brain()
            self._provider = GosiBrainProvider(
                url=gb.get("url"),
                model=gb.get("model"),
                authorization=gb.get("authorization"),
                api_key=gb.get("api_key"),
                oauth_domain=gb.get("oauth_domain"),
                temperature=float(gb.get("temperature") or 0.7),
                timeout=float(gb.get("timeout") or 300),
                connect_timeout=float(gb.get("connect_timeout") or 30),
                gzip_request=bool(gb.get("gzip_request")),
            )
        elif name == "gemini":
            from app.services.llm_providers.gemini_provider import GeminiProvider

            g = resolver.effective_google()
            self._provider = GeminiProvider(
                api_key=g.get("api_key"),
                model=g.get("model"),
            )
        else:
            raise ValueError(f"Unknown LLM provider: {name}")

    def call(self, system_prompt: str, user_prompt: str) -> str:
        try:
            resolver = SettingsResolver()
            self._ensure_provider(resolver)
            return self._provider.call(system_prompt, user_prompt)
        except Exception as e:
            raise RuntimeError(f"LLM call failed: {str(e)}") from e

    def call_with_prompt_budget(
        self,
        system_prompt: str,
        *,
        build_user_prompt: Callable[[Any], str],
        prompt_input: Any,
        compact_input: Callable[[Any, int], Any],
    ) -> str:
        """
        Call LLM with progressive prompt compaction for gosi-brain when APIGee rejects
        large payloads. Other providers use a single uncompacted call.
        """
        try:
            resolver = SettingsResolver()
            self._ensure_provider(resolver)
            name = resolver.effective_llm_provider()

            if name != "gosi-brain":
                return self._provider.call(system_prompt, build_user_prompt(prompt_input))

            from app.services.llm_providers.gosi_brain_provider import (
                GosiBrainPayloadRejectedError,
                GosiBrainTimeoutError,
            )

            gb = resolver.effective_gosi_brain()
            model = (gb.get("model") or "model").strip()
            temperature = float(gb.get("temperature") or 0.7)
            max_bytes = int(gb.get("max_request_bytes") or 524288)
            compaction_mode = (gb.get("prompt_compaction") or "auto").strip().lower()

            level = starting_compaction_level(
                system_prompt=system_prompt,
                user_prompt=build_user_prompt(compact_input(prompt_input, 0)),
                max_request_bytes=max_bytes,
                compaction_mode=compaction_mode,
                model=model,
                temperature=temperature,
            )

            last_payload_error: GosiBrainPayloadRejectedError | None = None
            for attempt_level in range(level, MAX_COMPACTION_LEVEL + 1):
                compacted = compact_input(prompt_input, attempt_level)
                user_prompt = build_user_prompt(compacted)
                log.info("GOSI Brain prompt compaction level=%d", attempt_level)

                payload_rejected = False
                for timeout_attempt in range(2):
                    try:
                        return self._provider.call(system_prompt, user_prompt)
                    except GosiBrainTimeoutError as e:
                        if timeout_attempt == 0:
                            log.warning(
                                "GOSI Brain timed out at compaction level %d after %dms; retrying once",
                                attempt_level,
                                e.elapsed_ms,
                            )
                            continue
                        raise RuntimeError(str(e)) from e
                    except GosiBrainPayloadRejectedError as e:
                        last_payload_error = e
                        payload_rejected = True
                        if attempt_level < MAX_COMPACTION_LEVEL:
                            log.warning(
                                "GOSI Brain payload rejected at compaction level %d (%d bytes); "
                                "retrying with level %d",
                                attempt_level,
                                e.request_bytes,
                                attempt_level + 1,
                            )
                        break

                if not payload_rejected:
                    break

            if last_payload_error is not None:
                raise RuntimeError(
                    "GOSI Brain request rejected by API gateway (payload too large). "
                    "Retried with reduced context but all compaction levels failed."
                ) from last_payload_error
            raise RuntimeError("GOSI Brain call failed after prompt compaction retries.")
        except RuntimeError:
            raise
        except Exception as e:
            raise RuntimeError(f"LLM call failed: {str(e)}") from e
