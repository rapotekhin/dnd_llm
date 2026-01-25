"""
Main game screen - chat, nav, quick actions.
"""

import pygame
from typing import List, Union
from .base_screen import BaseScreen
from ..colors import *
from ..components import Button
from localization import loc

SB_W = 12
SB_PAD = 4


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


class MainScreen(BaseScreen):
    """Main game screen: nav bar, chat area, input, quick actions."""

    def __init__(self, screen: pygame.Surface):
        super().__init__(screen)
        s = self._scale
        w, h = self._w, self._h
        self.font = pygame.font.Font(None, _sc(26, s))  # Same as other screens
        self.small_font = pygame.font.Font(None, _sc(22, s))  # Same as other screens

        self.nav_h = _sc(48, s)
        pad = _sc(8, s)
        input_h = _sc(44, s)
        quick_h = _sc(48, s)
        self.chat_y = self.nav_h + pad
        self.chat_h = h - self.nav_h - pad - (input_h + pad) - (quick_h + pad) - pad
        self.input_y = self.chat_y + self.chat_h + pad
        self.input_h = input_h
        self.quick_y = self.input_y + self.input_h + pad
        self.quick_h = quick_h
        self.line_h = _sc(24, s)

        margin = _sc(16, s)
        nav_gap = _sc(10, s)
        nw = (w - 2 * margin - 5 * nav_gap) // 5
        self.nav_buttons: List[Button] = []
        for i, key in enumerate(["nav_inventory", "nav_map", "nav_journal", "nav_character", "nav_abilities"]):
            x = margin + i * (nw + nav_gap)
            self.nav_buttons.append(Button(x, _sc(6, s), nw, self.nav_h - _sc(12, s), loc[key], self.font))

        chat_w = w - 2 * margin
        self.chat_rect = pygame.Rect(margin, self.chat_y, chat_w, self.chat_h)
        self.chat_lines: List[str] = []
        self.chat_scroll = 0
        self._chat_scroll_dragging = False

        send_w = _sc(130, s)
        input_w = chat_w - send_w - nav_gap
        self.input_rect = pygame.Rect(margin, self.input_y, input_w, self.input_h)
        self.input_active = False
        self.input_buffer = ""
        self.send_btn = Button(
            self.input_rect.right + nav_gap, self.input_y,
            send_w, self.input_h,
            loc["chat_send"], self.font
        )

        qw = (chat_w - 2 * nav_gap) // 3
        self.quick_buttons = [
            Button(margin, self.quick_y, qw, self.quick_h, loc["quick_hide"], self.font),
            Button(margin + qw + nav_gap, self.quick_y, qw, self.quick_h, loc["quick_look"], self.font),
            Button(margin + 2 * (qw + nav_gap), self.quick_y, qw, self.quick_h, loc["quick_rest"], self.font),
        ]

    def _chat_max_scroll(self) -> int:
        total = len(self.chat_lines) * self.line_h
        return max(0, total - self.chat_rect.height)

    def _chat_scrollbar_rects(self) -> tuple:
        mx = self._chat_max_scroll()
        if mx <= 0:
            return (None, None)
        rx = self.chat_rect.right - SB_W - SB_PAD
        track = pygame.Rect(rx, self.chat_rect.y + SB_PAD, SB_W, self.chat_rect.height - 2 * SB_PAD)
        vis = self.chat_rect.height / max(1, len(self.chat_lines) * self.line_h)
        th = max(24, int(track.height * vis))
        ty = track.y + int((self.chat_scroll / mx) * (track.height - th))
        thumb = pygame.Rect(rx, ty, SB_W, th)
        return (track, thumb)

    def handle_event(self, event: pygame.event.Event) -> Union[str, None]:
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            return "title"

        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            if self.nav_buttons[0].is_clicked(pos):
                return "inventory"
            if self.nav_buttons[2].is_clicked(pos):
                return "journal"
            if self.nav_buttons[3].is_clicked(pos):
                return "character"
            if self.nav_buttons[4].is_clicked(pos):
                return "abilities"
            if self.send_btn.is_clicked(pos):
                self._on_send()
                return None
            if self.input_rect.collidepoint(pos):
                self.input_active = True
                return None
            self.input_active = False
            if self.chat_rect.collidepoint(pos) and pos[0] >= self.chat_rect.right - SB_W - SB_PAD:
                mx = self._chat_max_scroll()
                if mx > 0:
                    track, thumb = self._chat_scrollbar_rects()
                    if thumb and thumb.collidepoint(pos):
                        self._chat_scroll_dragging = True

        if event.type == pygame.MOUSEBUTTONUP and event.button == 1:
            self._chat_scroll_dragging = False

        if event.type == pygame.MOUSEMOTION and self._chat_scroll_dragging:
            mx = self._chat_max_scroll()
            if mx > 0:
                track, thumb = self._chat_scrollbar_rects()
                if track and thumb:
                    r = (event.pos[1] - track.y) / (track.height - thumb.height) if track.height > thumb.height else 0
                    r = max(0, min(1, r))
                    self.chat_scroll = int(r * mx)

        if event.type == pygame.MOUSEWHEEL and self.chat_rect.collidepoint(pygame.mouse.get_pos()):
            mx = self._chat_max_scroll()
            if mx > 0:
                step = 36
                if event.y > 0:
                    self.chat_scroll = max(0, self.chat_scroll - step)
                else:
                    self.chat_scroll = min(mx, self.chat_scroll + step)
            return None

        if event.type == pygame.KEYDOWN and self.input_active:
            if event.key == pygame.K_RETURN:
                self._on_send()
            elif event.key == pygame.K_BACKSPACE:
                self.input_buffer = self.input_buffer[:-1]
            elif event.unicode and len(self.input_buffer) < 500:
                self.input_buffer += event.unicode
            return None

        return None

    def _on_send(self):
        if not self.input_buffer.strip():
            return
        self.chat_lines.append(f"[Вы]: {self.input_buffer.strip()}")
        self.input_buffer = ""
        mx = self._chat_max_scroll()
        self.chat_scroll = mx

    def update(self):
        pos = pygame.mouse.get_pos()
        for b in self.nav_buttons:
            b.update(pos)
        self.send_btn.update(pos)
        for b in self.quick_buttons:
            b.update(pos)

    def draw(self):
        self.screen.fill(BLACK)

        # Nav bar
        nav_rect = pygame.Rect(0, 0, self._w, self.nav_h)
        pygame.draw.rect(self.screen, DARK_GRAY, nav_rect)
        pygame.draw.line(self.screen, GOLD, (0, self.nav_h), (self._w, self.nav_h), 2)
        for b in self.nav_buttons:
            b.draw(self.screen)

        # Chat area
        pygame.draw.rect(self.screen, MODAL_BG, self.chat_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, self.chat_rect, width=2, border_radius=8)

        clip_save = self.screen.get_clip()
        self.screen.set_clip(self.chat_rect)
        pad = 12
        y = self.chat_rect.y + pad - self.chat_scroll
        for line in self.chat_lines:
            if y + self.line_h > self.chat_rect.y and y < self.chat_rect.bottom:
                s = self.small_font.render(line[:120], True, LIGHT_GRAY)
                self.screen.blit(s, (self.chat_rect.x + pad, y))
            y += self.line_h
        self.screen.set_clip(clip_save)

        mx = self._chat_max_scroll()
        if mx > 0:
            track, thumb = self._chat_scrollbar_rects()
            if track and thumb:
                pygame.draw.rect(self.screen, DARK_GRAY, track, border_radius=4)
                pygame.draw.rect(self.screen, GOLD, thumb, border_radius=4)

        # Input
        pygame.draw.rect(self.screen, INPUT_BG, self.input_rect, border_radius=6)
        bc = GOLD if self.input_active else LIGHT_GRAY
        pygame.draw.rect(self.screen, bc, self.input_rect, width=2, border_radius=6)
        txt = self.input_buffer or loc["chat_input_placeholder"]
        col = WHITE if self.input_buffer else LIGHT_GRAY
        s = self.font.render(txt[:80], True, col)
        self.screen.blit(s, (self.input_rect.x + 10, self.input_rect.centery - s.get_height() // 2))
        self.send_btn.draw(self.screen)

        # Quick actions
        for b in self.quick_buttons:
            b.draw(self.screen)
