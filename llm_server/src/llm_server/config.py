"""Server configuration from environment variables (and the root .env, which never overrides real env)."""

import os
from dataclasses import dataclass

from dotenv import load_dotenv

from . import REPO_ROOT

MAX_MESSAGE_BYTES = 1024 * 1024  # ADR-0009 §2


class ConfigError(RuntimeError):
    pass


@dataclass(frozen=True)
class Settings:
    token: str
    host: str = "127.0.0.1"
    port: int = 8765
    hello_timeout: float = 10.0
    turn_timeout: float = 90.0
    engine_timeout: float = 10.0
    max_concurrent_turns: int = 1
    max_message_bytes: int = MAX_MESSAGE_BYTES
    ws_ping_interval: float = 20.0
    ws_ping_timeout: float = 20.0
    model: str = "stub"

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

        return cls(
            token=token,
            host=os.environ.get("LLM_SERVER_HOST", cls.host),
            port=int(num("LLM_SERVER_PORT", cls.port)),
            hello_timeout=num("LLM_SERVER_HELLO_TIMEOUT", cls.hello_timeout),
            turn_timeout=num("LLM_SERVER_TURN_TIMEOUT", cls.turn_timeout),
            engine_timeout=num("LLM_SERVER_ENGINE_TIMEOUT", cls.engine_timeout),
            max_concurrent_turns=int(num("LLM_SERVER_MAX_TURNS", cls.max_concurrent_turns)),
        )

    def __repr__(self) -> str:
        # Never let the token reach logs or tracebacks.
        return f"Settings(host={self.host!r}, port={self.port}, model={self.model!r}, token=***)"
