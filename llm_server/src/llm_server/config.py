"""Server configuration from environment variables (and the root .env, which never overrides real env)."""

import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

from . import REPO_ROOT

MAX_MESSAGE_BYTES = 8 * 1024 * 1024  # ADR-0009 §2; 8 MB since 0.71.0: an image comes as base64

DEFAULT_MODEL = "deepseek/deepseek-v4.1-flash-1017"  # ADR-0011, since v0.7.3
# The whitelist the player can pick from in the game settings; the server owner pays, so the server decides.
DEFAULT_MODELS = (
    "deepseek/deepseek-v4.1-flash-1017",
    "anthropic/claude-haiku-5.5",
    "qwen/qwen3.8-27b",  # Qwen3.8 Omni Flash left (v0.7.21): its only provider has no forced tool_choice — every turn failed
    "google/gemini-3.8-flash",
    # z-ai/glm-5.3-flash left (v0.7.34.2): 81.5% on the goldens against DeepSeek's 89.6%, 4.7× dearer (docs/tech/model-comparison-2026-10-26.md)
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

# No provider is pinned first (v0.7.34.1, was Relace from 2026-10-24): the picker ranks them by the real cost of our
# turn, with the cache and each provider's own bills (llm/providers.py).



@dataclass(frozen=True)
class ImageModel:
    """A model that draws an event's frame (v0.7.35). `backend` — who draws: "openrouter" (`url` empty) or, later, an
    own endpoint such as AUTOMATIC1111 at `url`; `template` — prompts/images/<template>.md.j2, how this family wants
    its prompt written; `usd_per_image` — the estimate until our own bills say better."""

    id: str
    name: str
    template: str
    usd_per_image: float
    backend: str = "openrouter"
    url: str = ""
    # The player's settings start from these (v0.7.37): put before every prompt (quality tags, a LoRA) and the
    # negative prompt; `negative` — the backend takes a negative prompt at all.
    prompt_add: str = ""
    negative_add: str = ""
    # An own server (v0.7.37): the checkpoint it loads for this model (its title there), the canvas's side at 1:1
    # (768 — SD 1.5, 1024 — SDXL) and the txt2img fields the checkpoint's author recommends.
    # Forge builds the model from the checkpoint and `forge_additional_modules`: Anima's Qwen VAE on an SDXL
    # checkpoint draws black, so an SDXL model clears them in the same request as its checkpoint.
    checkpoint: str = ""
    side: int = 768
    txt2img: dict = field(default_factory=dict, hash=False)
    # Module files the checkpoint needs (v0.7.38.4: Anima's Qwen VAE and text encoder) by name; the server finds their
    # paths on Forge and leaves the model out when one is missing.
    modules: tuple[str, ...] = ()

    @property
    def negative(self) -> bool:
        return self.backend == "a1111"


# Prices of our first frames (2026-10-27); the server learns the real ones from its bills.
IMAGE_MODELS: tuple[ImageModel, ...] = (
    ImageModel("recraft/recraft-v4.1-flash", "Recraft V4.1 Flash", "recraft", 0.0072),
    ImageModel("recraft/recraft-v4.1", "Recraft V4.1", "recraft", 0.04),
    ImageModel("black-forest-labs/flux-3-image-klein", "FLUX 3 Klein", "flux", 0.0091),
    ImageModel("black-forest-labs/flux.2-pro", "FLUX.2 Pro", "flux", 0.045),
)
DEFAULT_IMAGE_MODEL = "recraft/recraft-v4.1-flash"

# Checkpoints of an own AUTOMATIC1111 / Forge, offered when the server has the file (`checkpoint` — its file name).
SD_MODELS: tuple[ImageModel, ...] = (
    ImageModel("sd:amix-illustrious", "A-Mix Illustrious (свой сервер)", "illustrious", 0.0, backend="a1111",
               checkpoint="aMixIllustrious_aMix.safetensors", side=1024,
               # v0.7.38.2: the author's pick — a square frame, 32 steps, no hires pass (it trebles the wait)
               txt2img={"sampler_name": "Euler a", "steps": 32, "cfg_scale": 6, "width": 1024, "height": 1024,
                        "override_settings": {"CLIP_stop_at_last_layers": 2, "forge_additional_modules": []}},
               prompt_add="masterwork, masterpiece, best quality, detailed, depth of field, high detail, very aesthetic, 8k, "
                          "dynamic pose, dynamic angle, adult, aged up, dynamic lighting, lighting, <lora:rimixO:1.2>",
               negative_add="lowres, worst quality, low quality, bad anatomy, bad hands, extra digits, jpeg artifacts, "
                            "signature, watermark, text, logo, artist name, patreon username, censored, nsfw, nude, "
                            "furry, anthro"),
    # v0.7.38.4: the Ri-mix author's Forge settings, a portrait frame; the author's quality LoRAs
    ImageModel("sd:rimix-anima", "Ri-mix Anima (свой сервер)", "anima", 0.0, backend="a1111",
               checkpoint="riMixIllustriousAnima_riMixAnima.safetensors", side=1024,
               modules=("qwen_image_vae.safetensors", "qwen_3_06b_base.safetensors"),
               txt2img={"sampler_name": "Euler a", "steps": 20, "cfg_scale": 6, "width": 768, "height": 1152,
                        "distilled_cfg_scale": 3.5},  # Forge's «Shift»: the API default, pinned (v0.7.38.7)
               prompt_add="masterwork, masterpiece, best quality, high quality, absurdres, highres, detailed, depth of field, "
                          "high detail, very aesthetic, safe, adult, aged up, "
                          "<lora:anima-base-1-masterpiece-v51:0.8> <lora:anima-highres-aesthetic-boost:0.8>",
               negative_add="worst quality, low quality, score_1, score_2, score_3, artist name, (lowres:1.2), "
                            "(bad anatomy:1.4), bad hands, multiple views, jpeg artifacts, patreon logo, patreon username, "
                            "web address, signature, watermark, nsfw, explicit, nude"),
)
DEFAULT_A1111_URL = "http://127.0.0.1:7860"


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
    image_models: tuple[ImageModel, ...] = IMAGE_MODELS  # LLM_SERVER_IMAGES=0 — none, the brush is hidden (v0.7.35)
    image_model: str = DEFAULT_IMAGE_MODEL
    a1111_url: str = ""  # an own AUTOMATIC1111 / Forge, asked for its models at every hello (v0.7.37); "" — none

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
            image_models=_image_models(),
            a1111_url=_a1111_url(),
            image_model=os.environ.get("LLM_SERVER_IMAGE_MODEL", DEFAULT_IMAGE_MODEL),
        )

    def __repr__(self) -> str:
        # Never let the token or the OpenRouter key reach logs or tracebacks.
        return f"Settings(host={self.host!r}, port={self.port}, handler={self.turn_handler!r}, model={self.model!r}, token=***)"


def _images_on() -> bool:
    return os.environ.get("LLM_SERVER_IMAGES", "1").strip() not in ("0", "false", "no", "")


def _image_models() -> tuple[ImageModel, ...]:
    """LLM_SERVER_IMAGES=0 — none, the brush is hidden."""
    return IMAGE_MODELS if _images_on() else ()


def _a1111_url() -> str:
    """LLM_SERVER_A1111_URL, the default — the local Forge; empty — none."""
    return os.environ.get("LLM_SERVER_A1111_URL", DEFAULT_A1111_URL).strip().rstrip("/") if _images_on() else ""
