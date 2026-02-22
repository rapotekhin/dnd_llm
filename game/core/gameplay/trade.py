"""
Barter / trade business logic – fully decoupled from pygame.

TradeState holds every mutable barter variable and exposes methods for:
  - querying player / NPC inventories and equipped slots
  - computing and comparing barter values
  - auto-balancing coin offers
  - executing the confirmed trade
  - routing drag-drop moves between inventory panels

Panel-name constants are shared with the UI so both sides agree on
the string labels used in handle_drop().
"""
from __future__ import annotations

from typing import List, Optional, TYPE_CHECKING

from core import data as game_data
from core.entities.base import ID
from core.entities.equipment import GameEquipment

if TYPE_CHECKING:
    from core.entities.npc import NPC
    from core.entities.player import Player

# ── Panel label constants ───────────────────────────────────────────────────
PANEL_EQUIP         = "equip"
PANEL_PLAYER_INV    = "player_inv"
PANEL_PLAYER_EQUIP  = "player_equip"
PANEL_PLAYER_BARTER = "player_barter"
PANEL_NPC_INV       = "npc_inv"
PANEL_NPC_BARTER    = "npc_barter"


class TradeState:
    """
    All non-UI state and logic for a single barter session.

    Instantiate once (e.g. on TradeScreen.__init__) and call
    reset(npc_id) each time the screen is opened for a new NPC.
    """

    # ------------------------------------------------------------------
    # INIT / RESET
    # ------------------------------------------------------------------

    def __init__(self) -> None:
        self.npc_id: Optional[ID] = None

        # Items staged for exchange
        self.player_barter: List[GameEquipment] = []
        self.npc_barter:    List[GameEquipment] = []

        # Coin offers
        self.player_coins_offer: int = 0
        self.npc_coins_offer:    int = 0

        # Raw text buffers for coin input fields (UI passes these back in)
        self.coin_buf_player: str = ""
        self.coin_buf_npc:    str = ""

        # Which coin field is currently focused ("player" | "npc" | "")
        self.coin_active: str = ""

    def reset(self, npc_id: ID) -> None:
        """Start a fresh session with the given NPC."""
        self.npc_id = npc_id
        self.player_barter.clear()
        self.npc_barter.clear()
        self.player_coins_offer = 0
        self.npc_coins_offer    = 0
        self.coin_buf_player    = ""
        self.coin_buf_npc       = ""
        self.coin_active        = ""

    # ------------------------------------------------------------------
    # GAME-STATE ACCESSORS
    # ------------------------------------------------------------------

    def get_player(self) -> Optional["Player"]:
        gs = game_data.game_state
        return gs.player if gs else None

    def get_npc(self) -> Optional["NPC"]:
        gs = game_data.game_state
        if not gs or not gs.npcs or self.npc_id is None:
            return None
        return gs.npcs.get(self.npc_id) or gs.npcs.get(str(self.npc_id))

    def item_in_slot(self, slot_key: str) -> Optional[GameEquipment]:
        """Return the player's item occupying *slot_key*, or None."""
        player = self.get_player()
        if not player or not getattr(player, "inventory", None):
            return None
        for it in player.inventory:
            if it is None or not isinstance(it, GameEquipment):
                continue
            if slot_key == "left_hand"  and it.equipped_left_hand:
                return it
            if slot_key == "right_hand" and it.equipped_right_hand:
                return it
            if slot_key not in ("left_hand", "right_hand") and it.equipped_slot == slot_key:
                return it
        return None

    def player_inv_items(self) -> List[GameEquipment]:
        player = self.get_player()
        if not player or not getattr(player, "inventory", None):
            return []
        return [it for it in player.inventory
                if it is not None and isinstance(it, GameEquipment)]

    def npc_inv_items(self) -> List[GameEquipment]:
        npc = self.get_npc()
        if not npc or not getattr(npc, "inventory", None):
            return []
        return [it for it in npc.inventory
                if it is not None and isinstance(it, GameEquipment)]

    # ------------------------------------------------------------------
    # BARTER VALUE CALCULATIONS
    # ------------------------------------------------------------------

    def player_barter_value(self) -> int:
        return sum((it.price or 0) for it in self.player_barter) + self.player_coins_offer

    def npc_barter_value(self) -> int:
        return sum((it.price or 0) for it in self.npc_barter) + self.npc_coins_offer

    def is_balanced(self) -> bool:
        """True when at least one item is offered and both sides' totals match."""
        has_items = bool(self.player_barter) or bool(self.npc_barter)
        return has_items and self.player_barter_value() == self.npc_barter_value()

    # ------------------------------------------------------------------
    # BARTER OPERATIONS
    # ------------------------------------------------------------------

    def balance(self) -> None:
        """Auto-fill coin offers so both sides' totals become equal."""
        p_items = sum((it.price or 0) for it in self.player_barter)
        n_items = sum((it.price or 0) for it in self.npc_barter)
        diff = p_items - n_items
        if diff > 0:
            # player offers more goods → NPC compensates with coins
            self.npc_coins_offer    = diff
            self.player_coins_offer = 0
        elif diff < 0:
            # NPC offers more goods → player compensates with coins
            self.player_coins_offer = -diff
            self.npc_coins_offer    = 0
        else:
            self.player_coins_offer = 0
            self.npc_coins_offer    = 0
        self.coin_buf_player = str(self.player_coins_offer) if self.player_coins_offer else ""
        self.coin_buf_npc    = str(self.npc_coins_offer)    if self.npc_coins_offer    else ""

    def execute_barter(self) -> None:
        """Commit the trade: swap items and transfer coins between player and NPC."""
        player = self.get_player()
        npc    = self.get_npc()
        if not player:
            return

        player_inv = getattr(player, "inventory", None)
        npc_inv    = getattr(npc,    "inventory", None) if npc else None

        # Player's offered items → NPC
        for item in list(self.player_barter):
            if player_inv:
                self.inv_remove(player_inv, item)
            item.equipped            = False
            item.equipped_left_hand  = False
            item.equipped_right_hand = False
            item.equipped_slot       = None
            if npc_inv is not None:
                npc_inv.append(item)

        # NPC's offered items → player
        for item in list(self.npc_barter):
            if npc_inv is not None:
                self.inv_remove(npc_inv, item)
            if player_inv is not None:
                player_inv.append(item)

        # Coin transfer
        player.coins = (getattr(player, "coins", 0) or 0) \
                       - self.player_coins_offer \
                       + self.npc_coins_offer
        if npc is not None:
            npc.coins = (getattr(npc, "coins", 0) or 0) \
                        + self.player_coins_offer \
                        - self.npc_coins_offer

        self.player_barter.clear()
        self.npc_barter.clear()
        self.player_coins_offer = 0
        self.npc_coins_offer    = 0
        self.coin_buf_player    = ""
        self.coin_buf_npc       = ""

    def handle_drop(self, item: GameEquipment, source: str, target: str) -> None:
        """
        Route a drag-drop move given string panel labels.

        source / target must be one of the PANEL_* constants defined above.
        """
        if target == PANEL_PLAYER_BARTER:
            if source in (PANEL_PLAYER_INV, PANEL_PLAYER_EQUIP) \
                    and not self.barter_contains(self.player_barter, item):
                if source == PANEL_PLAYER_EQUIP:
                    item.equipped            = False
                    item.equipped_left_hand  = False
                    item.equipped_right_hand = False
                    item.equipped_slot       = None
                self.player_barter.append(item)

        elif target in (PANEL_PLAYER_INV, PANEL_EQUIP):
            if source == PANEL_PLAYER_BARTER \
                    and self.barter_contains(self.player_barter, item):
                self.barter_remove(self.player_barter, item)

        elif target == PANEL_NPC_BARTER:
            if source == PANEL_NPC_INV \
                    and not self.barter_contains(self.npc_barter, item):
                self.npc_barter.append(item)

        elif target == PANEL_NPC_INV:
            if source == PANEL_NPC_BARTER \
                    and self.barter_contains(self.npc_barter, item):
                self.barter_remove(self.npc_barter, item)

    # ------------------------------------------------------------------
    # IDENTITY HELPERS
    # (use `is` so multiple copies of the same item type are treated separately)
    # ------------------------------------------------------------------

    @staticmethod
    def barter_contains(lst: List[GameEquipment], item: GameEquipment) -> bool:
        return any(it is item for it in lst)

    @staticmethod
    def barter_remove(lst: List[GameEquipment], item: GameEquipment) -> None:
        for i, it in enumerate(lst):
            if it is item:
                del lst[i]
                return

    @staticmethod
    def inv_remove(inv: list, item: GameEquipment) -> None:
        for i, it in enumerate(inv):
            if it is item:
                del inv[i]
                return
