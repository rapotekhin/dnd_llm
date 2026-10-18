"""Regression tests for the v0.3.1 P0 fixes (B1–B4 in docs/production/review-2026-10.md)."""

from __future__ import annotations

import os
import queue
import threading
from unittest.mock import MagicMock

import pytest

from _fakes import FakeAgent, collect_until, join_thread_or_stop
from core.entities.npc import NPC
from core.entities.player import Player
from core.gameplay import exploration as exp
from core.gameplay import social_interaction as social
from core.gameplay.schemas.exploration import (
    ActionList,
    ActionOption,
    AgentResolutionOutput,
    SceneDescription,
)
from core.gameplay.schemas.social import (
    NpcGreeting,
    ResponseOption,
    ResponseOptionList,
    SocialResolutionOutput,
)
from core.gameplay.trade import TradeState

from helpers import make_game_equipment
from test_exploration_loop_mocked import _minimal_game_state_two_rooms
from test_social_dialogue_mocked import _minimal_social_state


def _actions() -> ActionList:
    return ActionList(actions=[ActionOption(id=1, description="Look around")])


# ── B1: a "resume" while the loop waits for player input ────────────────────

def test_b1_resume_while_waiting_for_input_is_ignored(monkeypatch: pytest.MonkeyPatch) -> None:
    """Returning from the inventory used to send ``resume`` into a loop that was
    waiting for a choice → ``KeyError: 'text'`` killed the thread."""
    monkeypatch.setattr(exp, "_LOGFIRE_ENABLED", False)
    resolution = FakeAgent([
        AgentResolutionOutput(narration="Nothing unusual.", action="exploration",
                              question_to_player=None),
    ])
    monkeypatch.setattr(exp, "_build_describe_agent",
                        lambda *_a: FakeAgent([SceneDescription(environment_description="A hall.")]))
    monkeypatch.setattr(exp, "_build_generate_actions_agent",
                        lambda *_a: FakeAgent([_actions(), _actions()]))
    monkeypatch.setattr(exp, "_build_resolution_agent", lambda *_a: resolution)

    ui_q: queue.Queue = queue.Queue()
    in_q: queue.Queue = queue.Queue()
    stop = threading.Event()
    gs = _minimal_game_state_two_rooms()
    thr = threading.Thread(
        target=lambda: exp.run_exploration(MagicMock(model_name="stub"), gs, ui_q, in_q, stop),
        daemon=True, name="exploration-b1",
    )
    thr.start()
    collect_until(ui_q, lambda m: m.get("type") == "actions")

    in_q.put({"type": "resume", "summary": ""})
    in_q.put({"type": "input", "text": "1"})
    msgs = collect_until(ui_q, lambda m: m.get("type") in ("narration", "error"))

    assert msgs[-1] == {"type": "narration", "text": "Nothing unusual."}
    stop.set()
    join_thread_or_stop(thr, stop)


class _AliveThread:
    def is_alive(self) -> bool:
        return True


def _bare_main_screen():
    """MainScreen without pygame layout: only the exploration lifecycle fields."""
    from ui.screens.main_screen import MainScreen

    ms = MainScreen.__new__(MainScreen)
    ms._api_manager = None
    ms._ui_queue = queue.Queue()
    ms._input_queue = queue.Queue()
    ms._stop_event = threading.Event()
    ms._exploration_thread = _AliveThread()
    ms._pending_transition = None
    ms._awaiting_resume = False
    ms.chat_entries = []
    ms.chat_scroll = 0
    return ms


def test_b1_main_screen_sends_resume_only_when_paused() -> None:
    ms = _bare_main_screen()

    ms.start_exploration(api_manager=None)  # back from inventory
    assert ms._input_queue.empty()

    ms._awaiting_resume = True  # paused at a social/trade transition
    ms.start_exploration(api_manager=None, side_summary="Talked to the innkeeper.")
    assert ms._input_queue.get_nowait() == {"type": "resume", "summary": "Talked to the innkeeper."}
    assert ms._awaiting_resume is False


def test_b1_main_screen_fresh_start_restarts_thread(monkeypatch: pytest.MonkeyPatch) -> None:
    """New game / loaded save must not keep the old thread with a stale world."""
    import core.data as game_data
    import core.gameplay.exploration as exploration_module

    started = []
    monkeypatch.setattr(exploration_module, "run_exploration", lambda *a: started.append(a))
    monkeypatch.setattr(game_data, "game_state", _minimal_game_state_two_rooms())

    ms = _bare_main_screen()
    old_stop = ms._stop_event
    ms.chat_entries = ["old chat"]

    ms.start_exploration(api_manager="am", fresh=True)
    ms._exploration_thread.join(timeout=2)

    assert old_stop.is_set()
    assert ms.chat_entries == []
    assert len(started) == 1


# ── B2: rebuilding screens (resize / settings) keeps the session ────────────

@pytest.fixture
def pygame_display(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SDL_VIDEODRIVER", "dummy")
    pygame = pytest.importorskip("pygame")
    pygame.display.init()
    pygame.font.init()
    yield pygame
    pygame.display.quit()


def test_b2_init_screens_keeps_main_social_trade_state(pygame_display) -> None:
    from core.game import Game
    from core.settings.settings_manager import SettingsManager
    from ui.screens.main_screen import ChatEntry, ChatRole
    from ui.screens.social_screen import ChatEntry as SocialEntry, ChatRole as SocialRole

    game = Game.__new__(Game)
    game.screen = pygame_display.display.set_mode((1280, 720))
    game.settings_manager = SettingsManager()
    game.api_manager = MagicMock()
    game.current_screen_name = "main"
    game.screens = {}
    game._init_screens()

    main, social_screen, trade = game.screens["main"], game.screens["social"], game.screens["trade"]
    main_line = ChatEntry("chat line", ChatRole.DM)
    npc_line = SocialEntry("npc line", SocialRole.NPC)
    main.chat_entries.append(main_line)
    main._awaiting_resume = True
    main_thread_queue = main._input_queue
    social_screen._chat_entries.append(npc_line)
    social_screen._pending_summary = "summary"
    trade._trade.player_coins_offer = 42
    trade.set_return_to("social")

    game.screen = pygame_display.display.set_mode((1600, 900))
    game._init_screens()

    assert game.screens["main"] is not main
    assert game.screens["main"].chat_entries == [main_line]
    assert game.screens["main"]._input_queue is main_thread_queue
    assert game.screens["main"]._awaiting_resume is True
    assert game.screens["social"]._chat_entries == [npc_line]
    assert game.screens["social"].pop_summary() == "summary"
    assert game.screens["trade"]._trade.player_coins_offer == 42
    assert game.screens["trade"]._return_to == "social"


# ── B3: "combat" from a dialogue returns to exploration ─────────────────────

def test_b3_social_combat_returns_to_exploration(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(social, "_LOGFIRE_ENABLED", False)
    monkeypatch.setattr(social, "_generate_social_summary", lambda *a, **k: "A brawl almost started.")
    monkeypatch.setattr(social, "_build_greeting_agent", lambda *_a, **_k: FakeAgent([
        NpcGreeting(greeting_scene="Tense.", npc_first_words="What?"),
    ]))
    monkeypatch.setattr(social, "_build_options_agent", lambda *_a, **_k: FakeAgent([
        ResponseOptionList(options=[ResponseOption(id=1, text="Punch him.")]),
    ]))
    monkeypatch.setattr(social, "_build_resolution_agent", lambda *_a, **_k: FakeAgent([
        SocialResolutionOutput(npc_reply="You'll regret this!", action="combat"),
    ]))

    ui_q: queue.Queue = queue.Queue()
    in_q: queue.Queue = queue.Queue()
    stop = threading.Event()
    npc_id = "b3-npc"
    gs = _minimal_social_state(npc_id)
    thr = threading.Thread(
        target=lambda: social.run_social(MagicMock(model_name="stub"), gs, npc_id, ui_q, in_q, stop),
        daemon=True, name="social-b3",
    )
    thr.start()
    collect_until(ui_q, lambda m: m.get("type") == "options")
    in_q.put({"type": "input", "text": "1"})
    msgs = collect_until(ui_q, lambda m: m.get("type") == "transition")

    assert msgs[-1]["action"] == "exploration"
    assert msgs[-1]["summary"] == "A brawl almost started."
    join_thread_or_stop(thr, stop)


# ── B4: a side cannot pay more coins than it has ────────────────────────────

def _trade_setup(patched_game_state, player_coins: int, npc_coins: int):
    player = Player.create_random_character(name="P", race="human", class_type="fighter")
    player.inventory = [make_game_equipment(index="sword", name="Sword", gp=10)]
    player.coins = player_coins
    npc = NPC.create_random_character(name="N", race="human", class_type="rogue")
    npc.id = "npc-b4"
    npc.inventory = [make_game_equipment(index="gem", name="Gem", gp=10)]
    npc.coins = npc_coins
    patched_game_state.player = player
    patched_game_state.npcs[npc.id] = npc
    ts = TradeState()
    ts.reset(npc.id)
    return ts, player, npc


def test_b4_player_cannot_buy_with_money_they_do_not_have(patched_game_state) -> None:
    ts, player, npc = _trade_setup(patched_game_state, player_coins=5, npc_coins=0)
    gem = npc.inventory[0]
    ts.npc_barter.append(gem)
    ts.balance()  # player must pay the gem's full price

    assert ts.is_balanced()
    assert ts.funds_problem() == "player"
    assert not ts.can_execute()
    assert ts.execute_barter() is False
    assert gem in npc.inventory and gem not in player.inventory
    assert player.coins == 5


def test_b4_npc_cannot_pay_more_than_it_has(patched_game_state) -> None:
    ts, player, npc = _trade_setup(patched_game_state, player_coins=0, npc_coins=3)
    sword = player.inventory[0]
    ts.player_barter.append(sword)
    ts.balance()  # NPC must pay the sword's full price

    assert ts.funds_problem() == "npc"
    assert ts.execute_barter() is False
    assert sword in player.inventory
    assert npc.coins == 3 and player.coins == 0


def test_b4_affordable_trade_still_executes(patched_game_state) -> None:
    ts, player, npc = _trade_setup(patched_game_state, player_coins=10_000, npc_coins=0)
    gem = npc.inventory[0]
    ts.npc_barter.append(gem)
    ts.balance()
    price = ts.player_coins_offer

    assert ts.can_execute()
    assert ts.execute_barter() is True
    assert gem in player.inventory
    assert player.coins == 10_000 - price
    assert npc.coins == price


# ════════════════════════════ P1 (B5–B13) ════════════════════════════════════

# ── B5: no debug XP on new characters ───────────────────────────────────────

def _fighter_build():
    from core.builders.character_builder import CharacterBuild
    from core.database.json_database import JsonDatabase

    return CharacterBuild(
        name="B5", race="human", class_type="fighter",
        class_data=JsonDatabase().get("/classes/fighter.json"),
        alignment="neutral",
        abilities={"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8},
        points_remaining=0,
    )


def test_b5_new_character_starts_with_zero_xp(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("DND_DEV_START_XP", raising=False)
    assert _fighter_build().create_character().xp == 0


def test_b5_dev_start_xp_override(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DND_DEV_START_XP", "900")
    assert _fighter_build().create_character().xp == 900


# ── B6: HP per level is the fixed average, not the maximum ──────────────────

def test_b6_hp_gain_is_average_plus_con() -> None:
    from core.builders.level_up_builder import hp_gain_per_level

    assert hp_gain_per_level(10, 2) == 8   # d10: 6 + 2
    assert hp_gain_per_level(6, 0) == 4    # d6: 4
    assert hp_gain_per_level(12, 1) == 8   # d12: 7 + 1
    assert hp_gain_per_level(6, -5) == 1   # never below 1


def test_b6_level_up_adds_average_hp() -> None:
    from core.builders.level_up_builder import LevelUpBuild

    p = Player.create_random_character(name="B6", race="human", class_type="fighter")
    before = p.max_hit_points
    LevelUpBuild(new_level=2).apply_level_up(p)
    assert p.max_hit_points - before == max(1, 6 + p.ability_modifiers.con)


# ── B7: prepared casters get new slots without learning spells ──────────────

def test_b7_cleric_slots_update_without_new_spells() -> None:
    from core.builders.level_up_builder import LevelUpBuild
    from core.database.json_database import JsonDatabase

    from core.builders.character_builder import CharacterBuild

    p = CharacterBuild(
        name="B7", race="human", class_type="cleric",
        class_data=JsonDatabase().get("/classes/cleric.json"),
        alignment="neutral",
        abilities={"str": 10, "dex": 12, "con": 14, "int": 8, "wis": 15, "cha": 13},
        points_remaining=0,
    ).create_character()
    assert p.sc is not None
    table = JsonDatabase().get("/classes/cleric/levels/3.json")["spellcasting"]
    expected = [table.get(f"spell_slots_level_{lvl}", 0) for lvl in range(1, 10)]

    LevelUpBuild(new_level=3).apply_level_up(p)  # no new_cantrips / new_spells

    assert list(p.sc.spell_slots) == expected
    assert expected[1] > 0  # level 3 cleric has 2nd-level slots


# ── B8 / B9: transitions only to adjacent rooms and NPCs in the room ────────

def _run_one_resolution(monkeypatch, gs, resolution_output):
    monkeypatch.setattr(exp, "_LOGFIRE_ENABLED", False)
    monkeypatch.setattr(exp, "_generate_location_summary", lambda *a, **k: "")
    monkeypatch.setattr(exp, "_build_describe_agent",
                        lambda *_a: FakeAgent([SceneDescription(environment_description="A hall.")]))
    monkeypatch.setattr(exp, "_build_generate_actions_agent",
                        lambda *_a: FakeAgent([_actions(), _actions()]))
    monkeypatch.setattr(exp, "_build_resolution_agent", lambda *_a: FakeAgent([resolution_output]))

    ui_q: queue.Queue = queue.Queue()
    in_q: queue.Queue = queue.Queue()
    stop = threading.Event()
    thr = threading.Thread(
        target=lambda: exp.run_exploration(MagicMock(model_name="stub"), gs, ui_q, in_q, stop),
        daemon=True, name="exploration-p1",
    )
    thr.start()
    collect_until(ui_q, lambda m: m.get("type") == "actions")
    in_q.put({"type": "input", "text": "1"})
    msgs = collect_until(ui_q, lambda m: m.get("type") in ("actions", "transition", "error"))
    stop.set()
    join_thread_or_stop(thr, stop)
    return msgs


def test_b8_non_adjacent_room_keeps_player_in_place(monkeypatch: pytest.MonkeyPatch) -> None:
    from core.entities.location import Room

    gs = _minimal_game_state_two_rooms()
    gs.rooms["far"] = Room(name="Far", level=0, description="Far away.", id="far", location_id="loc1")
    msgs = _run_one_resolution(monkeypatch, gs, AgentResolutionOutput(
        narration="You walk off.", action="change_current_room",
        question_to_player=None, metadata=exp.ActionMetadata(room_id="far"),
    ))
    assert msgs[-1]["type"] == "actions"
    assert any(m.get("text") == exp.ROOM_UNREACHABLE_MARKER for m in msgs)
    assert gs.current_room_id == "r1"


def test_b8_room_change_without_metadata_does_not_crash(monkeypatch: pytest.MonkeyPatch) -> None:
    gs = _minimal_game_state_two_rooms()
    msgs = _run_one_resolution(monkeypatch, gs, AgentResolutionOutput(
        narration="You walk off.", action="change_current_room", question_to_player=None,
    ))
    assert msgs[-1]["type"] == "actions"
    assert gs.current_room_id == "r1"


@pytest.mark.parametrize("npc_id", [None, "ghost-npc"])
def test_b9_social_with_unknown_npc_stays_in_exploration(monkeypatch: pytest.MonkeyPatch, npc_id) -> None:
    gs = _minimal_game_state_two_rooms()
    msgs = _run_one_resolution(monkeypatch, gs, AgentResolutionOutput(
        narration="You approach someone.", action="social",
        question_to_player=None, metadata=exp.ActionMetadata(npc_id=npc_id),
    ))
    assert msgs[-1]["type"] == "actions"
    assert any(m.get("text") == exp.NPC_NOT_HERE_MARKER for m in msgs)


def test_b9_social_with_npc_in_room_transitions(monkeypatch: pytest.MonkeyPatch) -> None:
    gs = _minimal_game_state_two_rooms()
    msgs = _run_one_resolution(monkeypatch, gs, AgentResolutionOutput(
        narration="You approach the innkeeper.", action="social",
        question_to_player=None, metadata=exp.ActionMetadata(npc_id="npc1"),
    ))
    transition = msgs[-1]
    assert (transition["type"], transition["action"], transition["npc_id"]) == ("transition", "social", "npc1")
    # B26: the recent scene travels with the transition into the dialogue.
    assert "You approach the innkeeper." in transition["context"]


# ── B10: a new character gets a fresh world ─────────────────────────────────

def test_b10_new_character_resets_world(monkeypatch: pytest.MonkeyPatch) -> None:
    import core.data as game_data
    from core.game import Game

    game = Game.__new__(Game)
    game.screens = {"main": MagicMock()}
    game.current_screen_name = "character_creation"
    game.api_manager = MagicMock()
    game._reset_world()

    old_state = game_data.game_state
    old_state.locations[old_state.current_location_id].location_history_summary = "Old run."
    old_state.current_room_id = "somewhere-else"

    hero = Player.create_random_character(name="New hero", race="human", class_type="fighter")
    game._handle_screen_result(hero)

    gs = game_data.game_state
    assert gs is not old_state
    assert gs.player is hero
    assert gs.current_room_id == "tavern-room-001"
    assert gs.locations[gs.current_location_id].location_history_summary in ("", None)
    game.screens["main"].start_exploration.assert_called_once()
    assert game.screens["main"].start_exploration.call_args.kwargs["fresh"] is True


# ── B13: merchants buy at half price ────────────────────────────────────────

def test_b13_player_items_sell_for_half_price() -> None:
    sword = make_game_equipment(index="sword13", name="Sword", gp=10)
    ts = TradeState()
    ts.player_barter.append(sword)
    assert ts.player_barter_value() == 500   # 10 gp = 1000 cp, half
    ts.player_barter.clear()
    ts.npc_barter.append(sword)
    assert ts.npc_barter_value() == 1000     # buying is full price


# ════════════════════════════ P2 (B14–B19) ═══════════════════════════════════

# ── B14 / B15: dice — natural d20, DC 0, house rule, limits ─────────────────

class _ScriptedRng:
    """random.Random stand-in returning scripted randint values."""

    def __init__(self, values):
        self._values = list(values)

    def randint(self, _a, _b):
        return self._values.pop(0)


def _roll(values, *args, **kwargs):
    from core.tools.roll import RollDiceTool

    return RollDiceTool(rng=_ScriptedRng(values)).run(*args, **kwargs)


def test_b14_dc_zero_is_a_real_dc() -> None:
    assert _roll([1], "1d4", difficulty_class=0)["roll_success"] is True


def test_b14_natural_20_and_1_house_rule() -> None:
    nat20 = _roll([20], "1d20-5", difficulty_class=30)
    assert nat20["natural"] == 20 and nat20["roll_success"] is True
    nat1 = _roll([1], "1d20+30", difficulty_class=10)
    assert nat1["natural"] == 1 and nat1["roll_success"] is False


def test_b14_advantage_keeps_higher_d20_only() -> None:
    r = _roll([4, 17], "1d20+3", has_advantage=True, difficulty_class=15)
    assert r == {"roll_result": 20, "roll_success": True, "natural": 17, "rolls": [4, 17]}
    # Advantage does not apply to damage dice.
    dmg = _roll([3, 5], "2d6+1", has_advantage=True)
    assert dmg["roll_result"] == 9 and dmg["natural"] is None


@pytest.mark.parametrize("expr", [
    "99999999d99999", "21d6", "1d7", "1d20*2", "wisdom check", "", "1d20+100",
    "(2d4)*2+1", "1d20" + "+1" * 30,
])
def test_b15_rejects_unsafe_or_invalid_expressions(expr: str) -> None:
    from core.tools.roll import RollDiceTool

    result = RollDiceTool().run(expr, difficulty_class=10)
    assert "error" in result and "roll_result" not in result


def test_b15_accepts_plain_notation() -> None:
    r = _roll([2, 6, 3], "2d6+1d4-1")
    assert r["roll_result"] == 10 and r["rolls"] == [2, 6, 3]


# ── B16: cancelling a barter re-equips staged items ─────────────────────────

def _equipped_helm_setup(patched_game_state):
    from core.gameplay.trade import PANEL_PLAYER_EQUIP, PANEL_PLAYER_BARTER

    player = Player.create_random_character(name="P16", race="human", class_type="fighter")
    helm = make_game_equipment(index="helm16", name="Helm", gp=2)
    helm.equipped = True
    helm.equipped_slot = "head"
    player.inventory = [helm]
    npc = NPC.create_random_character(name="N16", race="human", class_type="rogue")
    npc.id = "npc-b16"
    npc.inventory = []
    npc.coins = 1000
    patched_game_state.player = player
    patched_game_state.npcs[npc.id] = npc
    ts = TradeState()
    ts.reset(npc.id)
    ts.handle_drop(helm, PANEL_PLAYER_EQUIP, PANEL_PLAYER_BARTER)
    assert helm.equipped is False
    return ts, helm


def test_b16_cancel_restores_equipment(patched_game_state) -> None:
    ts, helm = _equipped_helm_setup(patched_game_state)
    ts.cancel()
    assert helm.equipped is True and helm.equipped_slot == "head"
    assert ts.player_barter == []


def test_b16_withdrawing_item_restores_equipment(patched_game_state) -> None:
    from core.gameplay.trade import PANEL_PLAYER_BARTER, PANEL_PLAYER_INV

    ts, helm = _equipped_helm_setup(patched_game_state)
    ts.handle_drop(helm, PANEL_PLAYER_BARTER, PANEL_PLAYER_INV)
    assert helm.equipped is True and helm.equipped_slot == "head"


def test_b16_traded_item_stays_unequipped(patched_game_state) -> None:
    ts, helm = _equipped_helm_setup(patched_game_state)
    ts.balance()
    assert ts.execute_barter() is True
    ts.cancel()  # nothing left to restore
    assert helm.equipped is False


# ── B17: save slots are bounded and written atomically ──────────────────────

def test_b17_save_uses_first_free_slot_and_bounds(tmp_path, monkeypatch, patched_game_state) -> None:
    from core.data import game_state_base as gsb

    monkeypatch.setattr(gsb, "SAVE_DIR", str(tmp_path))
    patched_game_state.player = Player.create_random_character(name="S", race="human", class_type="fighter")

    for i in gsb.SAVE_SLOTS:
        if i != 3:
            (tmp_path / f"save_{i}.pkl").write_bytes(b"x")
    assert patched_game_state.save() == 3
    assert not list(tmp_path.glob("*.tmp")), "temp file left behind"

    with pytest.raises(ValueError):
        patched_game_state.save()  # all ten slots taken now
    with pytest.raises(ValueError):
        patched_game_state.save(11)


# ── B18: a failing agent call does not kill the session ─────────────────────

class _FailingAgent:
    model = "stub-model"

    def __init__(self):
        self.calls = 0

    def run_sync(self, *_a, **_k):
        self.calls += 1
        raise RuntimeError("provider down")


def test_b18_describe_and_actions_failures_fall_back(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(exp, "_LOGFIRE_ENABLED", False)
    describe, generate = _FailingAgent(), _FailingAgent()
    monkeypatch.setattr(exp, "_build_describe_agent", lambda *_a: describe)
    monkeypatch.setattr(exp, "_build_generate_actions_agent", lambda *_a: generate)
    monkeypatch.setattr(exp, "_build_resolution_agent", lambda *_a: FakeAgent([
        AgentResolutionOutput(narration="Ты оглядываешься.", action="exploration", question_to_player=None),
    ]))

    ui_q: queue.Queue = queue.Queue()
    in_q: queue.Queue = queue.Queue()
    stop = threading.Event()
    gs = _minimal_game_state_two_rooms()
    thr = threading.Thread(
        target=lambda: exp.run_exploration(MagicMock(model_name="stub"), gs, ui_q, in_q, stop),
        daemon=True, name="exploration-b18",
    )
    thr.start()
    msgs = collect_until(ui_q, lambda m: m.get("type") == "actions")

    scene = next(m for m in msgs if m.get("type") == "scene")
    assert scene["text"] == "A hall."  # static room description
    assert sum(m.get("type") == "error" for m in msgs) == 2
    assert msgs[-1]["actions"] == []
    assert describe.calls == exp.AGENT_ATTEMPTS and generate.calls == exp.AGENT_ATTEMPTS

    in_q.put({"type": "input", "text": "Осматриваюсь"})  # free input still works
    msgs = collect_until(ui_q, lambda m: m.get("type") == "narration")
    assert msgs[-1]["text"] == "Ты оглядываешься."
    stop.set()
    join_thread_or_stop(thr, stop)


# ── B19: input is sent only when the DM waits for it ────────────────────────

def test_b19_main_screen_sends_only_when_awaiting_input() -> None:
    ms = _bare_main_screen()
    ms._awaiting_input = False
    ms.input_buffer = "Иду к стойке"
    ms._add_entry = lambda *_a: None

    ms._on_send()  # DM is still thinking
    assert ms._input_queue.empty()
    assert ms.input_buffer == "Иду к стойке"  # kept for later

    ms._awaiting_input = True
    ms._on_send()
    assert ms._input_queue.get_nowait() == {"type": "input", "text": "Иду к стойке"}
    assert ms.input_buffer == "" and ms._awaiting_input is False


def test_quick_buttons_send_player_actions() -> None:
    from ui.screens.main_screen import MainScreen

    ms = _bare_main_screen()
    ms._awaiting_input = True
    ms._add_entry = lambda *_a: None
    assert ms._send_text(MainScreen.QUICK_ACTIONS[1]) is True
    assert ms._input_queue.get_nowait()["text"] == MainScreen.QUICK_ACTIONS[1]
