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
