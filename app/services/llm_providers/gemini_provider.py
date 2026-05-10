from app.config import GOOGLE_API_KEY, GEMINI_MODEL
from app.services.llm_providers.base import LLMProvider

try:
    from google import genai  # type: ignore
except Exception:  # pragma: no cover
    genai = None


class GeminiProvider(LLMProvider):

    def __init__(self):
        if genai is None:
            raise RuntimeError("Missing dependency for Gemini. Install `google-genai` (or the configured SDK) to use Gemini.")
        # Lazy-init client so backend can start without keys (UI/settings still usable).
        self._client = None

    def call(self, system_prompt: str, user_prompt: str) -> str:
        if not (GOOGLE_API_KEY or "").strip():
            raise RuntimeError("Missing GOOGLE_API_KEY. Set it in Settings UI or environment to use Gemini.")
        if self._client is None:
            # Always pass the key explicitly so behavior is deterministic.
            self._client = genai.Client(api_key=GOOGLE_API_KEY)
        full_prompt = f"{system_prompt}\n\n{user_prompt}"

        response = self._client.models.generate_content(model=GEMINI_MODEL, contents=full_prompt)
        return response.text