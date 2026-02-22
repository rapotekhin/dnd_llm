"""
Social screen – NPC dialogue, Pathfinder / Baldur's Gate style.

All dialogue state and business logic live in
core.gameplay.social_interaction.SocialState.
This file contains only pygame layout, rendering, and event routing.

Layout:  NPC portrait (left) | dialogue chat (center) | player portrait (right).
Bottom:  action buttons (Trade / Attack / Leave).
"""

from __future__ import annotations

import os
import pygame
from typing import List, Optional, TYPE_CHECKING

from .base_screen import BaseScreen
from ..colors import *
from ..components import Button
from core.entities.base import ID
from core.gameplay.social_interaction import SocialState

if TYPE_CHECKING:
    from core.entities.npc import NPC

SB_W = 12
SB_PAD = 4
PORTRAIT_W_RATIO = 0.18
PORTRAIT_H_RATIO = 0.40
BTN_H_RATIO = 0.07


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


class SocialScreen(BaseScreen):
    """
    Dialogue screen with an NPC.
    Call set_npc(npc_id) before switching to this screen.
    """

    def __init__(self, screen: pygame.Surface):
        super().__init__(screen)
        self._state = SocialState()
        self._portrait_cache: dict = {}

        # UI-only scroll state
        self._chat_scroll: int = 0
        self._chat_scroll_dragging: bool = False

        # Input field
        self._input_buffer: str = ""
        self._input_active: bool = True

        self._build_layout()

    # --------------------------------------------------
    # PUBLIC API
    # --------------------------------------------------

    def set_npc(self, npc_id: ID) -> None:
        """Set the NPC to talk to and reset dialogue state."""
        self._state.reset(npc_id)
        self._chat_scroll = 0

    # --------------------------------------------------
    # LAYOUT
    # --------------------------------------------------

    def _build_layout(self) -> None:
        s = self._scale
        w, h = self._w, self._h

        self.font       = pygame.font.Font(None, _sc(26, s))
        self.small_font = pygame.font.Font(None, _sc(22, s))
        self.link_font  = pygame.font.Font(None, _sc(22, s))
        self.title_font = pygame.font.Font(None, _sc(30, s))

        margin = _sc(16, s)
        gap    = _sc(10, s)

        self._btn_h = _sc(BTN_H_RATIO * h, s)
        self._btn_y = h - self._btn_h - margin

        content_top    = margin
        content_bottom = self._btn_y - gap
        content_h      = content_bottom - content_top

        portrait_w = int(w * PORTRAIT_W_RATIO)
        portrait_h = int(content_h * PORTRAIT_H_RATIO)

        self._npc_portrait_rect = pygame.Rect(margin, content_top, portrait_w, portrait_h)
        self._player_portrait_rect = pygame.Rect(
            w - margin - portrait_w, content_top, portrait_w, portrait_h
        )

        chat_x = margin + portrait_w + gap
        chat_w = w - margin - portrait_w - gap - portrait_w - gap - margin
        self._line_h   = _sc(22, s)
        self._chat_pad = _sc(10, s)

        input_h  = _sc(44, s)
        send_w   = _sc(100, s)
        send_gap = _sc(8, s)

        chat_h = content_h - input_h - send_gap
        self._chat_rect = pygame.Rect(chat_x, content_top, chat_w, chat_h)

        input_y = content_top + chat_h + send_gap
        input_w = chat_w - send_w - send_gap
        self._input_rect = pygame.Rect(chat_x, input_y, input_w, input_h)
        self._send_btn   = Button(
            chat_x + input_w + send_gap, input_y,
            send_w, input_h, "Сказать", self.font
        )

        self._npc_name_rect = pygame.Rect(
            margin, content_top + portrait_h + gap, portrait_w, _sc(28, s)
        )
        self._player_name_rect = pygame.Rect(
            w - margin - portrait_w, content_top + portrait_h + gap,
            portrait_w, _sc(28, s)
        )

        btn_count   = 3
        total_btn_w = w - 2 * margin
        btn_w       = (total_btn_w - (btn_count - 1) * gap) // btn_count
        labels      = ["Торговать", "Напасть", "Уйти"]
        self._action_buttons: List[Button] = [
            Button(margin + i * (btn_w + gap), self._btn_y, btn_w, self._btn_h, lbl, self.font)
            for i, lbl in enumerate(labels)
        ]

    # --------------------------------------------------
    # DRAW HELPERS
    # --------------------------------------------------

    def _load_portrait(self, path: str, size: tuple) -> Optional[pygame.Surface]:
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

    def _draw_portrait_frame(self, rect: pygame.Rect,
                             surf: Optional[pygame.Surface], label: str) -> None:
        pygame.draw.rect(self.screen, DARK_GRAY, rect, border_radius=8)
        if surf:
            pad   = 4
            inner = rect.inflate(-pad * 2, -pad * 2)
            self.screen.blit(pygame.transform.smoothscale(surf, (inner.w, inner.h)), inner.topleft)
        else:
            cx, cy = rect.centerx, rect.centery
            r = min(rect.w, rect.h) // 4
            pygame.draw.circle(self.screen, LIGHT_GRAY, (cx, cy - r // 2), r // 2, 2)
            pygame.draw.arc(self.screen, LIGHT_GRAY,
                            pygame.Rect(cx - r, cy, r * 2, r), 0, 3.14159, 2)
        pygame.draw.rect(self.screen, GOLD, rect, width=2, border_radius=8)
        name_surf = self.small_font.render(label, True, GOLD)
        self.screen.blit(name_surf, (
            rect.centerx - name_surf.get_width() // 2,
            rect.bottom + _sc(4, self._scale)
        ))

    # --------------------------------------------------
    # SCROLL HELPERS  (depend on UI metrics → stay in screen)
    # --------------------------------------------------

    def _chat_max_scroll(self) -> int:
        total   = len(self._state.chat_lines) * self._line_h
        visible = self._chat_rect.height - 2 * self._chat_pad
        return max(0, total - visible)

    def _chat_scrollbar_rects(self):
        mx = self._chat_max_scroll()
        if mx <= 0:
            return None, None
        rx    = self._chat_rect.right - SB_W - SB_PAD
        track = pygame.Rect(rx, self._chat_rect.y + SB_PAD,
                            SB_W, self._chat_rect.height - 2 * SB_PAD)
        vis   = (self._chat_rect.height - 2 * self._chat_pad) / max(
            1, len(self._state.chat_lines) * self._line_h)
        th    = max(20, int(track.height * vis))
        ty    = track.y + int((self._chat_scroll / mx) * (track.height - th))
        return track, pygame.Rect(rx, ty, SB_W, th)

    def _wrap_line(self, text: str, max_w: int) -> List[str]:
        words = text.split()
        lines: List[str] = []
        cur = ""
        for w in words:
            trial = (cur + " " + w).strip() if cur else w
            if self.small_font.size(trial)[0] <= max_w:
                cur = trial
            else:
                if cur:
                    lines.append(cur)
                cur = w
        if cur:
            lines.append(cur)
        return lines or [""]

    # --------------------------------------------------
    # INPUT HANDLER
    # --------------------------------------------------

    def _on_send(self) -> None:
        text = self._input_buffer.strip()
        if not text:
            return
        self._state.add_player_message(text)
        self._input_buffer = ""
        self._chat_scroll  = self._chat_max_scroll()
        # Future: trigger self._state.run_npc_reply(api_manager, text)

    # --------------------------------------------------
    # SCREEN INTERFACE
    # --------------------------------------------------

    def handle_event(self, event: pygame.event.Event):
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                return "main"
            if self._input_active:
                if event.key == pygame.K_RETURN:
                    self._on_send()
                elif event.key == pygame.K_BACKSPACE:
                    self._input_buffer = self._input_buffer[:-1]
                elif event.unicode and len(self._input_buffer) < 500:
                    self._input_buffer += event.unicode
            return None

        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            self._input_active = self._input_rect.collidepoint(pos)

            if self._send_btn.is_clicked(pos):
                self._on_send()
                return None

            mx = self._chat_max_scroll()
            if mx > 0 and self._chat_rect.collidepoint(pos):
                _, thumb = self._chat_scrollbar_rects()
                if thumb and thumb.collidepoint(pos):
                    self._chat_scroll_dragging = True

            # Trade button
            if self._action_buttons[0].is_clicked(pos):
                if self._state.npc_id is not None:
                    return f"trade:{self._state.npc_id}"
                self._state.add_system_message("Не выбран NPC для торговли.")
                self._chat_scroll = self._chat_max_scroll()
                return None

            # Attack button (stub)
            if self._action_buttons[1].is_clicked(pos):
                self._state.add_system_message("Бой пока не реализован.")
                self._chat_scroll = self._chat_max_scroll()
                return None

            # Leave button
            if self._action_buttons[2].is_clicked(pos):
                return "main"

        if event.type == pygame.MOUSEBUTTONUP and event.button == 1:
            self._chat_scroll_dragging = False

        if event.type == pygame.MOUSEMOTION and self._chat_scroll_dragging:
            mx = self._chat_max_scroll()
            if mx > 0:
                track, thumb = self._chat_scrollbar_rects()
                if track and thumb:
                    denom = track.height - thumb.height
                    r = (event.pos[1] - track.y) / denom if denom > 0 else 0
                    self._chat_scroll = int(max(0, min(1, r)) * mx)

        if event.type == pygame.MOUSEWHEEL and self._chat_rect.collidepoint(pygame.mouse.get_pos()):
            step = self._line_h * 3
            if event.y > 0:
                self._chat_scroll = max(0, self._chat_scroll - step)
            else:
                self._chat_scroll = min(self._chat_max_scroll(), self._chat_scroll + step)

        return None

    def update(self):
        pos = pygame.mouse.get_pos()
        for b in self._action_buttons:
            b.update(pos)
        self._send_btn.update(pos)

    def draw(self):
        self.screen.fill(BLACK)
        s = self._scale

        npc    = self._state.get_npc()
        player = self._state.get_player()

        npc_name    = getattr(npc,    "name", "???")   if npc    else "???"
        player_name = getattr(player, "name", "Игрок") if player else "Игрок"
        npc_icon    = getattr(npc,    "icon_image_path", "") if npc    else ""
        player_icon = getattr(player, "icon_image_path", "") if player else ""

        # Portraits
        npc_img = (
            self._load_portrait(npc_icon,
                                (self._npc_portrait_rect.w - 8, self._npc_portrait_rect.h - 8))
            if npc_icon else None
        )
        player_img = (
            self._load_portrait(player_icon,
                                (self._player_portrait_rect.w - 8, self._player_portrait_rect.h - 8))
            if player_icon else None
        )
        self._draw_portrait_frame(self._npc_portrait_rect,    npc_img,    npc_name)
        self._draw_portrait_frame(self._player_portrait_rect, player_img, player_name)

        # Chat box
        pygame.draw.rect(self.screen, MODAL_BG, self._chat_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD,     self._chat_rect, width=2, border_radius=8)

        pad        = self._chat_pad
        max_text_w = self._chat_rect.w - 2 * pad - SB_W - SB_PAD - 4
        wrapped: List[str] = []
        for raw in self._state.chat_lines:
            wrapped.extend(self._wrap_line(raw, max_text_w))

        clip_save = self.screen.get_clip()
        self.screen.set_clip(self._chat_rect)
        y = self._chat_rect.y + pad - self._chat_scroll
        for line in wrapped:
            if self._chat_rect.y < y + self._line_h and y < self._chat_rect.bottom:
                if line.startswith("[Система]"):
                    color = LIGHT_GRAY
                elif line.startswith(f"[{npc_name}]"):
                    color = BRIGHT_GOLD
                else:
                    color = WHITE
                surf = self.small_font.render(line[:120], True, color)
                self.screen.blit(surf, (self._chat_rect.x + pad, y))
            y += self._line_h
        self.screen.set_clip(clip_save)

        # Scrollbar
        if self._chat_max_scroll() > 0:
            track, thumb = self._chat_scrollbar_rects()
            if track and thumb:
                pygame.draw.rect(self.screen, DARK_GRAY, track, border_radius=4)
                pygame.draw.rect(self.screen, GOLD,      thumb, border_radius=4)

        # Input field
        pygame.draw.rect(self.screen, INPUT_BG, self._input_rect, border_radius=6)
        border_col = GOLD if self._input_active else LIGHT_GRAY
        pygame.draw.rect(self.screen, border_col, self._input_rect, width=2, border_radius=6)
        input_text = self._input_buffer or "Сказать что-нибудь..."
        input_col  = WHITE if self._input_buffer else LIGHT_GRAY
        input_surf = self.font.render(input_text[:80], True, input_col)
        self.screen.blit(input_surf, (
            self._input_rect.x + 10,
            self._input_rect.centery - input_surf.get_height() // 2
        ))
        self._send_btn.draw(self.screen)

        # Divider + action buttons
        div_y = self._btn_y - _sc(6, s)
        pygame.draw.line(self.screen, GOLD,
                         (_sc(16, s), div_y), (self._w - _sc(16, s), div_y), 1)
        for b in self._action_buttons:
            b.draw(self.screen)
