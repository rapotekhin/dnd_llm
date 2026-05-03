"""Trade screen: hit-testing, drag/drop, and pygame events."""
from __future__ import annotations

import pygame
from typing import List, Optional, Set, Tuple

from ...colors import *
from core.entities.equipment import GameEquipment
from core.gameplay.trade import (
    PANEL_EQUIP, PANEL_PLAYER_INV, PANEL_PLAYER_EQUIP,
    PANEL_PLAYER_BARTER, PANEL_NPC_INV, PANEL_NPC_BARTER,
)

from .constants import _sc


class TradeInteractionMixin:
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
                return self._return_to
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
