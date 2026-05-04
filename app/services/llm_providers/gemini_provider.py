from app.config import GOOGLE_API_KEY, GEMINI_MODEL
from app.services.llm_providers.base import LLMProvider

try:
    from google import genai  # type: ignore
    from google.genai import types as genai_types  # type: ignore
except Exception:  # pragma: no cover
    genai = None
    genai_types = None


class GeminiProvider(LLMProvider):

    def __init__(self):
        if genai is None:
            raise RuntimeError("Missing dependency for Gemini. Install `google-genai` (or the configured SDK) to use Gemini.")
        # Client uses GEMINI_API_KEY / GOOGLE_API_KEY from env by default.
        self.client = genai.Client(api_key=GOOGLE_API_KEY) if GOOGLE_API_KEY else genai.Client()

    def call(self, system_prompt: str, user_prompt: str, *, json_mode: bool = False) -> str:
        full_prompt = f"{system_prompt}\n\n{user_prompt}"

        if json_mode and genai_types is not None:
            config = genai_types.GenerateContentConfig(response_mime_type="application/json")
            response = self.client.models.generate_content(
                model=GEMINI_MODEL, contents=full_prompt, config=config
            )
        else:
            response = self.client.models.generate_content(model=GEMINI_MODEL, contents=full_prompt)
        return response.text