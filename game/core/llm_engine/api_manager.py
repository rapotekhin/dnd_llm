"""
API Manager for OpenRouter (Gemini via LangChain)
"""

import os
import requests
from pathlib import Path
from typing import Optional, Type, Any, Dict

from dotenv import load_dotenv, set_key
from langchain_core.runnables import RunnableConfig
from localization import loc
from pydantic import BaseModel

from langchain_openai import ChatOpenAI
from langchain.output_parsers import PydanticOutputParser
from langchain.prompts import ChatPromptTemplate

# Загружаем .env до чтения LANGFUSE_* — иначе при импорте модуля ключи ещё пустые
_ENV_FILE = Path(__file__).resolve().parent.parent.parent.parent / ".env"
load_dotenv(_ENV_FILE)

# Инициализация Langfuse для трейсинга
# Langfuse использует env: LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST
try:
    from langfuse import Langfuse
    _pk = os.getenv("LANGFUSE_PUBLIC_KEY")
    _sk = os.getenv("LANGFUSE_SECRET_KEY")
    _host = os.getenv("LANGFUSE_HOST", "https://cloud.langfuse.com")
    if _pk and _sk:
        Langfuse(public_key=_pk, secret_key=_sk, host=_host)
    LANGFUSE_AVAILABLE = bool(_pk and _sk)
except ImportError:
    LANGFUSE_AVAILABLE = False

class APIManager:
    OPENROUTER_CREDITS_URL = "https://openrouter.ai/api/v1/credits"
    ENV_FILE = Path(__file__).parent.parent.parent.parent / ".env"

    def __init__(self):
        self.api_key: Optional[str] = None
        self.balance: float = 0.0
        self.usage: float = 0.0
        self.is_valid: bool = False
        self.error_message: str = ""

        load_dotenv(self.ENV_FILE)
        self._load_key_from_env()

        # 🔥 Главный клиент LLM
        self.llm = ChatOpenAI(
            # model="google/gemini-2.5-flash-lite-preview-09-2025",  # меняй при желании
            model="google/gemini-3.1-flash-lite-preview",
            # model="z-ai/glm-4.7-flash",
            # model="openai/gpt-oss-120b",
            # model="stepfun/step-3.5-flash",
            # model="nvidia/nemotron-3-nano-30b-a3b",
            # model="qwen/qwen3-30b-a3b-thinking-2507",
            # model="qwen/qwen3-235b-a22b-2507",
            # model="x-ai/grok-4.1-fast",
            # model="openrouter/free",
            # model="qwen/qwen3.5-flash-02-23",
            api_key=self.api_key,
            base_url="https://openrouter.ai/api/v1",
            temperature=0.35
        )

    # --------------------------------------------------
    # API KEY MANAGEMENT
    # --------------------------------------------------

    def _load_key_from_env(self):
        self.api_key = os.getenv("OPENROUTER_API_KEY")
        self.langfuse_public_key = os.getenv("LANGFUSE_PUBLIC_KEY")
        self.langfuse_secret_key = os.getenv("LANGFUSE_SECRET_KEY")
        self.langfuse_host = os.getenv("LANGFUSE_HOST")
        self.langfuse_enabled = os.getenv("LANGFUSE_ENABLED") == "1"
        if self.api_key:
            self.validate_key(self.api_key)

    def validate_key(self, api_key: str) -> bool:
        self.api_key = api_key
        self.is_valid = False
        self.error_message = ""

        if not api_key.strip():
            self.error_message = loc["api_key_empty"]
            return False

        try:
            headers = {"Authorization": f"Bearer {api_key.strip()}"}
            response = requests.get(self.OPENROUTER_CREDITS_URL, headers=headers, timeout=10)

            if response.status_code != 200:
                self.error_message = loc["api_key_invalid"]
                return False

            data = response.json().get("data", {})
            self.balance = data.get("total_credits", 0.0)
            self.usage = data.get("total_usage", 0.0)

            self.is_valid = (self.balance - self.usage) > 0
            return self.is_valid

        except Exception as e:
            self.error_message = f"{loc['api_error']}: {str(e)}"
            return False

    def save_key_to_env(self, api_key: str) -> bool:
        try:
            if not self.ENV_FILE.exists():
                self.ENV_FILE.touch()
            set_key(str(self.ENV_FILE), "OPENROUTER_API_KEY", api_key.strip())
            self.api_key = api_key.strip()
            return True
        except Exception as e:
            self.error_message = f"{loc['api_save_error']}: {str(e)}"
            return False

    def get_remaining_balance(self) -> float:
        return max(0, self.balance - self.usage)

    # --------------------------------------------------
    # MODEL CONFIG (for exploration, Pydantic AI, etc.)
    # --------------------------------------------------

    @property
    def model_name(self) -> str:
        """Model ID used by LLM (e.g. x-ai/grok-4.1-fast). Single source of truth."""
        return getattr(self.llm, "model", None) or getattr(self.llm, "model_name", None) or "x-ai/grok-4.1-fast"

    def get_pydantic_ai_model(self):
        """
        Pydantic AI model configured like self.llm (OpenRouter, same api_key, model).
        Use this so all LLM settings come from APIManager.

        IMPORTANT: We create a fresh httpx.AsyncClient each time instead of using
        pydantic-ai's global cached_async_http_client. The cached client binds itself
        to the asyncio event loop of the first thread that uses it (exploration thread).
        If a second thread (social, trade, etc.) then calls run_sync, its event loop is
        different, causing a permanent hang on the HTTP request.  A fresh client per
        model instance avoids this cross-thread event-loop conflict.
        """
        try:
            from pydantic_ai.models.openrouter import OpenRouterModel
            from pydantic_ai.providers.openrouter import OpenRouterProvider
            import httpx
        except ImportError:
            raise ImportError(
                "pydantic-ai[openrouter] required for exploration: pip install 'pydantic-ai[openrouter]'"
            )

        http_client = httpx.AsyncClient(timeout=httpx.Timeout(120.0))
        provider = OpenRouterProvider(api_key=self.api_key, http_client=http_client)
        return OpenRouterModel(self.model_name, provider=provider)

    # --------------------------------------------------
    # 🔥 LLM GENERATION (STRUCTURED)
    # --------------------------------------------------

    def generate_with_format(
        self,
        prompt: str,
        schema: Type[BaseModel],
        config: Optional[RunnableConfig] = None,
        system_prompt: Optional[str] = None,
    ) -> BaseModel:
        """
        Генерация ответа с Pydantic структурой.
        config: RunnableConfig (callbacks, metadata) для Langfuse и др.
        system_prompt: если задан — уходит отдельным system-сообщением в начале запроса.
          Так OpenRouter/Gemini могут закэшировать этот блок (KV cache) и считать меньше за повторы.
        """

        parser = PydanticOutputParser(pydantic_object=schema)
        format_instructions = parser.get_format_instructions()

        if system_prompt:
            # System отдельно → бэкенд может кэшировать (prompt caching), платим меньше за повторы
            prompt_template = ChatPromptTemplate.from_messages([
                ("system", system_prompt),
                ("human", "{prompt}\n\n{format_instructions}"),
            ])
        else:
            prompt_template = ChatPromptTemplate.from_template(
                "{prompt}\n\n{format_instructions}"
            )

        chain = prompt_template | self.llm | parser

        result = chain.invoke(
            {
                "prompt": prompt,
                "format_instructions": format_instructions,
            },
            config=config or {},
        )

        return result

    # --------------------------------------------------
    # STATUS OUTPUT
    # --------------------------------------------------

    def get_status_text(self) -> str:
        if self.is_valid:
            return f"{loc['api_status_active']} (${self.get_remaining_balance():.2f})"
        elif self.error_message:
            return f"LLM: {self.error_message}"
        else:
            return loc["api_status_inactive"]

    def print_status(self):
        print("=" * 50)
        print("OpenRouter API Status:")
        print(f"  API Key: {'SET' if self.api_key else 'NOT SET'}")
        if self.is_valid:
            print(f"  Remaining: ${self.get_remaining_balance():.2f}")
        else:
            print(f"  ERROR: {self.error_message}")
        print("=" * 50)
