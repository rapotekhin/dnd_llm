"""Trade barter logic + inventory moves (no pygame)."""

from __future__ import annotations

from core.entities.npc import NPC
from core.entities.player import Player
from core.gameplay.trade import (
    PANEL_NPC_BARTER,
    PANEL_NPC_INV,
    PANEL_PLAYER_BARTER,
    PANEL_PLAYER_EQUIP,
    PANEL_PLAYER_INV,
    TradeState,
)

from helpers import make_game_equipment


def test_trade_balance_matches_item_difference(patched_game_state) -> None:
    patched_game_state.player = Player.create_random_character(
        name="Trader", race="human", class_type="fighter"
    )
    patched_game_state.player.inventory = []
    npc = NPC.create_random_character(name="Merchant", race="human", class_type="rogue")
    npc.id = "npc-trade-balance"
    patched_game_state.npcs[npc.id] = npc

    cheap = make_game_equipment(index="cheap", name="Cheap", gp=1)
    pricey = make_game_equipment(index="pricey", name="Pricey", gp=5)

    ts = TradeState()
    ts.reset(npc.id)
    ts.player_barter.append(pricey)
    patched_game_state.player.inventory.append(pricey)
    ts.npc_barter.append(cheap)
    npc.inventory = [cheap]

    ts.balance()
    assert ts.player_coins_offer == 0
    assert ts.npc_coins_offer == 4 * 100


def test_trade_balance_player_compensates_when_npc_offers_more_value(patched_game_state) -> None:
    patched_game_state.player = Player.create_random_character(name="T2", race="human", class_type="fighter")
    patched_game_state.player.inventory = []
    npc = NPC.create_random_character(name="M2", race="human", class_type="rogue")
    npc.id = "npc-trade-balance-2"
    patched_game_state.npcs[npc.id] = npc

    cheap = make_game_equipment(index="cheap2", name="Cheap", gp=1)
    pricey = make_game_equipment(index="pricey2", name="Pricey", gp=5)

    ts = TradeState()
    ts.reset(npc.id)
    ts.player_barter.append(cheap)
    patched_game_state.player.inventory.append(cheap)
    ts.npc_barter.append(pricey)
    npc.inventory = [pricey]

    ts.balance()
    assert ts.npc_coins_offer == 0
    assert ts.player_coins_offer == 4 * 100


def test_trade_execute_swaps_items_and_coins(patched_game_state) -> None:
    player = Player.create_random_character(name="P", race="human", class_type="fighter")
    player.inventory = []
    player.coins = 500

    npc = NPC.create_random_character(name="N", race="human", class_type="rogue")
    npc.id = "npc-trade-exec"
    npc.inventory = []
    npc.coins = 200

    a = make_game_equipment(index="pa", name="PA", gp=2)
    b = make_game_equipment(index="nb", name="NB", gp=3)

    player.inventory.append(a)
    npc.inventory.append(b)

    patched_game_state.player = player
    patched_game_state.npcs[npc.id] = npc

    ts = TradeState()
    ts.reset(npc.id)
    ts.player_barter.append(a)
    ts.npc_barter.append(b)
    ts.player_coins_offer = 100
    ts.npc_coins_offer = 50

    ts.execute_barter()

    assert a in npc.inventory
    assert b in player.inventory
    assert player.coins == 500 - 100 + 50
    assert npc.coins == 200 + 100 - 50
    assert ts.player_barter == []
    assert ts.npc_barter == []


def test_trade_is_balanced_requires_items() -> None:
    ts = TradeState()
    ts.player_coins_offer = 50
    ts.npc_coins_offer = 50
    assert ts.is_balanced() is False

    a = make_game_equipment(index="a", name="A", gp=1)
    b = make_game_equipment(index="b", name="B", gp=1)
    ts.player_barter.append(a)
    ts.npc_barter.append(b)
    ts.player_coins_offer = 0
    ts.npc_coins_offer = 0
    assert ts.is_balanced() is True
    assert ts.player_barter_value() == ts.npc_barter_value()


def test_is_balanced_false_when_only_one_side_offers_items() -> None:
    ts = TradeState()
    a = make_game_equipment(index="solo", name="Solo", gp=1)
    ts.player_barter.append(a)
    ts.npc_barter.clear()
    ts.player_coins_offer = 0
    ts.npc_coins_offer = 0
    assert ts.is_balanced() is False


def test_execute_barter_clears_equipped_flags(patched_game_state) -> None:
    player = Player.create_random_character(name="PE", race="human", class_type="fighter")
    a = make_game_equipment(index="eq-sw", name="Sword", gp=3)
    a.equipped = True
    a.equipped_right_hand = True
    player.inventory = [a]

    npc = NPC.create_random_character(name="NE", race="human", class_type="rogue")
    npc.id = "npc-equip-reset"
    b = make_game_equipment(index="eq-bot", name="Boot", gp=1)
    npc.inventory = [b]

    patched_game_state.player = player
    patched_game_state.npcs[npc.id] = npc

    ts = TradeState()
    ts.reset(npc.id)
    ts.player_barter.append(a)
    ts.npc_barter.append(b)

    ts.execute_barter()

    assert a.equipped is False
    assert a.equipped_right_hand is False
    assert a.equipped_slot is None


def test_execute_barter_player_without_npc_record_removes_from_inventory_only(patched_game_state) -> None:
    """No NPC in game_state: ``TradeState`` still strips offered gear from the player."""
    player = Player.create_random_character(name="Lonely", race="human", class_type="fighter")
    item = make_game_equipment(index="orphan", name="Orphan", gp=1)
    player.inventory = [item]
    patched_game_state.player = player
    patched_game_state.npcs.clear()

    ts = TradeState()
    ts.reset("missing-npc-id")
    ts.player_barter.append(item)

    ts.execute_barter()

    assert item not in player.inventory


def test_handle_drop_stages_barter_then_returns_to_inv(patched_game_state) -> None:
    player = Player.create_random_character(name="P", race="human", class_type="fighter")
    item = make_game_equipment(index="slot", name="Slot", gp=1)
    player.inventory = [item]

    npc = NPC.create_random_character(name="N", race="human", class_type="rogue")
    npc.id = "npc-drop"
    npc.inventory = []

    patched_game_state.player = player
    patched_game_state.npcs[npc.id] = npc

    ts = TradeState()
    ts.reset(npc.id)

    ts.handle_drop(item, PANEL_PLAYER_INV, PANEL_PLAYER_BARTER)
    assert item in ts.player_barter

    ts.handle_drop(item, PANEL_PLAYER_BARTER, PANEL_PLAYER_INV)
    assert item not in ts.player_barter


def test_handle_drop_from_equip_clears_slots_for_barter(patched_game_state) -> None:
    player = Player.create_random_character(name="PEq", race="human", class_type="fighter")
    item = make_game_equipment(index="helm", name="Helm", gp=2)
    item.equipped = True
    item.equipped_slot = "head"
    player.inventory = [item]

    npc = NPC.create_random_character(name="N3", race="human", class_type="rogue")
    npc.id = "npc-drop-eq"
    npc.inventory = []
    patched_game_state.player = player
    patched_game_state.npcs[npc.id] = npc

    ts = TradeState()
    ts.reset(npc.id)
    ts.handle_drop(item, PANEL_PLAYER_EQUIP, PANEL_PLAYER_BARTER)
    assert item in ts.player_barter
    assert item.equipped is False
    assert item.equipped_slot is None


def test_handle_drop_npc_side(patched_game_state) -> None:
    player = Player.create_random_character(name="P", race="human", class_type="fighter")
    player.inventory = []

    npc = NPC.create_random_character(name="N", race="human", class_type="rogue")
    npc.id = "npc-drop2"
    loot = make_game_equipment(index="loot", name="Loot", gp=2)
    npc.inventory = [loot]

    patched_game_state.player = player
    patched_game_state.npcs[npc.id] = npc

    ts = TradeState()
    ts.reset(npc.id)

    ts.handle_drop(loot, PANEL_NPC_INV, PANEL_NPC_BARTER)
    assert loot in ts.npc_barter
    ts.handle_drop(loot, PANEL_NPC_BARTER, PANEL_NPC_INV)
    assert loot not in ts.npc_barter
