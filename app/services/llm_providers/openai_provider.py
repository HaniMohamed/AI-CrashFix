from app.config import OPENAI_API_KEY, OPENAI_URL
from app.services.llm_providers.base import LLMProvider

try:
    from openai import OpenAI  # type: ignore
except Exception:  # pragma: no cover
    OpenAI = None


class OpenAIProvider(LLMProvider):

    def __init__(self):
        if OpenAI is None:
            raise RuntimeError("Missing dependency for OpenAI. Install `openai` to use the OpenAI provider.")
        self.client = OpenAI(api_key=OPENAI_API_KEY, base_url= OPENAI_URL)

    def call(self, system_prompt: str, user_prompt: str, *, json_mode: bool = False) -> str:
        kwargs: dict = {
            "model": "gpt-4.1-mini",
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": 0.2,
        }
        if json_mode:
            kwargs["response_format"] = {"type": "json_object"}

        response = self.client.chat.completions.create(**kwargs)

        return response.choices[0].message.content