from openai import OpenAI
from app.config import OPENAI_API_KEY, OPENAI_URL
from app.services.llm_providers.base import LLMProvider


class OpenAIProvider(LLMProvider):

    def __init__(self):
        self.client = OpenAI(api_key=OPENAI_API_KEY, base_url= OPENAI_URL)

    def call(self, system_prompt: str, user_prompt: str) -> str:
        response = self.client.chat.completions.create(
            model="gpt-4.1-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            temperature=0.2
        )

        return response.choices[0].message.content