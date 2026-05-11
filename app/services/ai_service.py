from __future__ import annotations

from typing import Any

from app.services.settings_resolver import SettingsResolver


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
        g = resolver.effective_google()
        return ("gemini", g.get("api_key"), g.get("model"))

    def call(self, system_prompt: str, user_prompt: str) -> str:
        try:
            resolver = SettingsResolver()
            sig = self._config_sig(resolver)
            if self._provider is None or self._sig != sig:
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
                elif name == "gemini":
                    from app.services.llm_providers.gemini_provider import GeminiProvider

                    g = resolver.effective_google()
                    self._provider = GeminiProvider(
                        api_key=g.get("api_key"),
                        model=g.get("model"),
                    )
                else:
                    raise ValueError(f"Unknown LLM provider: {name}")

            return self._provider.call(system_prompt, user_prompt)

        except Exception as e:
            raise RuntimeError(f"LLM call failed: {str(e)}")