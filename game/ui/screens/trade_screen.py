"""
Trade screen - BG3-style barter between player and NPC.

Layout (left → right):
  [Equipment slots] [Player inventory] [Player offer | NPC offer] [NPC inventory]

Top strip: portraits + name/coins row + barter value indicators.
Bottom strip: coin inputs + Balance button + Barter / Leave buttons.

Drag-and-drop rules:
  player_inv / player_equip  →  player barter list  (allowed)
  npc_inv                    →  npc barter list      (allowed)
  player_barter              →  player_inv/equip     (remove from barter)
  npc_barter                 →  npc_inv              (remove from barter)
  Any cross-side drag        →  blocked
"""

from __future__ import annotations

import os
import pygame
from typing import List, Optional, Dict, Tuple, Set, TYPE_CHECKING

from .base_screen import BaseScreen
from ..colors import *
from ..components import Button
from core import data as game_data
from core.entities.base import ID
from core.entities.equipment import GameEquipment
from localization import loc

if TYPE_CHECKING:
    from core.entities.npc import NPC

SB_W = 10
SB_PAD = 3

SLOTS = [
    ("head",       "inv_head",       []),
    ("body",       "inv_body",       ["armor"]),
    ("hands",      "inv_hands",      []),
    ("feet",       "inv_feet",       []),
    ("cloak",      "inv_cloak",      []),
    ("amulet",     "inv_amulet",     ["amulet"]),
    ("ring_1",     "inv_ring_1",     ["ring"]),
    ("ring_2",     "inv_ring_2",     ["ring"]),
    ("left_hand",  "inv_left_hand",  ["weapon", "armor"]),
    ("right_hand", "inv_right_hand", ["weapon"]),
]

# Panels that belong to each "side" for drop-zone highlighting
_PLAYER_PANELS = {"equip", "player_inv", "player_barter"}
_NPC_PANELS    = {"npc_inv", "npc_barter"}


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


def _slot_label(loc_key: str) -> str:
    try:
        return loc[loc_key]
    except Exception:
        return loc_key.replace("inv_", "").replace("_", " ").capitalize()


class TradeScreen(BaseScreen):
    """
    Barter trade screen.
    Call set_npc(npc_id) before switching to this screen.
    """

    # ------------------------------------------------------------------
    # INIT
    # ------------------------------------------------------------------

    def __init__(self, screen: pygame.Surface):
        super().__init__(screen)
        self._npc_id: Optional[ID] = None
        self._portrait_cache: dict = {}

        # ---- Barter state ----
        self._player_barter: List[GameEquipment] = []
        self._npc_barter:    List[GameEquipment] = []
        self._player_coins_offer: int = 0
        self._npc_coins_offer:    int = 0
        self._coin_buf_player: str = ""
        self._coin_buf_npc:    str = ""
        self._coin_active: str = ""   # "player" | "npc" | ""

        # ---- Scroll ----
        self._player_inv_scroll:    int = 0
        self._npc_inv_scroll:       int = 0
        self._player_barter_scroll: int = 0
        self._npc_barter_scroll:    int = 0

        # ---- Drag-and-drop ----
        self._drag_item:         Optional[GameEquipment] = None
        self._drag_source:       str = ""
        self._drag_pos:          Tuple[int, int] = (0, 0)
        self._drag_start_pos:    Tuple[int, int] = (0, 0)
        self._pending_drag_item: Optional[GameEquipment] = None
        self._drag_threshold:    int = 6

        # ---- Layout rects (built in _build_layout) ----
        self._slot_rects: Dict[str, pygame.Rect] = {}

        self._equip_panel         = pygame.Rect(0, 0, 0, 0)
        self._player_inv_panel    = pygame.Rect(0, 0, 0, 0)
        self._player_inv_rect     = pygame.Rect(0, 0, 0, 0)
        self._player_barter_panel = pygame.Rect(0, 0, 0, 0)
        self._player_barter_rect  = pygame.Rect(0, 0, 0, 0)
        self._npc_barter_panel    = pygame.Rect(0, 0, 0, 0)
        self._npc_barter_rect     = pygame.Rect(0, 0, 0, 0)
        self._npc_inv_panel       = pygame.Rect(0, 0, 0, 0)
        self._npc_inv_rect        = pygame.Rect(0, 0, 0, 0)

        self._player_portrait_rect    = pygame.Rect(0, 0, 0, 0)
        self._npc_portrait_rect       = pygame.Rect(0, 0, 0, 0)
        self._player_info_rect        = pygame.Rect(0, 0, 0, 0)
        self._npc_info_rect           = pygame.Rect(0, 0, 0, 0)
        self._barter_val_player_rect  = pygame.Rect(0, 0, 0, 0)
        self._barter_val_npc_rect     = pygame.Rect(0, 0, 0, 0)

        self._player_coin_input_rect  = pygame.Rect(0, 0, 0, 0)
        self._npc_coin_input_rect     = pygame.Rect(0, 0, 0, 0)

        self._balance_btn: Optional[Button] = None
        self._barter_btn:  Optional[Button] = None
        self._leave_btn:   Optional[Button] = None

        self._build_layout()

    # ------------------------------------------------------------------
    # PUBLIC API
    # ------------------------------------------------------------------

    def set_npc(self, npc_id: ID) -> None:
        """Initialise screen for a given NPC and reset barter state."""
        self._npc_id = npc_id
        self._player_barter.clear()
        self._npc_barter.clear()
        self._player_coins_offer = 0
        self._npc_coins_offer    = 0
        self._coin_buf_player    = ""
        self._coin_buf_npc       = ""
        self._player_inv_scroll  = 0
        self._npc_inv_scroll     = 0
        self._player_barter_scroll = 0
        self._npc_barter_scroll    = 0

    # ------------------------------------------------------------------
    # LAYOUT
    # ------------------------------------------------------------------

    def _build_layout(self) -> None:
        s = self._scale
        w, h = self._w, self._h

        self.font       = pygame.font.Font(None, _sc(24, s))
        self.small_font = pygame.font.Font(None, _sc(20, s))
        self.tiny_font  = pygame.font.Font(None, _sc(17, s))

        m   = _sc(10, s)
        gap = _sc(8, s)

        # ---- Row heights ----
        icon_h   = _sc(60, s)
        info_h   = _sc(26, s)
        top_h    = icon_h + _sc(4, s) + info_h

        btn_h    = _sc(38, s)
        coin_h   = _sc(34, s)
        # bottom: coin inputs + balance btn + barter/leave row
        btm_h    = coin_h + _sc(6, s) + btn_h + _sc(6, s) + btn_h + _sc(4, s)

        content_top    = m + top_h + _sc(6, s)
        content_bottom = h - m - btm_h
        content_h      = max(40, content_bottom - content_top)

        # ---- Column widths ----
        eq_w     = max(90,  int(w * 0.14))
        inv_w    = max(110, int(w * 0.21))
        barter_w = max(70,  (w - 2 * m - eq_w - 2 * inv_w - 4 * gap) // 2)

        # ---- Column X positions ----
        eq_x      = m
        pl_inv_x  = eq_x     + eq_w     + gap
        brt_pl_x  = pl_inv_x + inv_w    + gap
        brt_npc_x = brt_pl_x + barter_w + gap
        npc_inv_x = brt_npc_x + barter_w + gap

        # ---- Top strip: portraits ----
        player_sec_w = eq_w + gap + inv_w
        icon_y = m
        self._player_portrait_rect = pygame.Rect(
            eq_x + (player_sec_w - icon_h) // 2, icon_y, icon_h, icon_h
        )
        self._npc_portrait_rect = pygame.Rect(
            npc_inv_x + (inv_w - icon_h) // 2, icon_y, icon_h, icon_h
        )

        # ---- Top strip: name/coins + barter value indicators ----
        info_y = icon_y + icon_h + _sc(4, s)
        self._player_info_rect       = pygame.Rect(eq_x,      info_y, player_sec_w, info_h)
        self._npc_info_rect          = pygame.Rect(npc_inv_x, info_y, inv_w,        info_h)
        self._barter_val_player_rect = pygame.Rect(brt_pl_x,  info_y, barter_w,     info_h)
        self._barter_val_npc_rect    = pygame.Rect(brt_npc_x, info_y, barter_w,     info_h)

        # ---- Main content panels ----
        title_h = _sc(18, s)
        list_pad = 4

        self._equip_panel = pygame.Rect(eq_x, content_top, eq_w, content_h)

        self._player_inv_panel = pygame.Rect(pl_inv_x, content_top, inv_w, content_h)
        self._player_inv_rect  = pygame.Rect(
            pl_inv_x + list_pad, content_top + title_h,
            inv_w - list_pad * 2 - SB_W - SB_PAD, content_h - title_h - list_pad
        )

        self._player_barter_panel = pygame.Rect(brt_pl_x, content_top, barter_w, content_h)
        self._player_barter_rect  = pygame.Rect(
            brt_pl_x + list_pad, content_top + title_h,
            barter_w - list_pad * 2 - SB_W - SB_PAD, content_h - title_h - list_pad
        )

        self._npc_barter_panel = pygame.Rect(brt_npc_x, content_top, barter_w, content_h)
        self._npc_barter_rect  = pygame.Rect(
            brt_npc_x + list_pad, content_top + title_h,
            barter_w - list_pad * 2 - SB_W - SB_PAD, content_h - title_h - list_pad
        )

        self._npc_inv_panel = pygame.Rect(npc_inv_x, content_top, inv_w, content_h)
        self._npc_inv_rect  = pygame.Rect(
            npc_inv_x + list_pad, content_top + title_h,
            inv_w - list_pad * 2 - SB_W - SB_PAD, content_h - title_h - list_pad
        )

        # ---- Bottom: coin inputs ----
        ci_y = content_bottom + _sc(6, s)
        self._player_coin_input_rect = pygame.Rect(brt_pl_x,  ci_y, barter_w, coin_h)
        self._npc_coin_input_rect    = pygame.Rect(brt_npc_x, ci_y, barter_w, coin_h)

        # ---- Bottom: buttons ----
        bal_y  = ci_y + coin_h + _sc(6, s)
        act_y  = bal_y + btn_h + _sc(6, s)

        barter_center_x = brt_pl_x + barter_w  # midpoint between the two barter columns
        barter_zone_w   = barter_w * 2 + gap

        bal_w = _sc(150, s)
        self._balance_btn = Button(
            barter_center_x - bal_w // 2, bal_y,
            bal_w, btn_h, "Уравновесить", self.small_font
        )

        act_barter_w = _sc(110, s)
        act_leave_w  = _sc(90, s)
        act_gap      = _sc(10, s)
        total_act_w  = act_barter_w + act_gap + act_leave_w
        act_x        = barter_center_x - total_act_w // 2

        self._barter_btn = Button(act_x,                        act_y, act_barter_w, btn_h, "Бартер", self.small_font)
        self._leave_btn  = Button(act_x + act_barter_w + act_gap, act_y, act_leave_w,  btn_h, "Уйти",   self.small_font)

        self._layout_equip_slots()

    def _layout_equip_slots(self) -> None:
        r  = self._equip_panel
        s  = self._scale
        pad    = _sc(5, s)
        slot_w = r.w - 2 * pad
        slot_h = _sc(26, s)
        row_h  = slot_h + _sc(3, s)
        title_h = _sc(18, s)
        y = r.y + pad + title_h
        for i, (key, _, _) in enumerate(SLOTS):
            self._slot_rects[key] = pygame.Rect(r.x + pad, y + i * row_h, slot_w, slot_h)

    # ------------------------------------------------------------------
    # DATA HELPERS
    # ------------------------------------------------------------------

    def _get_player(self):
        gs = game_data.game_state
        return gs.player if gs else None

    def _get_npc(self) -> Optional["NPC"]:
        gs = game_data.game_state
        if not gs or not gs.npcs or self._npc_id is None:
            return None
        return gs.npcs.get(self._npc_id) or gs.npcs.get(str(self._npc_id))

    def _item_in_slot(self, slot_key: str) -> Optional[GameEquipment]:
        player = self._get_player()
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

    def _player_inv_items(self) -> List[GameEquipment]:
        player = self._get_player()
        if not player or not getattr(player, "inventory", None):
            return []
        return [it for it in player.inventory if it is not None and isinstance(it, GameEquipment)]

    def _npc_inv_items(self) -> List[GameEquipment]:
        npc = self._get_npc()
        if not npc or not getattr(npc, "inventory", None):
            return []
        return [it for it in npc.inventory if it is not None and isinstance(it, GameEquipment)]

    def _player_barter_value(self) -> int:
        return sum((it.price or 0) for it in self._player_barter) + self._player_coins_offer

    def _npc_barter_value(self) -> int:
        return sum((it.price or 0) for it in self._npc_barter) + self._npc_coins_offer

    def _is_balanced(self) -> bool:
        """True when both sides have a non-zero equal value OR at least one item in a list."""
        pv = self._player_barter_value()
        nv = self._npc_barter_value()
        has_items = bool(self._player_barter) or bool(self._npc_barter)
        return has_items and pv == nv

    # ------------------------------------------------------------------
    # BARTER LOGIC
    # ------------------------------------------------------------------

    def _do_balance(self) -> None:
        """Auto-fill coin fields so total values become equal."""
        p_items = sum((it.price or 0) for it in self._player_barter)
        n_items = sum((it.price or 0) for it in self._npc_barter)
        diff = p_items - n_items
        if diff > 0:
            # player offers more goods → NPC compensates with coins
            self._npc_coins_offer    = diff
            self._player_coins_offer = 0
        elif diff < 0:
            # NPC offers more goods → player pays coins
            self._player_coins_offer = -diff
            self._npc_coins_offer    = 0
        else:
            self._player_coins_offer = 0
            self._npc_coins_offer    = 0
        self._coin_buf_player = str(self._player_coins_offer) if self._player_coins_offer else ""
        self._coin_buf_npc    = str(self._npc_coins_offer)    if self._npc_coins_offer    else ""

    def _do_barter(self) -> None:
        """Execute the trade: swap items and transfer coins."""
        player = self._get_player()
        npc    = self._get_npc()
        if not player:
            return

        player_inv = getattr(player, "inventory", None)
        npc_inv    = getattr(npc,    "inventory", None) if npc else None

        # Transfer player's offered items → NPC
        for item in list(self._player_barter):
            if player_inv:
                self._inv_remove(player_inv, item)
            item.equipped            = False
            item.equipped_left_hand  = False
            item.equipped_right_hand = False
            item.equipped_slot       = None
            if npc_inv is not None:
                npc_inv.append(item)

        # Transfer NPC's offered items → player
        for item in list(self._npc_barter):
            if npc_inv is not None:
                self._inv_remove(npc_inv, item)
            if player_inv is not None:
                player_inv.append(item)

        # Coin transfer
        player.coins = (getattr(player, "coins", 0) or 0) \
                       - self._player_coins_offer \
                       + self._npc_coins_offer
        if npc is not None:
            npc.coins = (getattr(npc, "coins", 0) or 0) \
                        + self._player_coins_offer \
                        - self._npc_coins_offer

        self._player_barter.clear()
        self._npc_barter.clear()
        self._player_coins_offer = 0
        self._npc_coins_offer    = 0
        self._coin_buf_player    = ""
        self._coin_buf_npc       = ""

    # ------------------------------------------------------------------
    # BARTER LIST IDENTITY HELPERS
    # ------------------------------------------------------------------

    @staticmethod
    def _barter_contains(lst: List[GameEquipment], item: GameEquipment) -> bool:
        """Check membership by object identity (not __eq__), so duplicates of the
        same item type can each be added independently."""
        return any(it is item for it in lst)

    @staticmethod
    def _barter_remove(lst: List[GameEquipment], item: GameEquipment) -> None:
        """Remove the first entry that *is* (identity) the given item."""
        for i, it in enumerate(lst):
            if it is item:
                del lst[i]
                return

    @staticmethod
    def _inv_remove(inv: list, item: GameEquipment) -> None:
        """Remove item from inventory by identity, not __eq__."""
        for i, it in enumerate(inv):
            if it is item:
                del inv[i]
                return

    # ------------------------------------------------------------------
    # DRAG-AND-DROP HELPERS
    # ------------------------------------------------------------------

    def _cancel_drag(self) -> None:
        self._drag_item         = None
        self._drag_source       = ""
        self._pending_drag_item = None
        self._drag_start_pos    = (0, 0)

    def _item_at_list(self, pos: Tuple[int, int], rect: pygame.Rect,
                      items: list, scroll: int) -> Optional[GameEquipment]:
        if not rect.collidepoint(pos):
            return None
        line_h = _sc(24, self._scale)
        for i, it in enumerate(items):
            ry = rect.y + i * line_h - scroll
            if ry <= pos[1] < ry + line_h:
                return it
        return None

    def _handle_drop(self, pos: Tuple[int, int]) -> None:
        item = self._drag_item
        src  = self._drag_source
        if not item:
            return

        # ── Drop onto player barter list ──────────────────────────────
        if self._player_barter_panel.collidepoint(pos):
            if src in ("player_inv", "player_equip") and not self._barter_contains(self._player_barter, item):
                if src == "player_equip":
                    item.equipped            = False
                    item.equipped_left_hand  = False
                    item.equipped_right_hand = False
                    item.equipped_slot       = None
                self._player_barter.append(item)
            return

        # ── Drop onto NPC barter list ─────────────────────────────────
        if self._npc_barter_panel.collidepoint(pos):
            if src == "npc_inv" and not self._barter_contains(self._npc_barter, item):
                self._npc_barter.append(item)
            return

        # ── Drop player barter item back to player area ───────────────
        if self._player_inv_panel.collidepoint(pos) or self._equip_panel.collidepoint(pos):
            if src == "player_barter" and self._barter_contains(self._player_barter, item):
                self._barter_remove(self._player_barter, item)
            return

        # ── Drop NPC barter item back to NPC inventory ────────────────
        if self._npc_inv_panel.collidepoint(pos):
            if src == "npc_barter" and self._barter_contains(self._npc_barter, item):
                self._barter_remove(self._npc_barter, item)
            return

    # ------------------------------------------------------------------
    # HANDLE EVENTS
    # ------------------------------------------------------------------

    def handle_event(self, event: pygame.event.Event):
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                if self._drag_item:
                    self._cancel_drag()
                    return None
                return "social"

            # Coin field keyboard input
            if self._coin_active == "player":
                if event.key == pygame.K_BACKSPACE:
                    self._coin_buf_player = self._coin_buf_player[:-1]
                elif event.unicode.isdigit() and len(self._coin_buf_player) < 9:
                    self._coin_buf_player += event.unicode
                self._player_coins_offer = int(self._coin_buf_player) if self._coin_buf_player else 0
                return None
            if self._coin_active == "npc":
                if event.key == pygame.K_BACKSPACE:
                    self._coin_buf_npc = self._coin_buf_npc[:-1]
                elif event.unicode.isdigit() and len(self._coin_buf_npc) < 9:
                    self._coin_buf_npc += event.unicode
                self._npc_coins_offer = int(self._coin_buf_npc) if self._coin_buf_npc else 0
                return None
            return None

        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            self._layout_equip_slots()

            # Coin input focus
            if self._player_coin_input_rect.collidepoint(pos):
                self._coin_active = "player"
                return None
            if self._npc_coin_input_rect.collidepoint(pos):
                self._coin_active = "npc"
                return None
            self._coin_active = ""

            # Buttons
            if self._leave_btn and self._leave_btn.is_clicked(pos):
                return "social"
            if self._balance_btn and self._balance_btn.is_clicked(pos):
                self._do_balance()
                return None
            if self._barter_btn and self._barter_btn.is_clicked(pos) and self._is_balanced():
                self._do_barter()
                return None

            # ── Start drag from player inventory ──────────────────────
            pl_items = self._player_inv_items()
            it = self._item_at_list(pos, self._player_inv_rect, pl_items, self._player_inv_scroll)
            if it:
                self._pending_drag_item = it
                self._drag_source       = "player_inv"
                self._drag_start_pos    = pos
                self._drag_item         = None
                return None

            # ── Start drag from NPC inventory ─────────────────────────
            npc_items = self._npc_inv_items()
            it = self._item_at_list(pos, self._npc_inv_rect, npc_items, self._npc_inv_scroll)
            if it:
                self._pending_drag_item = it
                self._drag_source       = "npc_inv"
                self._drag_start_pos    = pos
                self._drag_item         = None
                return None

            # ── Start drag from player barter list ────────────────────
            it = self._item_at_list(pos, self._player_barter_rect,
                                    self._player_barter, self._player_barter_scroll)
            if it:
                self._pending_drag_item = it
                self._drag_source       = "player_barter"
                self._drag_start_pos    = pos
                self._drag_item         = None
                return None

            # ── Start drag from NPC barter list ───────────────────────
            it = self._item_at_list(pos, self._npc_barter_rect,
                                    self._npc_barter, self._npc_barter_scroll)
            if it:
                self._pending_drag_item = it
                self._drag_source       = "npc_barter"
                self._drag_start_pos    = pos
                self._drag_item         = None
                return None

            # ── Start drag from equipment slot ────────────────────────
            for slot_key, rect in self._slot_rects.items():
                if rect.collidepoint(pos):
                    item = self._item_in_slot(slot_key)
                    if item:
                        self._pending_drag_item = item
                        self._drag_source       = "player_equip"
                        self._drag_start_pos    = pos
                        self._drag_item         = None
                    return None

            return None

        if event.type == pygame.MOUSEMOTION:
            if event.buttons[0] and self._drag_start_pos != (0, 0) and self._drag_item is None:
                dx = event.pos[0] - self._drag_start_pos[0]
                dy = event.pos[1] - self._drag_start_pos[1]
                if (dx * dx + dy * dy) >= self._drag_threshold ** 2:
                    if self._pending_drag_item is not None:
                        self._drag_item = self._pending_drag_item
            if self._drag_item:
                self._drag_pos = event.pos
            return None

        if event.type == pygame.MOUSEBUTTONUP and event.button == 1:
            if self._drag_item:
                self._handle_drop(event.pos)
            self._cancel_drag()
            return None

        if event.type == pygame.MOUSEWHEEL:
            mpos   = pygame.mouse.get_pos()
            s      = self._scale
            line_h = _sc(24, s)
            step   = line_h * 3

            def _clamp_scroll(cur: int, count: int, rect_h: int, dy: int) -> int:
                max_s = max(0, count * line_h - rect_h)
                return max(0, min(max_s, cur + (-step if dy > 0 else step)))

            if self._player_inv_rect.collidepoint(mpos):
                self._player_inv_scroll = _clamp_scroll(
                    self._player_inv_scroll, len(self._player_inv_items()),
                    self._player_inv_rect.height, event.y)
            elif self._npc_inv_rect.collidepoint(mpos):
                self._npc_inv_scroll = _clamp_scroll(
                    self._npc_inv_scroll, len(self._npc_inv_items()),
                    self._npc_inv_rect.height, event.y)
            elif self._player_barter_rect.collidepoint(mpos):
                self._player_barter_scroll = _clamp_scroll(
                    self._player_barter_scroll, len(self._player_barter),
                    self._player_barter_rect.height, event.y)
            elif self._npc_barter_rect.collidepoint(mpos):
                self._npc_barter_scroll = _clamp_scroll(
                    self._npc_barter_scroll, len(self._npc_barter),
                    self._npc_barter_rect.height, event.y)
            return None

        return None

    # ------------------------------------------------------------------
    # UPDATE
    # ------------------------------------------------------------------

    def update(self):
        pos = pygame.mouse.get_pos()
        if self._balance_btn:
            self._balance_btn.update(pos)
        if self._barter_btn:
            self._barter_btn.update(pos)
        if self._leave_btn:
            self._leave_btn.update(pos)

    # ------------------------------------------------------------------
    # DRAW HELPERS
    # ------------------------------------------------------------------

    def _load_portrait(self, path: str, size: Tuple[int, int]) -> Optional[pygame.Surface]:
        key = (path, size)
        if key in self._portrait_cache:
            return self._portrait_cache[key]
        if not path or not os.path.exists(path):
            alt = os.path.normpath(
                os.path.join(os.path.dirname(__file__), "..", "..", "..", path))
            if not os.path.exists(alt):
                self._portrait_cache[key] = None
                return None
            path = alt
        try:
            img = pygame.image.load(path).convert_alpha()
            img = pygame.transform.smoothscale(img, size)
            self._portrait_cache[key] = img
        except Exception:
            self._portrait_cache[key] = None
        return self._portrait_cache[key]

    def _draw_portrait(self, rect: pygame.Rect, img: Optional[pygame.Surface]) -> None:
        pygame.draw.rect(self.screen, DARK_GRAY, rect, border_radius=6)
        if img:
            self.screen.blit(img, rect.topleft)
        else:
            cx, cy = rect.centerx, rect.centery
            r = min(rect.w, rect.h) // 3
            pygame.draw.circle(self.screen, LIGHT_GRAY, (cx, cy - r // 3), r // 3, 2)
            pygame.draw.arc(self.screen, LIGHT_GRAY,
                            pygame.Rect(cx - r // 2, cy, r, r // 2), 0, 3.14159, 2)
        pygame.draw.rect(self.screen, GOLD, rect, width=2, border_radius=6)

    def _draw_item_list(self, panel: pygame.Rect, list_rect: pygame.Rect,
                        title: str, items: List[GameEquipment],
                        scroll: int, in_barter: Set[int]) -> None:
        """Inventory list with title; items in barter highlighted gold.
        in_barter is a set of id()s for identity-safe membership check."""
        s      = self._scale
        line_h = _sc(24, s)
        pygame.draw.rect(self.screen, MODAL_BG, panel, border_radius=6)
        pygame.draw.rect(self.screen, GOLD,     panel, width=1, border_radius=6)
        t = self.tiny_font.render(title, True, GOLD)
        self.screen.blit(t, (panel.x + 4, panel.y + 2))

        clip = self.screen.get_clip()
        self.screen.set_clip(list_rect)
        for i, it in enumerate(items):
            y = list_rect.y + i * line_h - scroll
            if y + line_h < list_rect.y or y > list_rect.bottom:
                continue
            offered = id(it) in in_barter
            bg  = (55, 44, 8) if offered else (DARK_GRAY if i % 2 == 0 else MODAL_BG)
            col = BRIGHT_GOLD if offered else WHITE
            pygame.draw.rect(self.screen, bg, (list_rect.x, y, list_rect.w, line_h))
            ns = self.tiny_font.render((it.name or it.index or "?")[:22], True, col)
            self.screen.blit(ns, (list_rect.x + 4, y + (line_h - ns.get_height()) // 2))
            ps = self.tiny_font.render(f"{it.price or 0}cp", True, LIGHT_GRAY)
            self.screen.blit(ps, (list_rect.right - ps.get_width() - 4,
                                  y + (line_h - ps.get_height()) // 2))
        self.screen.set_clip(clip)

    def _draw_barter_panel(self, panel: pygame.Rect, list_rect: pygame.Rect,
                           title: str, items: List[GameEquipment], scroll: int) -> None:
        """Barter offer list with slightly darker background."""
        s      = self._scale
        line_h = _sc(24, s)
        pygame.draw.rect(self.screen, (22, 20, 10), panel, border_radius=6)
        pygame.draw.rect(self.screen, GOLD,          panel, width=1, border_radius=6)
        t = self.tiny_font.render(title, True, BRIGHT_GOLD)
        self.screen.blit(t, (panel.x + 4, panel.y + 2))

        clip = self.screen.get_clip()
        self.screen.set_clip(list_rect)
        for i, it in enumerate(items):
            y = list_rect.y + i * line_h - scroll
            if y + line_h < list_rect.y or y > list_rect.bottom:
                continue
            bg = DARK_GRAY if i % 2 == 0 else (35, 35, 35)
            pygame.draw.rect(self.screen, bg, (list_rect.x, y, list_rect.w, line_h))
            ns = self.tiny_font.render((it.name or it.index or "?")[:20], True, WHITE)
            self.screen.blit(ns, (list_rect.x + 4, y + (line_h - ns.get_height()) // 2))
            ps = self.tiny_font.render(f"{it.price or 0}cp", True, LIGHT_GRAY)
            self.screen.blit(ps, (list_rect.right - ps.get_width() - 4,
                                  y + (line_h - ps.get_height()) // 2))
        self.screen.set_clip(clip)

    def _draw_equip_panel(self) -> None:
        s = self._scale
        pl_barter_ids = {id(it) for it in self._player_barter}
        pygame.draw.rect(self.screen, MODAL_BG, self._equip_panel, border_radius=6)
        pygame.draw.rect(self.screen, GOLD,     self._equip_panel, width=1, border_radius=6)
        t = self.tiny_font.render("Экипировка", True, GOLD)
        self.screen.blit(t, (self._equip_panel.x + 4, self._equip_panel.y + 2))

        for slot_key, loc_key, _ in SLOTS:
            r = self._slot_rects.get(slot_key)
            if not r:
                continue
            item      = self._item_in_slot(slot_key)
            in_barter = item is not None and id(item) in pl_barter_ids
            bg         = (55, 44, 8) if in_barter else DARK_GRAY
            border_col = BRIGHT_GOLD if in_barter else (GOLD if item else LIGHT_GRAY)
            pygame.draw.rect(self.screen, bg,         r, border_radius=3)
            pygame.draw.rect(self.screen, border_col, r, width=1, border_radius=3)
            if item:
                label = (item.name or item.index or "")[:16]
                col   = BRIGHT_GOLD if in_barter else WHITE
            else:
                label = _slot_label(loc_key)[:12]
                col   = (50, 50, 50)
            ls = self.tiny_font.render(label, True, col)
            self.screen.blit(ls, ls.get_rect(midleft=(r.x + 4, r.centery)))

    def _draw_coin_input(self, rect: pygame.Rect, buf: str,
                         value: int, active: bool) -> None:
        pygame.draw.rect(self.screen, INPUT_BG, rect, border_radius=4)
        pygame.draw.rect(self.screen, GOLD if active else LIGHT_GRAY,
                         rect, width=2, border_radius=4)
        lbl = self.tiny_font.render("Монеты: ", True, LIGHT_GRAY)
        self.screen.blit(lbl, (rect.x + 6, rect.centery - lbl.get_height() // 2))
        val_str = buf if active else str(value)
        col     = WHITE if active else (GOLD if value > 0 else LIGHT_GRAY)
        val     = self.small_font.render(val_str or "0", True, col)
        self.screen.blit(val, (rect.x + lbl.get_width() + 10,
                                rect.centery - val.get_height() // 2))

    # ------------------------------------------------------------------
    # DRAW
    # ------------------------------------------------------------------

    def draw(self):
        self.screen.fill(BLACK)
        self._layout_equip_slots()

        player = self._get_player()
        npc    = self._get_npc()

        player_name  = getattr(player, "name",            "Игрок") if player else "Игрок"
        npc_name     = getattr(npc,    "name",            "???")   if npc    else "???"
        player_coins = getattr(player, "coins", 0) or 0
        npc_coins    = getattr(npc,    "coins", 0) or 0
        player_icon  = getattr(player, "icon_image_path", "")     if player else ""
        npc_icon     = getattr(npc,    "icon_image_path", "")     if npc    else ""

        # ── Portraits ────────────────────────────────────────────────
        pl_icon_sz  = (self._player_portrait_rect.w, self._player_portrait_rect.h)
        npc_icon_sz = (self._npc_portrait_rect.w,    self._npc_portrait_rect.h)
        self._draw_portrait(self._player_portrait_rect,
                            self._load_portrait(player_icon, pl_icon_sz) if player_icon else None)
        self._draw_portrait(self._npc_portrait_rect,
                            self._load_portrait(npc_icon, npc_icon_sz) if npc_icon else None)

        # ── Name + coins info ─────────────────────────────────────────
        pi = self.small_font.render(f"{player_name}  ·  {player_coins} cp", True, GOLD)
        self.screen.blit(pi, pi.get_rect(center=self._player_info_rect.center))
        ni = self.small_font.render(f"{npc_name}  ·  {npc_coins} cp", True, GOLD)
        self.screen.blit(ni, ni.get_rect(center=self._npc_info_rect.center))

        # ── Barter value indicators ───────────────────────────────────
        balanced = self._is_balanced()
        pv = self._player_barter_value()
        nv = self._npc_barter_value()
        val_col_p = BRIGHT_GOLD if balanced else (WHITE if pv > 0 else LIGHT_GRAY)
        val_col_n = BRIGHT_GOLD if balanced else (WHITE if nv > 0 else LIGHT_GRAY)
        pvs = self.small_font.render(f"↓ {pv} cp", True, val_col_p)
        nvs = self.small_font.render(f"↓ {nv} cp", True, val_col_n)
        self.screen.blit(pvs, pvs.get_rect(center=self._barter_val_player_rect.center))
        self.screen.blit(nvs, nvs.get_rect(center=self._barter_val_npc_rect.center))

        # ── Equipment panel ───────────────────────────────────────────
        self._draw_equip_panel()

        # ── Player inventory ──────────────────────────────────────────
        pl_items   = self._player_inv_items()
        pl_offered = {id(it) for it in self._player_barter}
        self._draw_item_list(
            self._player_inv_panel, self._player_inv_rect,
            "Инвентарь", pl_items, self._player_inv_scroll, pl_offered
        )

        # ── NPC inventory ─────────────────────────────────────────────
        npc_items   = self._npc_inv_items()
        npc_offered = {id(it) for it in self._npc_barter}
        self._draw_item_list(
            self._npc_inv_panel, self._npc_inv_rect,
            f"Инвентарь {npc_name[:14]}", npc_items, self._npc_inv_scroll, npc_offered
        )

        # ── Barter lists ──────────────────────────────────────────────
        self._draw_barter_panel(
            self._player_barter_panel, self._player_barter_rect,
            "← Ваше предложение", self._player_barter, self._player_barter_scroll
        )
        self._draw_barter_panel(
            self._npc_barter_panel, self._npc_barter_rect,
            f"{npc_name[:12]} →", self._npc_barter, self._npc_barter_scroll
        )

        # ── Coin inputs ───────────────────────────────────────────────
        self._draw_coin_input(self._player_coin_input_rect,
                              self._coin_buf_player, self._player_coins_offer,
                              self._coin_active == "player")
        self._draw_coin_input(self._npc_coin_input_rect,
                              self._coin_buf_npc, self._npc_coins_offer,
                              self._coin_active == "npc")

        # ── Buttons ───────────────────────────────────────────────────
        if self._balance_btn:
            self._balance_btn.draw(self.screen)
        if self._barter_btn:
            self._barter_btn.draw(self.screen)
            # Dim overlay when barter not yet balanced
            if not balanced:
                dim = pygame.Surface(
                    (self._barter_btn.rect.w, self._barter_btn.rect.h), pygame.SRCALPHA)
                dim.fill((0, 0, 0, 150))
                self.screen.blit(dim, self._barter_btn.rect.topleft)
        if self._leave_btn:
            self._leave_btn.draw(self.screen)

        # ── Drag ghost + drop-zone highlights ────────────────────────
        if self._drag_item:
            # Which panels are valid drop targets for this source?
            valid_ids: Set[int] = set()
            if self._drag_source in ("player_inv", "player_equip"):
                valid_ids = {id(self._player_barter_panel)}
            elif self._drag_source == "player_barter":
                valid_ids = {id(self._player_inv_panel), id(self._equip_panel)}
            elif self._drag_source == "npc_inv":
                valid_ids = {id(self._npc_barter_panel)}
            elif self._drag_source == "npc_barter":
                valid_ids = {id(self._npc_inv_panel)}

            for panel in (self._equip_panel, self._player_inv_panel,
                          self._player_barter_panel, self._npc_barter_panel, self._npc_inv_panel):
                is_valid = id(panel) in valid_ids
                color    = (60, 200, 80) if is_valid else (200, 60, 60)
                surf     = pygame.Surface((panel.w, panel.h), pygame.SRCALPHA)
                surf.fill((*color, 55))
                self.screen.blit(surf, panel.topleft)
                pygame.draw.rect(self.screen, color, panel, width=2, border_radius=6)

            # Ghost label follows cursor
            label = (self._drag_item.name or self._drag_item.index or "?")[:26]
            gs    = self.small_font.render(label, True, WHITE)
            gb    = pygame.Surface((gs.get_width() + 14, gs.get_height() + 6), pygame.SRCALPHA)
            gb.fill((20, 20, 20, 215))
            gx = self._drag_pos[0] + 14
            gy = self._drag_pos[1] - gb.get_height() // 2
            self.screen.blit(gb, (gx, gy))
            self.screen.blit(gs, (gx + 7, gy + 3))
