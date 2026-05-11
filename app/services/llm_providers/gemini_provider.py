from app.services.llm_providers.base import LLMProvider

try:
    from google import genai  # type: ignore
except Exception:  # pragma: no cover
    genai = None


class GeminiProvider(LLMProvider):

    def __init__(self, *, api_key: str | None = None, model: str | None = None):
        if genai is None:
            raise RuntimeError("Missing dependency for Gemini. Install `google-genai` (or the configured SDK) to use Gemini.")
        self._api_key = (api_key or "").strip()
        self._model = (model or "").strip() or None
        self._client = None

    def call(self, system_prompt: str, user_prompt: str) -> str:
        if not self._api_key:
            raise RuntimeError("Missing GOOGLE_API_KEY. Set it in Settings UI or environment to use Gemini.")
        if self._client is None:
            self._client = genai.Client(api_key=self._api_key)
        full_prompt = f"{system_prompt}\n\n{user_prompt}"
        model = self._model or "gemini-2.5-flash"
        response = self._client.models.generate_content(model=model, contents=full_prompt)
        return response.text