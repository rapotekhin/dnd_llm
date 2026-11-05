"""One road, review 2, group N (v0.8.4.29.7): one table of a turn's kinds, one continuation on the token limit for every
agent at its own ceiling, the goldens on the game's road, one text of furnishing, the words of a topic in its row."""

from pydantic_ai.exceptions import UnexpectedModelBehavior
from pydantic_ai.messages import ModelResponse, ToolCallPart

from llm_server import agents, prompts
from llm_server.protocol import TurnRequestParams

from conftest import tavern_snapshot
from test_agent import play, scripted


def _params(**kw) -> TurnRequestParams:
    base = {"turn_id": "t-1", "mode": "exploration", "kind": "action", "input": "осматриваю зал", "snapshot": tavern_snapshot()}
    base.update(kw)
    return TurnRequestParams.model_validate(base)


def test_one_table_of_the_kinds_of_a_turn():
    assert agents.turn_kind(_params(kind="quest_act", input="[quest q | act 1 | giver | here | near]")).name == "designer"
    assert agents.turn_kind(_params(kind="prepare", input="[prepare board | room r | prop p1]")).name == "prepare"
    assert agents.turn_kind(_params(kind="enter")).name == "entry"
    assert agents.turn_kind(_params()).name == "turn"
    assert not agents.turn_kind(_params(kind="prepare", input="[prepare furnish | room r]")).router
    assert agents.turn_kind(_params(kind="quest_act", input="[quest q | act 1 | giver | here | near]")).framed


def test_every_agent_goes_on_at_its_own_raised_ceiling():
    assert agents.retry_max_tokens(_params()) == agents.RETRY_MAX_TOKENS
    assert agents.retry_max_tokens(_params(kind="quest_act", input="[quest q | act 1 | giver | here | near]")) == agents.DESIGNER_MAX_TOKENS * 3 // 2
    assert agents.retry_max_tokens(_params(kind="prepare", input="[prepare board | room r | prop p1]")) == 12000
    assert agents.retry_max_tokens(_params(kind="prepare", input="[prepare furnish | room r]")) == agents.RETRY_MAX_TOKENS


def test_a_prepared_room_out_of_tokens_goes_on_from_there(data_dir):
    """The second line had no continuation: a furnishing out of tokens failed with the same ceiling that ran out."""
    seen = []
    fn = scripted(("propose_effect", {"effect": {"kind": "furnish", "props": [{"name": "Свеча", "item_id": "candle"}]}}),
                  ("final", {"narration": ""}))

    async def watched(messages, info):
        seen.append(info.model_settings.get("max_tokens") if info.model_settings else None)
        if len(seen) == 2:
            raise UnexpectedModelBehavior("Model token limit (4000) exceeded before any response was generated.")
        return await fn(messages, info)

    frame = "[prepare furnish | room brod-square]\nКомната: Брод — Площадь.\nКандидаты (item_id — название, цена):\n- candle — Свеча (1 мм)"
    msg, calls, _ = play(data_dir, watched, kind="prepare", input=frame, background=True)
    assert msg["result"]["effect_ids"] == ["e-1"]
    assert [c["method"] for c in calls].count("engine.validate") == 1  # the history went on, the furnishing kept
    assert seen[0] == 4000 and seen[-1] == agents.RETRY_MAX_TOKENS


def test_the_change_of_mode_is_read_in_one_place():
    from llm_server.turns import next_mode_of, picked_options

    out = agents.TurnOutput(narration="x", next_mode="exploration", options=["a", " ", "b"])
    assert next_mode_of(_params(), out) is None  # it stays where it is
    social = next_mode_of(_params(), agents.TurnOutput(narration="x", next_mode="social", npc_id="npc_bruno"))
    assert social is not None and social.npc_id == "npc_bruno"
    assert [o for o, _, _ in picked_options(out)] == ["a", "b"]


def test_one_text_of_furnishing_for_three_prompts():
    snap = _params().snapshot
    snap.scene.furnish = True
    full = prompts.system_prompt("exploration", snap, None)
    entry = prompts.entry_prompt(snap)
    ahead = prompts.prepare_prompt(snap, "furnish")
    for text in (full, entry, ahead):
        assert "source: water" in text and "`container`" in text and "`body`" in text
    assert "find_items" in entry and "find_items" in full
    assert "из кандидатов рамки" in ahead and "Поиска вещей в этом ходе нет" in ahead


def test_the_words_of_a_topic_are_its_row():
    snap = _params().snapshot
    assert "rumors" in prompts.auto_topics("exploration", snap, "О чём говорят в округе?")
    assert "rumors" not in prompts.auto_topics("exploration", snap, "Подхожу к доске объявлений")  # a notice is the board's
    assert "faith" not in prompts.auto_topics("exploration", snap, "Пока действует маскировка, я выгляжу как сектант")
    assert "faith" in prompts.auto_topics("exploration", snap, "Молюсь Маске о удаче")
    assert not prompts.CONTAINER_WORDS.search("Ищу, что тут спрятано") and prompts.CONTAINER_WORDS.search("Спрячу кошель в сундук")
    assert all(isinstance(t, prompts.Topic) for t in prompts.TOPICS.values())
