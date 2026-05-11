from app.services.llm_providers.base import LLMProvider
import time

try:
    from openai import OpenAI  # type: ignore
except Exception:  # pragma: no cover
    OpenAI = None


class OpenAIProvider(LLMProvider):

    def __init__(
        self,
        *,
        api_key: str | None = None,
        base_url: str | None = None,
        model: str | None = None,
    ):
        if OpenAI is None:
            raise RuntimeError("Missing dependency for OpenAI. Install `openai` to use the OpenAI provider.")
        self._api_key = (api_key or "").strip()
        self._base_url = (base_url or "").strip() or None
        self._model = (model or "").strip() or None
        self._client = None

    def call(self, system_prompt: str, user_prompt: str) -> str:
        if not self._api_key:
            raise RuntimeError("Missing OPENAI_API_KEY. Set it in Settings UI or environment to use OpenAI.")
        if self._client is None:
            url = self._base_url or "https://api.openai.com/v1"
            self._client = OpenAI(api_key=self._api_key, base_url=url)
        time.sleep(2) # add one second delay
        model = self._model or "gpt-4o-mini"
        response = self._client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            temperature=0.2
        )

        return response.choices[0].message.content