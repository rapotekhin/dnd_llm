"""Server configuration from environment variables (and the root .env, which never overrides real env)."""

import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

from . import REPO_ROOT

MAX_MESSAGE_BYTES = 1024 * 1024  # ADR-0009 §2

DEFAULT_MODEL = "deepseek/deepseek-v4.1-flash-1017"  # ADR-0011, since v0.7.3
# The whitelist the player can pick from in the game settings; the server owner pays, so the server decides.
DEFAULT_MODELS = (
    "deepseek/deepseek-v4.1-flash-1017",
    "anthropic/claude-haiku-5.5",
    "qwen/qwen3.8-27b",  # Qwen3.8 Omni Flash left (v0.7.21): its only provider has no forced tool_choice — every turn failed
    "google/gemini-3.8-flash",
    # free (v0.7.20.2, the author's request): OpenRouter's free router and free models — limited by requests a day
    "openrouter/free",
    "nvidia/nemotron-3.5-super-vl:free",
    "google/gemma-4-31b-it:free",
    "nvidia/nemotron-3-ultra-550b-a55b:free",
)

# Providers the player may pin a paid model to (v0.7.20.5, the author's request): OpenRouter endpoint tags with a name,
# the fastest and cheapest for a ~20k-token turn by OpenRouter's stats of 2026-10-22 (DeepSeek's — the author's pick).
# Pinned, a request goes only to that provider; free models are left to OpenRouter.
PROVIDERS: dict[str, tuple[tuple[str, str], ...]] = {
    "deepseek/deepseek-v4.1-flash-1017": (("relace", "Relace"), ("open-inference/fp4", "OpenInference"),
                                          ("deepinfra/fp8/flex", "DeepInfra (flex)")),
    "anthropic/claude-haiku-5.5": (("google-vertex/global", "Google Vertex"), ("google-vertex/us", "Google Vertex (US)"),
                                   ("anthropic", "Anthropic")),
    "qwen/qwen3.8-27b": (("near-ai/fp8", "Near AI"), ("modal", "Modal"), ("dekallm", "DekaLLM")),
    "google/gemini-3.8-flash": (("google-ai-studio/flex", "Google AI Studio (flex)"), ("google-ai-studio", "Google AI Studio"),
                                ("google-ai-studio/priority", "Google AI Studio (priority)")),
}


class ConfigError(RuntimeError):
    pass


@dataclass(frozen=True)
class Settings:
    token: str
    host: str = "127.0.0.1"
    port: int = 8765
    hello_timeout: float = 10.0
    turn_timeout: float = 180.0  # a slow provider day: a late answer beats an error (v0.7.14.5, was 90)
    engine_timeout: float = 10.0
    max_concurrent_turns: int = 1
    max_message_bytes: int = MAX_MESSAGE_BYTES
    ws_ping_interval: float = 20.0
    ws_ping_timeout: float = 20.0
    # "agent" = Pydantic AI over OpenRouter; "stub" = no LLM (protocol tests, UI work without money).
    turn_handler: str = "agent"
    model: str = DEFAULT_MODEL
    models: tuple[str, ...] = DEFAULT_MODELS
    openrouter_api_key: str = field(default="", repr=False)
    llm_retries: int = 2  # ADR-0009 §6
    daily_budget_usd: float | None = 1.0
    data_dir: Path = REPO_ROOT / "llm_server" / "var"  # budget counter, generated item library
    langfuse: bool = False
    router: bool = True  # v0.7.20.4: a turn of words only goes with the short prompt; LLM_SERVER_ROUTER=0 — always the full one
    trace: bool = True  # the model side of play sessions in data_dir/traces (v0.7.1); LLM_SERVER_TRACE=0 turns it off

    @classmethod
    def from_env(cls, load_env_file: bool = True) -> "Settings":
        if load_env_file:
            load_dotenv(REPO_ROOT / ".env", override=False)
        token = os.environ.get("LLM_SERVER_TOKEN", "")
        if len(token) < 16:
            raise ConfigError("LLM_SERVER_TOKEN must be set (at least 16 characters)")

        def num(name: str, default: float) -> float:
            raw = os.environ.get(name)
            return float(raw) if raw else default

        handler = os.environ.get("LLM_SERVER_TURN_HANDLER", cls.turn_handler)
        if handler not in ("agent", "stub"):
            raise ConfigError("LLM_SERVER_TURN_HANDLER must be 'agent' or 'stub'")
        key = os.environ.get("OPENROUTER_API_KEY", "")
        if handler == "agent" and not key:
            raise ConfigError("OPENROUTER_API_KEY is required for LLM_SERVER_TURN_HANDLER=agent (or use 'stub')")
        models = tuple(m.strip() for m in os.environ.get("LLM_SERVER_MODELS", ",".join(DEFAULT_MODELS)).split(",") if m.strip())
        model = os.environ.get("LLM_SERVER_MODEL", DEFAULT_MODEL)
        if model not in models:
            models = (model, *models)
        budget_raw = os.environ.get("LLM_SERVER_DAILY_BUDGET_USD", "1.0").strip().lower()
        budget = None if budget_raw in ("", "0", "none", "off") else float(budget_raw)

        return cls(
            token=token,
            host=os.environ.get("LLM_SERVER_HOST", cls.host),
            port=int(num("LLM_SERVER_PORT", cls.port)),
            hello_timeout=num("LLM_SERVER_HELLO_TIMEOUT", cls.hello_timeout),
            turn_timeout=num("LLM_SERVER_TURN_TIMEOUT", cls.turn_timeout),
            engine_timeout=num("LLM_SERVER_ENGINE_TIMEOUT", cls.engine_timeout),
            max_concurrent_turns=int(num("LLM_SERVER_MAX_TURNS", cls.max_concurrent_turns)),
            turn_handler=handler,
            model=model,
            models=models,
            openrouter_api_key=key,
            daily_budget_usd=budget,
            data_dir=Path(os.environ.get("LLM_SERVER_DATA_DIR", str(cls.data_dir))),
            router=os.environ.get("LLM_SERVER_ROUTER", "1").strip() not in ("0", "false", "no", ""),
            trace=os.environ.get("LLM_SERVER_TRACE", "1").strip() not in ("0", "false", "no", ""),
            langfuse=os.environ.get("LANGFUSE_ENABLED") == "1",
        )

    def __repr__(self) -> str:
        # Never let the token or the OpenRouter key reach logs or tracebacks.
        return f"Settings(host={self.host!r}, port={self.port}, handler={self.turn_handler!r}, model={self.model!r}, token=***)"
