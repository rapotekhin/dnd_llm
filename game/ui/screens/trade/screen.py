"""Barter trade screen (composed from trade submodules)."""
from __future__ import annotations

import pygame
from typing import TYPE_CHECKING, Optional

from ..base_screen import BaseScreen
from core.entities.base import ID
from core.entities.equipment import GameEquipment
from core.gameplay.trade import TradeState

from .layout import TradeLayoutMixin
from .interaction import TradeInteractionMixin
from .render import TradeRenderMixin

if TYPE_CHECKING:
    from core.entities.npc import NPC


class TradeScreen(TradeRenderMixin, TradeInteractionMixin, TradeLayoutMixin, BaseScreen):
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

        # Where to go when the player clicks "Уйти"
        self._return_to: str = "main"

        self._build_layout()

    # ------------------------------------------------------------------
    # PUBLIC API
    # ------------------------------------------------------------------

    def set_return_to(self, screen_name: str) -> None:
        """Set the destination when the player clicks 'Уйти' (e.g. 'social' or 'main')."""
        self._return_to = screen_name

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
