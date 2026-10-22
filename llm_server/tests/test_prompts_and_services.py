import json

import pytest
from jinja2 import UndefinedError

from llm_server import REPO_ROOT, prompts
from llm_server.llm.budget import DailyBudget
from llm_server.llm.catalog import ModelCatalog
from llm_server.protocol import ItemProperty, Snapshot

from conftest import tavern_snapshot

INNKEEPER = "npc_innkeeper"


def snap() -> Snapshot:
    return Snapshot.model_validate(tavern_snapshot())


def test_exploration_prompt():
    text = prompts.system_prompt("exploration", snap(), None)
    assert "Таверна «Хромой олень» — общий зал [brod-tavern-hall]" in text
    assert "Кухня таверны [brod-tavern-kitchen]" in text  # exits with ids for `move`
    assert "10 зм" in text
    assert "женском роде" in text
    assert "Сил 16" in text and "athletics +5*" in text and "(* — владеет)" in text
    assert "Надето и в руках (слот: предмет [id]): armor: Кольчуга [chain_mail], shield: Щит [shield]" in text
    assert "Заклинатель" not in text
    assert "## Мир: Сумеречная Марка" in text and "Пепельный Князь" in text
    assert "Забытые Королевства" in text  # the rule against other settings
    assert "Классический" in text and "Вуали" in text and "пытки" in text
    assert "История персонажа: Айра стояла" in text
    assert "\n\n\n" not in text


def test_caster_sheet_in_the_prompt():
    raw = tavern_snapshot()
    raw["character"].update({"class_name": "Волшебник", "spell_save_dc": 13, "cantrips": ["Огненный снаряд"],
                             "spells": ["Волшебная стрела", "Щит"], "spell_slots": [{"level": 1, "left": 1, "max": 2}]})
    text = prompts.system_prompt("exploration", Snapshot.model_validate(raw), None)
    assert "Заклинатель: Сл спасброска 13; ячейки: 1 круг 1/2." in text
    assert "Заговоры: Огненный снаряд." in text
    assert "Заклинания: Волшебная стрела, Щит." in text


def test_style_and_content_limits_in_the_prompt():
    raw = tavern_snapshot()
    raw["world"].update({"dm_style": "dry", "violence": "mild", "lines": ["пауки"], "veils": []})
    text = prompts.system_prompt("exploration", Snapshot.model_validate(raw), None)
    assert "Сухой: коротко и по делу" in text
    assert "мягко:" in text
    assert "Линии" in text and "пауки" in text and "Вуали" not in text
    assert "тёмное фэнтези с надеждой: серая мораль" in text  # the pack's tone replaces the default


def test_found_secrets_are_facts_in_the_scene():
    raw = tavern_snapshot()
    raw["scene"]["found"] = ["следы босых ног ведут к стене"]
    text = prompts.system_prompt("exploration", Snapshot.model_validate(raw), None)
    assert "Игрок уже заметил или нашёл" in text and "следы босых ног" in text


def test_npc_prompts():
    s = snap()
    npc = next(n for n in s.scene.npcs if n.npc_id == INNKEEPER)
    social = prompts.system_prompt("social", s, npc)
    trade = prompts.system_prompt("trade", s, npc)
    assert social.startswith("# Ты — Бруно Хмель")
    assert "target_id = \"" + INNKEEPER in social
    assert "Покупка и оплата — эффектами" in social and "Платный вариант" not in social  # payment details by rules("pay")
    assert "Сделки — только через панель сделки" in trade and "Покупка и оплата" not in trade
    with pytest.raises(ValueError):
        prompts.system_prompt("social", s, None)


def test_rule_topics_out_of_the_prompt_unless_the_scene_needs_them():
    # v0.7.20.4: a topic's rules come by `rules(topic)`; the index names the rest, the scene brings its own
    s = snap()
    text = prompts.system_prompt("exploration", s, None)
    assert "Снаряжение — эффектом `equip`" not in text and "`equip` — надеть, снять" in text
    assert "Новое место — только `create_place`" not in text
    s.scene.open_edges = ["[0] чаща по обе стороны просеки (forest)"]
    text = prompts.system_prompt("exploration", s, None)
    assert "Новое место — только `create_place` на открытом краю" in text and "`places` —" not in text
    assert all(prompts.topic_text(k).strip() for k in prompts.TOPICS)


def test_trade_prompt_lists_engine_prices_and_haggle_state():
    raw = tavern_snapshot()
    raw["trade"] = {"npc_id": INNKEEPER, "purse_cp": 3000, "haggle_pct": 10,
                    "stock": [{"item_id": "ale", "name": "Кружка эля", "qty": 40, "price_cp": 4}],
                    "buys": [{"item_id": "handaxe", "name": "Ручной топор", "qty": 2, "price_cp": 250}]}
    s = Snapshot.model_validate(raw)
    npc = next(n for n in s.scene.npcs if n.npc_id == INNKEEPER)
    text = prompts.system_prompt("trade", s, npc)
    assert "Кошелёк Бруно Хмель: 30 зм" in text
    assert "Кружка эля — 4 мм, 40 шт." in text and "Ручной топор — 2 зм 5 см" in text
    assert "скидкой 10%" in text
    raw["trade"].update({"haggle_pct": 0, "haggle_locked": True, "stock": []})
    text = prompts.system_prompt("trade", Snapshot.model_validate(raw), npc)
    assert "до завтра ты не уступаешь" in text and "ничего не осталось" in text


def test_prompt_without_character_or_scene_still_renders():
    text = prompts.system_prompt("exploration", Snapshot(), None)
    assert "Избегай родовых форм".lower() in text.lower()


def test_strict_templates_fail_on_missing_variables():
    with pytest.raises(UndefinedError):
        prompts.render("turn.md.j2", mode="exploration")


def test_turn_prompt_kinds():
    s = snap()
    assert "«Таверна «Хромой олень» — общий зал». Опиши именно его" in prompts.turn_prompt("exploration", "enter", "", s, None)
    assert "вернулся в общую сцену" in prompts.turn_prompt("exploration", "resume", "", s, None)
    assert "Действие игрока: прыгаю" in prompts.turn_prompt("exploration", "action", "прыгаю", s, None)
    assert "Мастер: Таверна шумит." in prompts.turn_prompt("exploration", "action", "x", s, None)
    npc = next(n for n in s.scene.npcs if n.npc_id == INNKEEPER)
    deal = prompts.turn_prompt("trade", "deal", "Куплено: Кружка эля — 4 мм; итог: игрок платит торговцу 4 мм", s, npc)
    assert "заключил сделку" in deal and "игрок платит торговцу 4 мм" in deal
    assert "Движок уже бросил проверку: Торг удался" in prompts.turn_prompt("trade", "haggle", "Торг удался", s, npc)


def test_quests_in_the_prompt_and_the_quest_turn():
    raw = tavern_snapshot()
    raw["quests"] = [{"id": "letter_to_ilva", "title": "Письмо для Илвы", "description": "Отнести письмо жрице.", "done": False}]
    s = Snapshot.model_validate(raw)
    text = prompts.system_prompt("exploration", s, None)
    assert "## Задания игрока" in text and "Письмо для Илвы: Отнести письмо жрице." in text
    assert "не даёшь за него опыт" in text
    turn = prompts.turn_prompt("exploration", "quest", "Игрок отдал письмо. Награда: +300 опыта (задание).", s, None)
    assert "выполнил задание" in turn and "+300 опыта" in turn


def test_resources_concentration_and_v060_turns():
    raw = tavern_snapshot()
    raw["character"].update({"resources": [{"name": "Второе дыхание", "left": 0, "max": 1}], "concentration": "Обнаружение магии",
                             "conditions": ["poisoned"]})
    s = Snapshot.model_validate(raw)
    text = prompts.system_prompt("exploration", s, None)
    assert "Второе дыхание 0/1" in text and "Концентрация: Обнаружение магии" in text
    assert "`cast`" in text and "0 HP вне боя — не смерть" in text
    social = prompts.system_prompt("social", s, next(n for n in s.scene.npcs if n.npc_id == INNKEEPER))
    assert "Товары торговца покупаются в торговле" in social
    assert "Игрок колдует" in prompts.turn_prompt("exploration", "ability", "Игрок колдует «Свет»", s, None)
    assert "очнулся с 1 HP" in prompts.turn_prompt("exploration", "downed", "", s, None)


def test_combat_prompt_and_turns():
    raw = tavern_snapshot()
    raw["combat"] = {"round": 2, "enemies": [
        {"id": "e1", "name": "Серый волк 1", "monster": "Волк", "distance_ft": 0, "side": "same", "status": "active", "health": "bloodied"},
        {"id": "e2", "name": "Серый волк 2", "monster": "Волк", "distance_ft": 60, "side": "left", "status": "active", "health": "full"},
        {"id": "e3", "name": "Гоблин", "status": "fled", "health": "fled"}], "log": []}
    s = Snapshot.model_validate(raw)
    text = prompts.system_prompt("combat", s, None)
    assert "## Поле боя (раунд 2)" in text and "Серый волк 1 [e1] (Волк): вплотную, тяжело ранен" in text
    assert "в 60 футах слева" in text and "Гоблин [e3]: сбежал" in text
    assert "Бой ведёт движок" in text and "target_id" in text
    explore = prompts.system_prompt("exploration", snap(), None)
    assert "`next_mode = \"combat\"`" in explore and "`start_combat`" in explore
    assert "Перескажи раунд" in prompts.turn_prompt("combat", "combat_round", "Волк — Укус: промах", s, None)
    assert "Начался бой" in prompts.turn_prompt("combat", "combat_start", "Бой!", s, None)
    assert "эпитафию" in prompts.turn_prompt("combat", "death", "Путь героя", s, None)
    assert "стоит его действия" in prompts.turn_prompt("combat", "action", "опрокидываю стол", s, None)


def test_coins_format():
    assert prompts.coins(1537) == "15 зм 3 см 7 мм"
    assert prompts.coins(0) == "0 зм"


def test_budget_counts_and_resets(tmp_path, monkeypatch):
    b = DailyBudget(tmp_path / "budget.json", 1.0)
    b.add(0.4)
    b.add(0.7)
    assert b.exhausted()
    assert b.left() == 0
    monkeypatch.setattr(DailyBudget, "_today", staticmethod(lambda: "2099-01-01"))
    assert b.spent_today() == 0
    assert DailyBudget(tmp_path / "x.json", None).left() is None


def test_catalog_resolves_only_whitelisted_models():
    c = ModelCatalog(("a/x", "b/y"), "a/x")
    assert c.resolve(None) == "a/x"
    assert c.resolve("b/y") == "b/y"
    assert c.resolve("c/z") is None


def test_item_properties_match_the_godot_vocabulary():
    godot = json.loads((REPO_ROOT / "game" / "data" / "items.json").read_text(encoding="utf-8"))["properties"]
    assert set(godot) == set(ItemProperty.__args__)


def test_openrouter_takes_the_cheapest_provider(monkeypatch):
    from pydantic_ai.models.openrouter import OpenRouterModel
    from pydantic_ai.providers.openrouter import OpenRouterProvider

    from llm_server.agents import settings_for

    model = OpenRouterModel("deepseek/deepseek-v4.1-flash-1017", provider=OpenRouterProvider(api_key="test"))
    assert settings_for(model)["openrouter_provider"] == {"sort": "price", "require_parameters": True}
    monkeypatch.setenv("LLM_SERVER_PROVIDER_SORT", "off")
    assert "openrouter_provider" not in settings_for(model)



def test_no_temperature_for_claude_on_openrouter():
    # v0.7.7: Haiku 5.5 endpoints take no temperature; with require_parameters the request found no provider (404).
    from pydantic_ai.models.openrouter import OpenRouterModel
    from pydantic_ai.providers.openrouter import OpenRouterProvider

    from llm_server.agents import settings_for

    haiku = settings_for(OpenRouterModel("anthropic/claude-haiku-5.5", provider=OpenRouterProvider(api_key="test")))
    assert "temperature" not in haiku and haiku["openrouter_provider"]["require_parameters"] is True
    deepseek = settings_for(OpenRouterModel("deepseek/deepseek-v4.1-flash-1017", provider=OpenRouterProvider(api_key="test")))
    assert deepseek["temperature"] == 0.8


def _endpoint(tag: str, prompt: float, completion: float, uptime: float = 100, tools: bool = True) -> dict:
    return {"tag": tag, "pricing": {"prompt": str(prompt / 1e6), "completion": str(completion / 1e6)}, "uptime_last_30m": uptime,
            "supported_parameters": ["tools", "tool_choice", "temperature"] if tools else ["temperature"]}


def test_the_three_cheapest_providers_with_tools_that_are_up():
    # v0.7.14.4: a slow day of the cheapest provider — the request goes to the cheapest three, fast ones first.
    from llm_server.llm.providers import cheapest

    endpoints = [
        _endpoint("expensive", 0.3, 1.2),
        _endpoint("open-inference/fp4", 0.049, 0.375),
        _endpoint("no-tools", 0.01, 0.01, tools=False),
        _endpoint("down", 0.02, 0.02, uptime=40),
        _endpoint("decart/fp4", 0.09, 0.18),
        _endpoint("deepinfra/fp8", 0.098, 0.294),
        _endpoint("cloudflare", 0.1, 0.6),
    ]
    assert cheapest(endpoints, 3) == ["open-inference/fp4", "decart/fp4", "deepinfra/fp8"]


def test_the_picked_providers_go_into_the_request(monkeypatch):
    from pydantic_ai.models.openrouter import OpenRouterModel
    from pydantic_ai.providers.openrouter import OpenRouterProvider

    from llm_server.agents import settings_for
    from llm_server.llm.providers import PICKER

    model_id = "deepseek/deepseek-v4.1-flash-1017"
    model = OpenRouterModel(model_id, provider=OpenRouterProvider(api_key="test"))
    monkeypatch.setitem(PICKER._ranked, model_id, [("a", "A"), ("b", "B"), ("c", "C"), ("d", "D")])
    monkeypatch.setenv("LLM_SERVER_MIN_TPS", "40")
    assert settings_for(model)["openrouter_provider"] == {"sort": "price", "require_parameters": True, "only": ["a", "b", "c"],
                                                        "allow_fallbacks": True, "preferred_min_throughput": {"p50": 40.0}}
    monkeypatch.setenv("LLM_SERVER_PROVIDER_SORT", "throughput")
    assert "only" not in settings_for(model)["openrouter_provider"]


def test_a_pinned_provider_is_the_only_one(monkeypatch):
    # v0.7.20.5: the player's provider from the settings — no picking, no fallbacks
    from pydantic_ai.models.openrouter import OpenRouterModel
    from pydantic_ai.providers.openrouter import OpenRouterProvider

    from llm_server.agents import settings_for
    from llm_server.llm.providers import PINNED, pinned_for

    model_id = "deepseek/deepseek-v4.1-flash-1017"
    model = OpenRouterModel(model_id, provider=OpenRouterProvider(api_key="test"))
    assert pinned_for(model_id, "relace") == "relace"
    assert pinned_for(model_id, "google-vertex/global") is None and pinned_for(model_id, None) is None
    token = PINNED.set("relace")
    try:
        assert settings_for(model)["openrouter_provider"] == {"only": ["relace"], "order": ["relace"], "allow_fallbacks": False,
                                                            "require_parameters": True}
    finally:
        PINNED.reset(token)
    infos = {m.id: m for m in ModelCatalog(("deepseek/deepseek-v4.1-flash-1017", "openrouter/free"), model_id).infos()}
    assert [p.name for p in infos[model_id].providers] == ["Relace", "OpenInference", "DeepInfra (flex)"]
    assert infos["openrouter/free"].providers == []


def test_the_picker_keeps_its_list_when_openrouter_fails():
    import asyncio

    import httpx

    from llm_server.llm.providers import ProviderPicker

    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request.url.path)
        if len(calls) == 1:
            return httpx.Response(200, json={"data": {"endpoints": [_endpoint("x", 0.1, 0.1), _endpoint("y", 0.2, 0.2)]}})
        return httpx.Response(500)

    picker = ProviderPicker(ttl=0)

    async def twice() -> None:
        for _ in range(2):
            async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
                assert await picker.refresh("m/x", c) == ["x", "y"]

    asyncio.run(twice())
    assert calls == ["/api/v1/models/m/x/endpoints"] * 2


def test_a_provider_observed_slow_leaves_the_three():
    # v0.7.14.5, the live playtest: OpenRouter's own stats did not see OpenInference crawling at 14 tok/s on 40k-token
    # turns — our own timing of each request does.
    from llm_server.llm.providers import ProviderPicker

    picker = ProviderPicker()
    picker._ranked["m"] = [("open-inference/fp4", "OpenInference"), ("decart/fp4", "Decart"), ("relace", "Relace"), ("x", "X")]
    picker.observe("OpenInference", 600, 45.0)  # 13 tok/s
    assert picker.providers("m") == ["decart/fp4", "relace"]
    picker.observe("Decart", 50, 30.0)  # too short to judge
    picker.observe("Relace", 600, 10.0)
    assert picker.providers("m") == ["decart/fp4", "relace"]
    picker.observe("Decart", 600, 60.0)
    picker.observe("Relace", 600, 60.0)
    picker.observe("Relace", 600, 60.0)  # the median of 60, 10, 10 tok/s
    assert picker.providers("m") == ["open-inference/fp4", "decart/fp4", "relace"]  # all slow: the three stay


def test_the_daily_budget_counts_what_openrouter_billed(tmp_path):
    # v0.7.14.5: the catalog price of DeepSeek is 0.3 / 1.2 $ per Mtok, the providers we use bill ~5 times less —
    # the budget takes the `cost` of every answer, retries included.
    import asyncio

    from pydantic_ai import Agent
    from pydantic_ai.messages import ModelResponse, TextPart
    from pydantic_ai.models.function import FunctionModel

    from llm_server.llm.catalog import REQUEST_COSTS, TimedModel

    calls = []

    def answer(messages, info):
        calls.append(1)
        return ModelResponse(parts=[TextPart("ок")], provider_details={"cost": 0.0021, "downstream_provider": "Relace"})

    billed: list[float] = []

    async def run() -> None:
        token = REQUEST_COSTS.set(billed)
        try:
            await Agent(TimedModel(FunctionModel(answer))).run("привет")
            await Agent(TimedModel(FunctionModel(answer))).run("ещё")
        finally:
            REQUEST_COSTS.reset(token)

    asyncio.run(run())
    assert billed == [0.0021, 0.0021]

    from llm_server.config import Settings
    from llm_server.services import Services
    from llm_server.turns import _usage

    class S:
        services = Services.create(Settings(token="x" * 16, data_dir=tmp_path, trace=False))

    from pydantic_ai.usage import RunUsage

    usage = _usage(S, "deepseek/deepseek-v4.1-flash-1017", RunUsage(input_tokens=30000, output_tokens=500), billed)
    assert usage.cost_usd == 0.0042
    assert abs(S.services.budget.spent_today() - 0.0042) < 1e-9
