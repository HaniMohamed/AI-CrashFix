 
from app.config import LLM_PROVIDER


class LLMService:

    def __init__(self):
        self._provider_name = (LLM_PROVIDER or "").strip().lower()
        self._provider = None

    def call(self, system_prompt: str, user_prompt: str) -> str:
        try:
            if self._provider is None:
                if self._provider_name == "openai":
                    from app.services.llm_providers.openai_provider import OpenAIProvider

                    self._provider = OpenAIProvider()
                elif self._provider_name == "gemini":
                    from app.services.llm_providers.gemini_provider import GeminiProvider

                    self._provider = GeminiProvider()
                else:
                    raise ValueError(f"Unknown LLM provider: {self._provider_name}")

            return self._provider.call(system_prompt, user_prompt)

        except Exception as e:
            raise RuntimeError(f"LLM call failed: {str(e)}")