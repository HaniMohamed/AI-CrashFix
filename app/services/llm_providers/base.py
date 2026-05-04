from abc import ABC, abstractmethod


class LLMProvider(ABC):

    @abstractmethod
    def call(self, system_prompt: str, user_prompt: str, *, json_mode: bool = False) -> str:
        pass