 
from app.config import LLM_PROVIDER


class LLMService:

    def __init__(self):
        if LLM_PROVIDER == "openai":
            from app.services.llm_providers.openai_provider import OpenAIProvider

            self.provider = OpenAIProvider()

        elif LLM_PROVIDER == "gemini":
            from app.services.llm_providers.gemini_provider import GeminiProvider

            self.provider = GeminiProvider()

        else:
            raise ValueError(f"Unknown LLM provider: {LLM_PROVIDER}")

    def call(self, system_prompt: str, user_prompt: str) -> str:
        try:
            return self.provider.call(system_prompt, user_prompt)

        except Exception as e:
            raise RuntimeError(f"LLM call failed: {str(e)}")