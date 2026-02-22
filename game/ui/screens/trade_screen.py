"""
Trade screen – BG3-style barter between player and NPC.

All barter business logic lives in core.gameplay.trade.TradeState.
This file contains only pygame layout, rendering, and event routing.

Layout (left → right):
  [Equipment slots] [Player inventory] [Player offer | NPC offer] [NPC inventory] [Description]

Top strip:    portraits + name/coins + barter value indicators.
Bottom strip: coin inputs + Balance + Barter / Leave buttons.

Drag-and-drop rules are enforced by TradeState.handle_drop(); the screen
only translates pixel coordinates into panel-label strings.
"""

from __future__ import annotations

import os
import pygame
from typing import List, Optional, Dict, Tuple, Set, TYPE_CHECKING

from .base_screen import BaseScreen
from ..colors import *
from ..components import Button
from core.entities.base import ID
from core.entities.equipment import GameEquipment
from core.gameplay.trade import (
    TradeState,
    PANEL_EQUIP, PANEL_PLAYER_INV, PANEL_PLAYER_EQUIP,
    PANEL_PLAYER_BARTER, PANEL_NPC_INV, PANEL_NPC_BARTER,
)
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
        self._trade = TradeState()
        self._portrait_cache: dict = {}

        # ---- Scroll ----
        self._player_inv_scroll:    int = 0
        self._npc_inv_scroll:       int = 0
        self._player_barter_scroll: int = 0
        self._npc_barter_scroll:    int = 0

        # ---- Description panel ----
        # _selected_item is pinned by a click; _hovered_item is a live preview.
        self._selected_item:   Optional[GameEquipment] = None
        self._hovered_item:    Optional[GameEquipment] = None
        self._desc_scroll:     int = 0
        self._desc_max_scroll: int = 0

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
        self._desc_panel          = pygame.Rect(0, 0, 0, 0)
        self._desc_content_rect   = pygame.Rect(0, 0, 0, 0)

        self._player_portrait_rect   = pygame.Rect(0, 0, 0, 0)
        self._npc_portrait_rect      = pygame.Rect(0, 0, 0, 0)
        self._player_info_rect       = pygame.Rect(0, 0, 0, 0)
        self._npc_info_rect          = pygame.Rect(0, 0, 0, 0)
        self._barter_val_player_rect = pygame.Rect(0, 0, 0, 0)
        self._barter_val_npc_rect    = pygame.Rect(0, 0, 0, 0)

        self._player_coin_input_rect = pygame.Rect(0, 0, 0, 0)
        self._npc_coin_input_rect    = pygame.Rect(0, 0, 0, 0)

        self._balance_btn: Optional[Button] = None
        self._barter_btn:  Optional[Button] = None
        self._leave_btn:   Optional[Button] = None

        self._build_layout()

    # ------------------------------------------------------------------
    # PUBLIC API
    # ------------------------------------------------------------------

    def set_npc(self, npc_id: ID) -> None:
        """Initialise screen for a given NPC and reset all state."""
        self._trade.reset(npc_id)
        self._player_inv_scroll    = 0
        self._npc_inv_scroll       = 0
        self._player_barter_scroll = 0
        self._npc_barter_scroll    = 0
        self._selected_item   = None
        self._hovered_item    = None
        self._desc_scroll     = 0
        self._desc_max_scroll = 0

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

        icon_h = _sc(60, s)
        info_h = _sc(26, s)
        top_h  = icon_h + _sc(4, s) + info_h

        btn_h  = _sc(38, s)
        coin_h = _sc(34, s)
        btm_h  = coin_h + _sc(6, s) + btn_h + _sc(6, s) + btn_h + _sc(4, s)

        content_top    = m + top_h + _sc(6, s)
        content_bottom = h - m - btm_h
        content_h      = max(40, content_bottom - content_top)

        # Column widths (desc_w taken from what was previously barter space)
        eq_w     = max(90,  int(w * 0.14))
        inv_w    = max(110, int(w * 0.21))
        desc_w   = max(130, int(w * 0.13))
        barter_w = max(70,  (w - 2 * m - eq_w - 2 * inv_w - desc_w - 5 * gap) // 2)

        eq_x      = m
        pl_inv_x  = eq_x     + eq_w     + gap
        brt_pl_x  = pl_inv_x + inv_w    + gap
        brt_npc_x = brt_pl_x + barter_w + gap
        npc_inv_x = brt_npc_x + barter_w + gap
        desc_x    = npc_inv_x + inv_w    + gap

        # Top strip: portraits
        player_sec_w = eq_w + gap + inv_w
        icon_y = m
        self._player_portrait_rect = pygame.Rect(
            eq_x + (player_sec_w - icon_h) // 2, icon_y, icon_h, icon_h
        )
        self._npc_portrait_rect = pygame.Rect(
            npc_inv_x + (inv_w - icon_h) // 2, icon_y, icon_h, icon_h
        )

        info_y = icon_y + icon_h + _sc(4, s)
        self._player_info_rect       = pygame.Rect(eq_x,      info_y, player_sec_w, info_h)
        self._npc_info_rect          = pygame.Rect(npc_inv_x, info_y, inv_w,        info_h)
        self._barter_val_player_rect = pygame.Rect(brt_pl_x,  info_y, barter_w,     info_h)
        self._barter_val_npc_rect    = pygame.Rect(brt_npc_x, info_y, barter_w,     info_h)

        title_h  = _sc(18, s)
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

        self._desc_panel = pygame.Rect(desc_x, content_top, desc_w, content_h)
        self._desc_content_rect = pygame.Rect(
            desc_x + list_pad, content_top + title_h,
            desc_w - list_pad * 2 - SB_W - SB_PAD, content_h - title_h - list_pad
        )

        ci_y = content_bottom + _sc(6, s)
        self._player_coin_input_rect = pygame.Rect(brt_pl_x,  ci_y, barter_w, coin_h)
        self._npc_coin_input_rect    = pygame.Rect(brt_npc_x, ci_y, barter_w, coin_h)

        bal_y = ci_y + coin_h + _sc(6, s)
        act_y = bal_y + btn_h + _sc(6, s)

        barter_center_x = brt_pl_x + barter_w

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

        self._barter_btn = Button(
            act_x, act_y, act_barter_w, btn_h, "Бартер", self.small_font
        )
        self._leave_btn = Button(
            act_x + act_barter_w + act_gap, act_y, act_leave_w, btn_h, "Уйти", self.small_font
        )

        self._layout_equip_slots()

    def _layout_equip_slots(self) -> None:
        r  = self._equip_panel
        s  = self._scale
        pad     = _sc(5, s)
        slot_w  = r.w - 2 * pad
        slot_h  = _sc(26, s)
        row_h   = slot_h + _sc(3, s)
        title_h = _sc(18, s)
        y = r.y + pad + title_h
        for i, (key, _, _) in enumerate(SLOTS):
            self._slot_rects[key] = pygame.Rect(r.x + pad, y + i * row_h, slot_w, slot_h)

    # ------------------------------------------------------------------
    # HIT-TEST HELPERS  (coordinate → panel label)
    # ------------------------------------------------------------------

    def _panel_at(self, pos: Tuple[int, int]) -> str:
        """Return the PANEL_* label for the panel under *pos*, or ''."""
        if self._player_barter_panel.collidepoint(pos):
            return PANEL_PLAYER_BARTER
        if self._npc_barter_panel.collidepoint(pos):
            return PANEL_NPC_BARTER
        if self._player_inv_panel.collidepoint(pos):
            return PANEL_PLAYER_INV
        if self._equip_panel.collidepoint(pos):
            return PANEL_EQUIP
        if self._npc_inv_panel.collidepoint(pos):
            return PANEL_NPC_INV
        return ""

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

    def _item_under_mouse(self, pos: Tuple[int, int]) -> Optional[GameEquipment]:
        """Return the item (if any) under the mouse across all panels."""
        s      = self._scale
        line_h = _sc(24, s)

        def _at(rect: pygame.Rect, items: list, scroll: int) -> Optional[GameEquipment]:
            if not rect.collidepoint(pos):
                return None
            for i, it in enumerate(items):
                ry = rect.y + i * line_h - scroll
                if ry <= pos[1] < ry + line_h:
                    return it
            return None

        t = _at(self._player_inv_rect, self._trade.player_inv_items(), self._player_inv_scroll)
        if t:
            return t
        t = _at(self._npc_inv_rect, self._trade.npc_inv_items(), self._npc_inv_scroll)
        if t:
            return t
        t = _at(self._player_barter_rect, self._trade.player_barter, self._player_barter_scroll)
        if t:
            return t
        t = _at(self._npc_barter_rect, self._trade.npc_barter, self._npc_barter_scroll)
        if t:
            return t
        for slot_key, rect in self._slot_rects.items():
            if rect.collidepoint(pos):
                return self._trade.item_in_slot(slot_key)
        return None

    # ------------------------------------------------------------------
    # DESCRIPTION HELPERS
    # ------------------------------------------------------------------

    def _pin_item(self, item: GameEquipment) -> None:
        if item is not self._selected_item:
            self._selected_item = item
            self._desc_scroll   = 0

    def _wrap_desc(self, raw_lines: list, max_w: int) -> List[str]:
        out: List[str] = []
        for raw in (raw_lines if isinstance(raw_lines, list) else [str(raw_lines)]):
            words = str(raw or "").split()
            if not words:
                out.append("")
                continue
            cur = ""
            for word in words:
                trial = (cur + " " + word).strip() if cur else word
                if self.tiny_font.size(trial)[0] <= max_w:
                    cur = trial
                else:
                    if cur:
                        out.append(cur)
                    cur = word
            if cur:
                out.append(cur)
        return out or ["—"]

    # ------------------------------------------------------------------
    # DRAG-AND-DROP HELPERS
    # ------------------------------------------------------------------

    def _cancel_drag(self) -> None:
        self._drag_item         = None
        self._drag_source       = ""
        self._pending_drag_item = None
        self._drag_start_pos    = (0, 0)

    def _handle_drop(self, pos: Tuple[int, int]) -> None:
        item = self._drag_item
        if not item:
            return
        target = self._panel_at(pos)
        if target:
            self._trade.handle_drop(item, self._drag_source, target)

    # ------------------------------------------------------------------
    # HANDLE EVENTS
    # ------------------------------------------------------------------

    def handle_event(self, event: pygame.event.Event):
        trade = self._trade

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                if self._drag_item:
                    self._cancel_drag()
                    return None
                return "social"

            # Coin field keyboard input
            if trade.coin_active == "player":
                if event.key == pygame.K_BACKSPACE:
                    trade.coin_buf_player = trade.coin_buf_player[:-1]
                elif event.unicode.isdigit() and len(trade.coin_buf_player) < 9:
                    trade.coin_buf_player += event.unicode
                trade.player_coins_offer = int(trade.coin_buf_player) if trade.coin_buf_player else 0
                return None
            if trade.coin_active == "npc":
                if event.key == pygame.K_BACKSPACE:
                    trade.coin_buf_npc = trade.coin_buf_npc[:-1]
                elif event.unicode.isdigit() and len(trade.coin_buf_npc) < 9:
                    trade.coin_buf_npc += event.unicode
                trade.npc_coins_offer = int(trade.coin_buf_npc) if trade.coin_buf_npc else 0
                return None
            return None

        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            self._layout_equip_slots()

            # Coin input focus
            if self._player_coin_input_rect.collidepoint(pos):
                trade.coin_active = "player"
                return None
            if self._npc_coin_input_rect.collidepoint(pos):
                trade.coin_active = "npc"
                return None
            trade.coin_active = ""

            # Buttons
            if self._leave_btn and self._leave_btn.is_clicked(pos):
                return "social"
            if self._balance_btn and self._balance_btn.is_clicked(pos):
                trade.balance()
                return None
            if self._barter_btn and self._barter_btn.is_clicked(pos) and trade.is_balanced():
                trade.execute_barter()
                return None

            # ── Start drag from player inventory ──────────────────────
            pl_items = trade.player_inv_items()
            it = self._item_at_list(pos, self._player_inv_rect, pl_items, self._player_inv_scroll)
            if it:
                self._pin_item(it)
                self._pending_drag_item = it
                self._drag_source       = PANEL_PLAYER_INV
                self._drag_start_pos    = pos
                self._drag_item         = None
                return None

            # ── Start drag from NPC inventory ─────────────────────────
            npc_items = trade.npc_inv_items()
            it = self._item_at_list(pos, self._npc_inv_rect, npc_items, self._npc_inv_scroll)
            if it:
                self._pin_item(it)
                self._pending_drag_item = it
                self._drag_source       = PANEL_NPC_INV
                self._drag_start_pos    = pos
                self._drag_item         = None
                return None

            # ── Start drag from player barter list ────────────────────
            it = self._item_at_list(pos, self._player_barter_rect,
                                    trade.player_barter, self._player_barter_scroll)
            if it:
                self._pin_item(it)
                self._pending_drag_item = it
                self._drag_source       = PANEL_PLAYER_BARTER
                self._drag_start_pos    = pos
                self._drag_item         = None
                return None

            # ── Start drag from NPC barter list ───────────────────────
            it = self._item_at_list(pos, self._npc_barter_rect,
                                    trade.npc_barter, self._npc_barter_scroll)
            if it:
                self._pin_item(it)
                self._pending_drag_item = it
                self._drag_source       = PANEL_NPC_BARTER
                self._drag_start_pos    = pos
                self._drag_item         = None
                return None

            # ── Start drag from equipment slot ────────────────────────
            for slot_key, rect in self._slot_rects.items():
                if rect.collidepoint(pos):
                    item = self._trade.item_in_slot(slot_key)
                    if item:
                        self._pin_item(item)
                        self._pending_drag_item = item
                        self._drag_source       = PANEL_PLAYER_EQUIP
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
            new_hover = self._item_under_mouse(event.pos)
            if new_hover is not self._hovered_item:
                self._hovered_item = new_hover
                if self._selected_item is None:
                    self._desc_scroll = 0
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

            def _clamp(cur: int, count: int, rect_h: int, dy: int) -> int:
                max_s = max(0, count * line_h - rect_h)
                return max(0, min(max_s, cur + (-step if dy > 0 else step)))

            if self._player_inv_rect.collidepoint(mpos):
                self._player_inv_scroll = _clamp(
                    self._player_inv_scroll, len(trade.player_inv_items()),
                    self._player_inv_rect.height, event.y)
            elif self._npc_inv_rect.collidepoint(mpos):
                self._npc_inv_scroll = _clamp(
                    self._npc_inv_scroll, len(trade.npc_inv_items()),
                    self._npc_inv_rect.height, event.y)
            elif self._player_barter_rect.collidepoint(mpos):
                self._player_barter_scroll = _clamp(
                    self._player_barter_scroll, len(trade.player_barter),
                    self._player_barter_rect.height, event.y)
            elif self._npc_barter_rect.collidepoint(mpos):
                self._npc_barter_scroll = _clamp(
                    self._npc_barter_scroll, len(trade.npc_barter),
                    self._npc_barter_rect.height, event.y)
            elif self._desc_panel.collidepoint(mpos) and self._desc_max_scroll > 0:
                delta = -step if event.y > 0 else step
                self._desc_scroll = max(0, min(self._desc_max_scroll,
                                               self._desc_scroll + delta))
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
        pl_barter_ids = {id(it) for it in self._trade.player_barter}
        pygame.draw.rect(self.screen, MODAL_BG, self._equip_panel, border_radius=6)
        pygame.draw.rect(self.screen, GOLD,     self._equip_panel, width=1, border_radius=6)
        t = self.tiny_font.render("Экипировка", True, GOLD)
        self.screen.blit(t, (self._equip_panel.x + 4, self._equip_panel.y + 2))

        for slot_key, loc_key, _ in SLOTS:
            r = self._slot_rects.get(slot_key)
            if not r:
                continue
            item      = self._trade.item_in_slot(slot_key)
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

    def _draw_desc_panel(self) -> None:
        s       = self._scale
        panel   = self._desc_panel
        content = self._desc_content_rect

        pinned     = self._selected_item is not None
        item       = self._selected_item if pinned else self._hovered_item
        border_col = BRIGHT_GOLD if pinned else GOLD

        pygame.draw.rect(self.screen, MODAL_BG,   panel, border_radius=6)
        pygame.draw.rect(self.screen, border_col, panel, width=1, border_radius=6)
        title_surf = self.tiny_font.render("Описание", True, border_col)
        self.screen.blit(title_surf, (panel.x + 4, panel.y + 2))

        if not item:
            for i, txt in enumerate(("Кликни или наведи", "на предмет")):
                h = self.tiny_font.render(txt, True, (80, 80, 80))
                self.screen.blit(h, h.get_rect(
                    center=(panel.centerx, panel.centery - _sc(10, s) + i * _sc(18, s))
                ))
            return

        # Item name
        name_surf = self.small_font.render(
            (item.name or item.index or "?")[:22], True, BRIGHT_GOLD
        )
        self.screen.blit(name_surf, (content.x, content.y))
        name_h = name_surf.get_height() + _sc(4, s)

        # Cost line
        cost_y   = content.y + name_h
        cost_obj = getattr(item, "cost", None)
        cost_str = ""
        if cost_obj is not None:
            qty  = getattr(cost_obj, "quantity", None)
            unit = getattr(cost_obj, "unit", "gp") or "gp"
            cost_str = f"{qty} {unit}" if qty is not None else ""
        if cost_str:
            cost_surf = self.tiny_font.render(cost_str, True, GOLD)
            self.screen.blit(cost_surf, (content.x, cost_y))
            cost_h = cost_surf.get_height() + _sc(3, s)
        else:
            cost_h = 0

        # Description text with scroll
        desc_line_h = _sc(17, s)
        text_top    = cost_y + cost_h
        text_h      = panel.bottom - text_top - _sc(4, s)

        raw     = item.desc or ["—"]
        wrapped = self._wrap_desc(raw, content.w)
        total_h = len(wrapped) * desc_line_h
        max_s   = max(0, total_h - text_h)
        self._desc_max_scroll = max_s
        self._desc_scroll     = min(self._desc_scroll, max_s)

        clip_rect  = pygame.Rect(panel.x, text_top, panel.w, text_h)
        saved_clip = self.screen.get_clip()
        self.screen.set_clip(clip_rect)
        for i, line in enumerate(wrapped):
            yy = text_top + i * desc_line_h - self._desc_scroll
            if yy + desc_line_h < text_top or yy > panel.bottom:
                continue
            ls = self.tiny_font.render(line, True, LIGHT_GRAY)
            self.screen.blit(ls, (content.x, yy))
        self.screen.set_clip(saved_clip)

        if max_s > 0:
            sb_x    = panel.right - SB_W - SB_PAD
            track   = pygame.Rect(sb_x, text_top + 2, SB_W, text_h - 4)
            vis_r   = text_h / max(1, total_h)
            thumb_h = max(16, int(track.h * vis_r))
            thumb_y = track.y + int((self._desc_scroll / max_s) * (track.h - thumb_h))
            pygame.draw.rect(self.screen, DARK_GRAY, track, border_radius=3)
            pygame.draw.rect(self.screen, GOLD,
                             pygame.Rect(sb_x, thumb_y, SB_W, thumb_h), border_radius=3)

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

        trade  = self._trade
        player = trade.get_player()
        npc    = trade.get_npc()

        player_name  = getattr(player, "name",            "Игрок") if player else "Игрок"
        npc_name     = getattr(npc,    "name",            "???")   if npc    else "???"
        player_coins = getattr(player, "coins", 0) or 0
        npc_coins    = getattr(npc,    "coins", 0) or 0
        player_icon  = getattr(player, "icon_image_path", "")     if player else ""
        npc_icon     = getattr(npc,    "icon_image_path", "")     if npc    else ""

        # Portraits
        pl_sz  = (self._player_portrait_rect.w, self._player_portrait_rect.h)
        npc_sz = (self._npc_portrait_rect.w,    self._npc_portrait_rect.h)
        self._draw_portrait(self._player_portrait_rect,
                            self._load_portrait(player_icon, pl_sz) if player_icon else None)
        self._draw_portrait(self._npc_portrait_rect,
                            self._load_portrait(npc_icon, npc_sz) if npc_icon else None)

        # Name + coins
        pi = self.small_font.render(f"{player_name}  ·  {player_coins} cp", True, GOLD)
        self.screen.blit(pi, pi.get_rect(center=self._player_info_rect.center))
        ni = self.small_font.render(f"{npc_name}  ·  {npc_coins} cp", True, GOLD)
        self.screen.blit(ni, ni.get_rect(center=self._npc_info_rect.center))

        # Barter value indicators
        balanced  = trade.is_balanced()
        pv        = trade.player_barter_value()
        nv        = trade.npc_barter_value()
        val_col_p = BRIGHT_GOLD if balanced else (WHITE if pv > 0 else LIGHT_GRAY)
        val_col_n = BRIGHT_GOLD if balanced else (WHITE if nv > 0 else LIGHT_GRAY)
        pvs = self.small_font.render(f"↓ {pv} cp", True, val_col_p)
        nvs = self.small_font.render(f"↓ {nv} cp", True, val_col_n)
        self.screen.blit(pvs, pvs.get_rect(center=self._barter_val_player_rect.center))
        self.screen.blit(nvs, nvs.get_rect(center=self._barter_val_npc_rect.center))

        # Equipment panel
        self._draw_equip_panel()

        # Player inventory
        pl_items   = trade.player_inv_items()
        pl_offered = {id(it) for it in trade.player_barter}
        self._draw_item_list(
            self._player_inv_panel, self._player_inv_rect,
            "Инвентарь", pl_items, self._player_inv_scroll, pl_offered
        )

        # NPC inventory
        npc_items   = trade.npc_inv_items()
        npc_offered = {id(it) for it in trade.npc_barter}
        self._draw_item_list(
            self._npc_inv_panel, self._npc_inv_rect,
            f"Инвентарь {npc_name[:14]}", npc_items, self._npc_inv_scroll, npc_offered
        )

        # Barter lists
        self._draw_barter_panel(
            self._player_barter_panel, self._player_barter_rect,
            "← Ваше предложение", trade.player_barter, self._player_barter_scroll
        )
        self._draw_barter_panel(
            self._npc_barter_panel, self._npc_barter_rect,
            f"{npc_name[:12]} →", trade.npc_barter, self._npc_barter_scroll
        )

        # Description panel
        self._draw_desc_panel()

        # Coin inputs
        self._draw_coin_input(self._player_coin_input_rect,
                              trade.coin_buf_player, trade.player_coins_offer,
                              trade.coin_active == "player")
        self._draw_coin_input(self._npc_coin_input_rect,
                              trade.coin_buf_npc, trade.npc_coins_offer,
                              trade.coin_active == "npc")

        # Buttons
        if self._balance_btn:
            self._balance_btn.draw(self.screen)
        if self._barter_btn:
            self._barter_btn.draw(self.screen)
            if not balanced:
                dim = pygame.Surface(
                    (self._barter_btn.rect.w, self._barter_btn.rect.h), pygame.SRCALPHA)
                dim.fill((0, 0, 0, 150))
                self.screen.blit(dim, self._barter_btn.rect.topleft)
        if self._leave_btn:
            self._leave_btn.draw(self.screen)

        # Drag ghost + drop-zone highlights
        if self._drag_item:
            valid_ids: Set[int] = set()
            if self._drag_source in (PANEL_PLAYER_INV, PANEL_PLAYER_EQUIP):
                valid_ids = {id(self._player_barter_panel)}
            elif self._drag_source == PANEL_PLAYER_BARTER:
                valid_ids = {id(self._player_inv_panel), id(self._equip_panel)}
            elif self._drag_source == PANEL_NPC_INV:
                valid_ids = {id(self._npc_barter_panel)}
            elif self._drag_source == PANEL_NPC_BARTER:
                valid_ids = {id(self._npc_inv_panel)}

            for panel in (self._equip_panel, self._player_inv_panel,
                          self._player_barter_panel, self._npc_barter_panel,
                          self._npc_inv_panel):
                is_valid = id(panel) in valid_ids
                color    = (60, 200, 80) if is_valid else (200, 60, 60)
                surf     = pygame.Surface((panel.w, panel.h), pygame.SRCALPHA)
                surf.fill((*color, 55))
                self.screen.blit(surf, panel.topleft)
                pygame.draw.rect(self.screen, color, panel, width=2, border_radius=6)

            label = (self._drag_item.name or self._drag_item.index or "?")[:26]
            gs    = self.small_font.render(label, True, WHITE)
            gb    = pygame.Surface((gs.get_width() + 14, gs.get_height() + 6), pygame.SRCALPHA)
            gb.fill((20, 20, 20, 215))
            gx = self._drag_pos[0] + 14
            gy = self._drag_pos[1] - gb.get_height() // 2
            self.screen.blit(gb, (gx, gy))
            self.screen.blit(gs, (gx + 7, gy + 3))
