"""Trade screen: panel geometry."""
import pygame

from ..colors import *
from ..components import Button

from .constants import SB_W, SB_PAD, SLOTS, _sc


class TradeLayoutMixin:
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
