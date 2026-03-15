"""
Social screen – NPC dialogue, Pathfinder / Baldur's Gate style.

All LLM logic lives in core.gameplay.social_interaction (run_social).
This file handles only pygame layout, rendering, threading glue, and event routing.

Layout:  NPC portrait (left) | dialogue chat (center) | player portrait (right).
Bottom:  action buttons (Trade / Attack / Leave).

Threading:
  _social_thread  – background thread running run_social()
  _ui_queue       – social → screen  (scene, npc_reply, options, thinking, transition…)
  _input_queue    – screen → social  (player input / resume)
  _stop_event     – set to abort the thread

update() drains _ui_queue each frame and returns a transition string or None.
"""
from __future__ import annotations

import os
import queue
import threading
from dataclasses import dataclass
from enum import Enum
from typing import List, Optional, TYPE_CHECKING, Union

import pygame

from .base_screen import BaseScreen
from ..colors import *
from ..components import Button
from core.entities.base import ID
from core.gameplay.social_interaction import SocialState, generate_social_summary_async

if TYPE_CHECKING:
    from core.entities.npc import NPC

SB_W = 12
SB_PAD = 4
PORTRAIT_W_RATIO = 0.18
PORTRAIT_H_RATIO = 0.40
BTN_H_RATIO = 0.07


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


# ── Chat entry types ─────────────────────────────────────────────────────────

class ChatRole(Enum):
    GREETING = "greeting"   # DM scene narration at start
    NPC      = "npc"        # NPC in-character line
    PLAYER   = "player"     # player's own words
    OPTION   = "option"     # suggested player response
    QUESTION = "question"   # GM clarification
    SYSTEM   = "system"     # engine notices
    THINKING = "thinking"   # loading indicator


_ROLE_COLORS = {
    ChatRole.GREETING: (200, 185, 100),   # warm amber — DM narration
    ChatRole.NPC:      (255, 210, 80),    # bright gold — NPC speech
    ChatRole.PLAYER:   (220, 220, 220),   # near-white
    ChatRole.OPTION:   (130, 210, 130),   # soft green — options
    ChatRole.QUESTION: (130, 190, 220),   # light blue — GM question
    ChatRole.SYSTEM:   (150, 150, 150),   # gray
    ChatRole.THINKING: (80,  80,  80),    # dim
}


@dataclass
class ChatEntry:
    text: str
    role: ChatRole


# ── Screen ───────────────────────────────────────────────────────────────────

class SocialScreen(BaseScreen):
    """
    Dialogue screen with an NPC.
    Call set_npc(npc_id) then start_social(api_manager) before switching to it.
    """

    def __init__(self, screen: pygame.Surface):
        super().__init__(screen)
        self._state          = SocialState()
        self._portrait_cache: dict = {}

        # Chat entries (replaces flat string list)
        self._chat_entries: List[ChatEntry] = []

        # UI scroll state
        self._chat_scroll: int = 0
        self._chat_scroll_dragging: bool = False

        # Input
        self._input_buffer: str = ""
        self._input_active: bool = True

        # Threading
        self._api_manager    = None
        self._ui_queue:    queue.Queue = queue.Queue()
        self._input_queue: queue.Queue = queue.Queue()
        self._stop_event:  threading.Event = threading.Event()
        self._social_thread: Optional[threading.Thread] = None

        self._build_layout()

    # --------------------------------------------------
    # PUBLIC API
    # --------------------------------------------------

    def set_npc(self, npc_id: ID) -> None:
        """Set the NPC for the upcoming conversation (does NOT start the thread)."""
        self._state.reset(npc_id)
        self._chat_entries.clear()
        self._chat_scroll = 0

    def start_social(self, api_manager) -> None:
        """Start or resume the social background thread.

        If the thread is alive (paused at a 'trade' transition), send a resume signal.
        Otherwise start a fresh thread.
        """
        self._api_manager = api_manager

        # Thread alive → paused after trade transition; resume it
        if self._social_thread and self._social_thread.is_alive():
            self._input_queue.put({"type": "resume"})
            return

        # Fresh start
        self._stop_event.set()
        while not self._ui_queue.empty():
            try:
                self._ui_queue.get_nowait()
            except queue.Empty:
                break
        while not self._input_queue.empty():
            try:
                self._input_queue.get_nowait()
            except queue.Empty:
                break

        self._stop_event  = threading.Event()
        self._ui_queue    = queue.Queue()
        self._input_queue = queue.Queue()

        import core.data as game_data
        from core.gameplay.social_interaction import run_social

        gs = game_data.game_state
        npc_id = self._state.npc_id
        if gs is None or npc_id is None:
            self._add_entry("[Система]: не задан NPC или игровое состояние.", ChatRole.SYSTEM)
            return

        self._social_thread = threading.Thread(
            target=run_social,
            args=(api_manager, gs, str(npc_id), self._ui_queue, self._input_queue, self._stop_event),
            daemon=True,
            name="social",
        )
        self._social_thread.start()

    # --------------------------------------------------
    # LAYOUT
    # --------------------------------------------------

    def _build_layout(self) -> None:
        s = self._scale
        w, h = self._w, self._h

        self.font       = pygame.font.Font(None, _sc(26, s))
        self.small_font = pygame.font.Font(None, _sc(22, s))
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
        self._chat_rect  = pygame.Rect(chat_x, content_top, chat_w, chat_h)

        input_y  = content_top + chat_h + send_gap
        input_w  = chat_w - send_w - send_gap
        self._input_rect = pygame.Rect(chat_x, input_y, input_w, input_h)
        self._send_btn   = Button(
            chat_x + input_w + send_gap, input_y,
            send_w, input_h, "Сказать", self.font
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
    # CHAT HELPERS
    # --------------------------------------------------

    def _add_entry(self, text: str, role: ChatRole) -> None:
        text = text.replace(r'\n', '\n')
        self._chat_entries.append(ChatEntry(text, role))
        self._chat_scroll = self._chat_max_scroll()

    def _wrap_text(self, text: str, max_w: int) -> List[str]:
        lines: List[str] = []
        for paragraph in text.split("\n"):
            words = paragraph.split()
            if not words:
                lines.append("")
                continue
            cur = ""
            for word in words:
                trial = (cur + " " + word).strip() if cur else word
                if self.small_font.size(trial)[0] <= max_w:
                    cur = trial
                else:
                    if cur:
                        lines.append(cur)
                    cur = word
            if cur:
                lines.append(cur)
        return lines or [""]

    def _all_wrapped_lines(self, max_w: int) -> List[tuple]:
        result = []
        for entry in self._chat_entries:
            for line in self._wrap_text(entry.text, max_w):
                result.append((line, entry.role))
        return result

    def _chat_max_scroll(self) -> int:
        pad   = self._chat_pad
        max_w = self._chat_rect.w - 2 * pad - SB_W - SB_PAD - 4
        total = len(self._all_wrapped_lines(max_w)) * self._line_h
        return max(0, total - (self._chat_rect.height - 2 * pad))

    def _chat_scrollbar_rects(self):
        mx = self._chat_max_scroll()
        if mx <= 0:
            return None, None
        pad   = self._chat_pad
        max_w = self._chat_rect.w - 2 * pad - SB_W - SB_PAD - 4
        n     = len(self._all_wrapped_lines(max_w))
        total = n * self._line_h
        rx    = self._chat_rect.right - SB_W - SB_PAD
        track = pygame.Rect(rx, self._chat_rect.y + SB_PAD,
                            SB_W, self._chat_rect.height - 2 * SB_PAD)
        vis   = self._chat_rect.height / max(1, total)
        th    = max(20, int(track.height * vis))
        ty    = track.y + int((self._chat_scroll / mx) * (track.height - th))
        return track, pygame.Rect(rx, ty, SB_W, th)

    # --------------------------------------------------
    # QUEUE DRAIN
    # --------------------------------------------------

    def _drain_social_queue(self) -> Optional[str]:
        """Process all pending messages. Returns a transition string or None."""
        transition: Optional[str] = None
        while True:
            try:
                msg = self._ui_queue.get_nowait()
            except queue.Empty:
                break

            t = msg.get("type")

            # Any real content clears the thinking indicator
            if t in ("greeting", "npc_reply", "options", "question", "error", "resume"):
                self._chat_entries = [e for e in self._chat_entries
                                      if e.role != ChatRole.THINKING]

            if t == "greeting":
                self._add_entry(msg["text"], ChatRole.GREETING)
            elif t == "npc_reply":
                self._add_entry(msg["text"], ChatRole.NPC)
            elif t == "question":
                self._add_entry(msg["text"], ChatRole.QUESTION)
            elif t == "options":
                for o in msg.get("options", []):
                    self._add_entry(f"{o['id']}. {o['text']}", ChatRole.OPTION)
            elif t == "thinking":
                self._chat_entries = [e for e in self._chat_entries
                                      if e.role != ChatRole.THINKING]
                self._add_entry("НПС думает…", ChatRole.THINKING)
            elif t == "resume":
                pass  # thinking already cleared; actions follow shortly
            elif t == "error":
                self._add_entry(msg["text"], ChatRole.SYSTEM)
            elif t == "transition":
                self._chat_entries = [e for e in self._chat_entries
                                      if e.role != ChatRole.THINKING]
                action  = msg.get("action", "")
                npc_id  = msg.get("npc_id")
                room_id = msg.get("room_id")
                if action == "trade" and npc_id:
                    transition = f"trade:{npc_id}"
                elif action in ("exploration", "change_current_room"):
                    transition = "exploration"
                elif action == "combat":
                    transition = "combat"
        return transition

    # --------------------------------------------------
    # SUMMARY ON MANUAL LEAVE
    # --------------------------------------------------

    def _trigger_summary_on_leave(self) -> None:
        """Reconstruct dialogue history from chat entries and generate summary async."""
        import core.data as _gd
        gs = _gd.game_state
        npc_id = self._state.npc_id
        if gs is None or npc_id is None or self._api_manager is None:
            return

        # Reconstruct history list from visible chat entries (skip options/thinking/system)
        history: List[str] = []
        for entry in self._chat_entries:
            if entry.role == ChatRole.GREETING:
                history.append(f"СЦЕНА: {entry.text}")
            elif entry.role == ChatRole.NPC:
                history.append(f"НПС: {entry.text}")
            elif entry.role == ChatRole.PLAYER:
                # strip the "[Вы]: " prefix added in _on_send
                text = entry.text
                if text.startswith("[Вы]: "):
                    text = text[len("[Вы]: "):]
                history.append(f"ИГРОК: {text}")
            elif entry.role == ChatRole.QUESTION:
                history.append(f"GM: {entry.text}")

        if not history:
            return  # nothing happened, no need to summarise

        generate_social_summary_async(self._api_manager, gs, str(npc_id), history)

    # --------------------------------------------------
    # INPUT
    # --------------------------------------------------

    def _on_send(self) -> None:
        text = self._input_buffer.strip()
        if not text:
            return
        self._add_entry(f"[Вы]: {text}", ChatRole.PLAYER)
        self._input_buffer = ""
        if self._social_thread and self._social_thread.is_alive():
            self._input_queue.put({"type": "input", "text": text})

    # --------------------------------------------------
    # PORTRAIT HELPER
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
    # EVENT HANDLER
    # --------------------------------------------------

    def handle_event(self, event: pygame.event.Event) -> Union[str, None]:
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self._stop_event.set()
                self._trigger_summary_on_leave()
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

            # Trade button — hand off to LLM if possible, else manual
            if self._action_buttons[0].is_clicked(pos):
                npc_id = self._state.npc_id
                if npc_id is not None:
                    return f"trade:{npc_id}"
                self._add_entry("[Система]: нет NPC для торговли.", ChatRole.SYSTEM)
                return None

            # Attack button (stub)
            if self._action_buttons[1].is_clicked(pos):
                self._add_entry("[Система]: бой пока не реализован.", ChatRole.SYSTEM)
                return None

            # Leave button — stop thread, save summary, return to main
            if self._action_buttons[2].is_clicked(pos):
                self._stop_event.set()
                self._trigger_summary_on_leave()
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

    # --------------------------------------------------
    # UPDATE  (drains queue; returns transition or None)
    # --------------------------------------------------

    def update(self) -> Optional[str]:
        pos = pygame.mouse.get_pos()
        for b in self._action_buttons:
            b.update(pos)
        self._send_btn.update(pos)
        return self._drain_social_queue()

    # --------------------------------------------------
    # DRAW
    # --------------------------------------------------

    def draw(self) -> None:
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

        pad   = self._chat_pad
        max_w = self._chat_rect.w - 2 * pad - SB_W - SB_PAD - 4
        lines = self._all_wrapped_lines(max_w)

        clip_save = self.screen.get_clip()
        self.screen.set_clip(self._chat_rect)
        y = self._chat_rect.y + pad - self._chat_scroll
        for text, role in lines:
            if self._chat_rect.y < y + self._line_h and y < self._chat_rect.bottom:
                color = _ROLE_COLORS.get(role, LIGHT_GRAY)
                surf  = self.small_font.render(text, True, color)
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

        # Divider + buttons
        div_y = self._btn_y - _sc(6, s)
        pygame.draw.line(self.screen, GOLD,
                         (_sc(16, s), div_y), (self._w - _sc(16, s), div_y), 1)
        for b in self._action_buttons:
            b.draw(self.screen)
