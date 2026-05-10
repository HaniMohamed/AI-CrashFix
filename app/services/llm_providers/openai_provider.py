from app.config import OPENAI_API_KEY, OPENAI_MODEL, OPENAI_URL
from app.services.llm_providers.base import LLMProvider
import time

try:
    from openai import OpenAI  # type: ignore
except Exception:  # pragma: no cover
    OpenAI = None


class OpenAIProvider(LLMProvider):

    def __init__(self):
        if OpenAI is None:
            raise RuntimeError("Missing dependency for OpenAI. Install `openai` to use the OpenAI provider.")
        # Lazy-init client so backend can start without keys (UI/settings still usable).
        self._client = None

    def call(self, system_prompt: str, user_prompt: str) -> str:
        if not (OPENAI_API_KEY or "").strip():
            raise RuntimeError("Missing OPENAI_API_KEY. Set it in Settings UI or environment to use OpenAI.")
        if self._client is None:
            self._client = OpenAI(api_key=OPENAI_API_KEY, base_url=OPENAI_URL)
        time.sleep(2) # add one second delay
        response = self._client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            temperature=0.2
        )

        return response.choices[0].message.content