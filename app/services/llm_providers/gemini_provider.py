from google import genai

from app.config import GOOGLE_API_KEY, GEMINI_MODEL
from app.services.llm_providers.base import LLMProvider


class GeminiProvider(LLMProvider):

    def __init__(self):
        # Client uses GEMINI_API_KEY / GOOGLE_API_KEY from env by default.
        self.client = genai.Client(api_key=GOOGLE_API_KEY) if GOOGLE_API_KEY else genai.Client()

    def call(self, system_prompt: str, user_prompt: str) -> str:
        full_prompt = f"{system_prompt}\n\n{user_prompt}"

        response = self.client.models.generate_content(model=GEMINI_MODEL, contents=full_prompt)
        return response.text