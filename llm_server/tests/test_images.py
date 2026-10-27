"""The frame of an event (v0.7.35): image models in the hello, the prompt by the family's template, the backends."""

import asyncio
import base64

import httpx
from fastapi.testclient import TestClient
from pydantic_ai.messages import ModelResponse, TextPart, ToolCallPart
from pydantic_ai.models.function import AgentInfo, FunctionModel

from llm_server import images, prompts
from llm_server.app import create_app
from llm_server.config import ImageModel
from llm_server.images import Drawn, ImageError, ImagePrices, draw

from conftest import AUTH, hello, make_services, request

EVENT = {"event": "Волк вцепился в край щита.", "place": "Тропа лесорубов", "time": "вечер, 19:40",
         "hero": "Айра, человек, женщина; кольчуга, щит", "people": ["Олех, лесоруб с топором"]}
RECRAFT = ImageModel("recraft/recraft-v4.1-flash", "Recraft V4.1 Flash", "recraft", 0.0072)


def ask(services, params: dict) -> dict:
    with TestClient(create_app(services.settings, services=services)) as c, c.websocket_connect("/ws", headers=AUTH) as ws:
        hello(ws)
        request(ws, "g-2", "image.request", params)
        return ws.receive_json()


def test_hello_offers_the_image_models_and_the_default(client):
    with client.websocket_connect("/ws", headers=AUTH) as ws:
        result = hello(ws)["result"]
    assert result["image_model"] == "recraft/recraft-v4.1-flash"
    ids = [m["id"] for m in result["image_models"]]
    assert ids[0] == "recraft/recraft-v4.1-flash" and "black-forest-labs/flux-3-image-klein" in ids
    assert all(m["usd_per_image"] > 0 for m in result["image_models"])


def test_no_images_on_the_server_hides_them(data_dir):
    services = make_services(data_dir, image_models=())
    with TestClient(create_app(services.settings, services=services)) as c, c.websocket_connect("/ws", headers=AUTH) as ws:
        result = hello(ws)["result"]
        request(ws, "g-2", "image.request", EVENT)
        msg = ws.receive_json()
    assert result["image_model"] == "" and result["image_models"] == []
    assert msg["error"]["data"]["reason"] == "invalid_params"


def test_the_stub_draws_a_png(data_dir):
    msg = ask(make_services(data_dir), {**EVENT, "style": "гравюра"})
    data = base64.b64decode(msg["result"]["data_b64"])
    assert msg["result"]["mime"] == "image/png" and data.startswith(b"\x89PNG")
    assert msg["result"]["prompt"].startswith("гравюра.")


def test_each_family_has_its_own_template():
    assert prompts.image_prompt("recraft", "A wolf bites a shield.", "ink") == "ink. A wolf bites a shield."
    assert prompts.image_prompt("flux", "A wolf bites a shield.", "ink") == "A wolf bites a shield. Drawn as ink."
    assert prompts.image_prompt("flux", "A wolf.", "").endswith(prompts.DEFAULT_IMAGE_STYLE + ".")
    assert "Recraft" in prompts.image_instructions("recraft", 700) and "700" in prompts.image_instructions("recraft", 700)
    assert "не понимает отрицаний" in prompts.image_instructions("flux", 700)
    assert "negative" in prompts.image_instructions("sd", 700)
    frame = prompts.image_frame(**{k: EVENT[k] for k in ("event", "place", "time", "hero", "people")})
    assert "Волк вцепился" in frame and "Олех" in frame and "вечер" in frame


def test_the_agent_writes_the_frame_and_the_image_is_paid(data_dir, monkeypatch):
    seen: dict = {}

    def fn(messages, info: AgentInfo) -> ModelResponse:
        seen["instructions"] = messages[0].instructions
        assert not info.output_tools  # JSON in the text: visible in the OpenRouter log (v0.7.38.3)
        return ModelResponse(parts=[TextPart('{"scene": "A grey wolf bites the rim of a round shield.", "negative": ""}')])

    async def fake_draw(spec, prompt, negative, aspect, api_key, client=None):
        seen.update(spec=spec.id, prompt=prompt, aspect=aspect)
        return Drawn("image/webp", base64.b64encode(b"RIFF....WEBP").decode(), 0.007)

    monkeypatch.setattr(images, "draw", fake_draw)
    services = make_services(data_dir, model_factory=lambda m: FunctionModel(fn, model_name=m), turn_handler="agent")
    msg = ask(services, {**EVENT, "image_model": "black-forest-labs/flux-3-image-klein", "style": "ink"})
    assert msg["result"]["mime"] == "image/webp"
    assert seen["spec"] == "black-forest-labs/flux-3-image-klein" and seen["aspect"] == "16:9"
    assert seen["prompt"] == "A grey wolf bites the rim of a round shield. Drawn as ink."
    assert "FLUX" in seen["instructions"]
    assert msg["result"]["usage"]["cost_usd"] >= 0.007
    assert services.budget.spent_today() >= 0.007
    assert services.images.prices.price(services.images.models["black-forest-labs/flux-3-image-klein"]) == 0.007


def test_a_spent_day_draws_nothing(data_dir):
    services = make_services(data_dir, model_factory=lambda m: FunctionModel(lambda *_: None, model_name=m), turn_handler="agent",
                             daily_budget_usd=0.01)
    services.budget.add(0.02)
    assert ask(services, EVENT)["error"]["data"]["reason"] == "budget_exceeded"


def test_an_unknown_image_model_is_refused(data_dir):
    assert ask(make_services(data_dir), {**EVENT, "image_model": "openai/dall-e-9"})["error"]["data"]["reason"] == "invalid_params"


def _run(spec: ImageModel, handler) -> Drawn:
    async def go() -> Drawn:
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
            return await draw(spec, "a wolf", "blurry", "16:9", "key", client=c)
    return asyncio.run(go())


def test_openrouter_answers_with_base64_and_its_cost():
    def handler(req: httpx.Request) -> httpx.Response:
        assert req.url.path == "/api/v1/images"
        body = __import__("json").loads(req.content)
        assert body["model"] == RECRAFT.id and body["aspect_ratio"] == "16:9" and body["prompt"] == "a wolf"
        return httpx.Response(200, json={"data": [{"b64_json": "QUJD", "media_type": "image/webp"}], "usage": {"cost": 0.0071}})

    drawn = _run(RECRAFT, handler)
    assert (drawn.mime, drawn.data_b64, drawn.cost_usd) == ("image/webp", "QUJD", 0.0071)


def test_openrouter_refusal_is_an_image_error():
    try:
        _run(RECRAFT, lambda req: httpx.Response(400, json={"error": {"message": "nope"}}))
    except ImageError as exc:
        assert "400" in str(exc)
    else:
        raise AssertionError("no error")


def test_an_own_automatic1111_endpoint():
    own = ImageModel("a1111", "SD", "sd", 0.0, backend="a1111", url="http://127.0.0.1:7860/")

    def handler(req: httpx.Request) -> httpx.Response:
        assert str(req.url) == "http://127.0.0.1:7860/sdapi/v1/txt2img"
        body = __import__("json").loads(req.content)
        assert body["negative_prompt"] == "blurry" and (body["width"], body["height"]) == (1024, 576)
        return httpx.Response(200, json={"images": ["iVBO"]})

    drawn = _run(own, handler)
    assert (drawn.mime, drawn.data_b64, drawn.cost_usd) == ("image/png", "iVBO", 0.0)


def test_prices_are_learned_from_the_bills(tmp_path):
    path = tmp_path / "image_prices.json"
    prices = ImagePrices(path)
    assert prices.price(RECRAFT) == 0.0072
    prices.observe(RECRAFT.id, 0.006)
    prices.observe(RECRAFT.id, 0.008)
    assert ImagePrices(path).price(RECRAFT) == 0.007


def test_an_own_forge_offers_the_checkpoints_it_has():
    """v0.7.37: SD_MODELS by file name, whatever the folder and the hash; a silent server offers nothing."""
    from llm_server.images import own_image_models

    def handler(req: httpx.Request) -> httpx.Response:
        if req.url.path == "/sdapi/v1/sd-modules":
            return httpx.Response(200, json=[{"model_name": "qwen_image_vae.safetensors", "filename": "/f/VAE/qwen_image_vae.safetensors"}])
        assert req.url.path == "/sdapi/v1/sd-models"
        return httpx.Response(200, json=[{"title": "Anima/other.safetensors [6bbb]"},
                                         {"title": "Anima/riMixIllustriousAnima_riMixAnima.safetensors [91cf]"},
                                         {"title": "Illustration/aMixIllustrious_aMix.safetensors"}])

    def down(req: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("refused")

    async def ask(h):
        async with httpx.AsyncClient(transport=httpx.MockTransport(h)) as c:
            return await own_image_models("http://127.0.0.1:7860", c)

    own = asyncio.run(ask(handler))
    assert [m.id for m in own] == ["a1111", "sd:amix-illustrious"]
    assert own[1].checkpoint == "Illustration/aMixIllustrious_aMix.safetensors" and own[1].url == "http://127.0.0.1:7860"
    assert asyncio.run(ask(down)) == ()


def test_anima_comes_with_its_modules_found_on_forge():
    """v0.7.38.4: the Qwen VAE and text encoder by name → Forge's paths; without one of them no Anima."""
    from llm_server.images import own_image_models

    def handler(req: httpx.Request) -> httpx.Response:
        if req.url.path == "/sdapi/v1/sd-modules":
            return httpx.Response(200, json=[{"model_name": "qwen_image_vae.safetensors", "filename": "/f/VAE/qwen_image_vae.safetensors"},
                                             {"model_name": "qwen_3_06b_base.safetensors", "filename": "/f/te/qwen_3_06b_base.safetensors"}])
        return httpx.Response(200, json=[{"title": "Anima/riMixIllustriousAnima_riMixAnima.safetensors [91cf]"}])

    async def ask():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
            return await own_image_models("http://127.0.0.1:7860", c)

    anima = asyncio.run(ask())[1]
    assert anima.id == "sd:rimix-anima" and anima.template == "anima"
    assert anima.txt2img["override_settings"]["forge_additional_modules"] == ["/f/VAE/qwen_image_vae.safetensors", "/f/te/qwen_3_06b_base.safetensors"]
    assert (anima.txt2img["sampler_name"], anima.txt2img["cfg_scale"]) == ("Euler a", 6)
    p = prompts.image_prompt("anima", "1boy, wolf, animal. A man fights a wolf.", "ink")
    assert p == "(flat color, no lineart, no outline, Flat vector), 1boy, wolf, animal. A man fights a wolf"
    assert "Anima" in prompts.image_instructions("anima", 700)


def test_every_hello_asks_the_own_server_again(tmp_path, monkeypatch):
    """v0.7.37: Forge started after the server shows up at the next connection, and goes when it stops."""
    from llm_server.config import SD_MODELS

    answer: list[tuple] = [()]

    async def fake_own(url, client=None):
        assert url == "http://127.0.0.1:7860"
        return answer[0]

    monkeypatch.setattr(images, "own_image_models", fake_own)
    services = make_services(tmp_path, a1111_url="http://127.0.0.1:7860", image_model="sd:amix-illustrious")
    seen: list[str] = []

    def ids() -> list[str]:
        with TestClient(create_app(services.settings, services=services)) as c, c.websocket_connect("/ws", headers=AUTH) as ws:
            result = hello(ws)["result"]
            seen.append(result["image_model"])
            return [m["id"] for m in result["image_models"]]

    assert "sd:amix-illustrious" not in ids()
    answer[0] = (SD_MODELS[0],)
    assert ids()[-1] == "sd:amix-illustrious"
    answer[0] = ()
    assert "sd:amix-illustrious" not in ids()
    assert seen == ["recraft/recraft-v4.1-flash", "sd:amix-illustrious", "recraft/recraft-v4.1-flash"]  # the wanted default while it answers


def test_a_checkpoint_model_loads_its_file_with_its_settings():
    from llm_server.config import SD_MODELS

    spec = __import__("dataclasses").replace(SD_MODELS[0], url="http://127.0.0.1:7860", checkpoint="Illustration/aMixIllustrious_aMix.safetensors")

    def handler(req: httpx.Request) -> httpx.Response:
        body = __import__("json").loads(req.content)
        assert (body["width"], body["height"]) == (1024, 1024)  # the model's own size wins over the aspect
        assert (body["sampler_name"], body["steps"], body["cfg_scale"]) == ("Euler a", 32, 6)
        assert "enable_hr" not in body
        assert body["override_settings"] == {"CLIP_stop_at_last_layers": 2, "forge_additional_modules": [], "sd_model_checkpoint": spec.checkpoint}
        assert body["override_settings_restore_afterwards"] is False
        return httpx.Response(200, json={"images": ["iVBO"]})

    assert _run(spec, handler).data_b64 == "iVBO"
    assert "sd_model_checkpoint" not in SD_MODELS[0].txt2img["override_settings"]  # the config is not touched


def test_the_players_additions_go_after_the_scene_and_into_the_negative():
    """v0.7.37: the model's own by default, the player's from the settings, the negative with the agent's or alone."""
    from llm_server.config import SD_MODELS
    from llm_server.images import compose
    from llm_server.protocol import ImageParams

    amix = SD_MODELS[0]
    p = prompts.image_prompt("illustrious", "1boy, wolf, forest.", "book illustration")
    assert p == "(monochrome:0.75), (Sketch art, line art, drawn), 1boy, wolf, forest"  # no prose style (v0.7.38.2)
    prompt, neg = compose(amix, ImageParams(event="x"), p, "crowd, daylight")
    assert prompt.startswith(p + ", masterwork, masterpiece") and prompt.endswith("<lora:rimixO:1.2>")
    assert neg.startswith("lowres, worst quality") and neg.endswith("anthro, crowd, daylight")
    own = ImageParams(event="x", prompt_add="ink, <lora:other:1>,", negative_add="blurry", negative_only=True)
    assert compose(amix, own, p, "crowd") == (p + ", ink, <lora:other:1>", "blurry")
    assert compose(amix, ImageParams(event="x", prompt_add="", negative_add=""), p, "crowd") == (p, "crowd")
    assert compose(RECRAFT, ImageParams(event="x", prompt_add="cinematic", negative_add="blurry"), p, "crowd") == (p + ", cinematic", "")
    assert "Danbooru" in prompts.image_instructions("illustrious", 700)


def test_solo_goes_when_a_beast_is_in_the_frame():
    from llm_server.images import booru_scene

    assert booru_scene("1boy, solo, wolf, animal, sword, forest") == "1boy, wolf, animal, sword, forest"
    assert booru_scene("1girl, solo, dress, swing") == "1girl, solo, dress, swing"


def test_hello_offers_each_models_additions():
    from llm_server.config import SD_MODELS
    from llm_server.images import ImageCatalog

    info = {m.id: m for m in ImageCatalog((RECRAFT, *SD_MODELS), RECRAFT.id, ImagePrices(None)).infos()}
    assert info["sd:amix-illustrious"].negative and "<lora:rimixO:1.2>" in info["sd:amix-illustrious"].prompt_add
    assert not info[RECRAFT.id].negative and info[RECRAFT.id].prompt_add == ""
