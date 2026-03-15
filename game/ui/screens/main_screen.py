"""
Main game screen – chat, nav, quick actions.

Exploration runs in a background thread (core.gameplay.exploration.run_exploration).
Thread ↔ screen communicate via two thread-safe queues:
  _ui_queue    – exploration sends scene / narration / action lists / transitions
  _input_queue – screen sends player text to exploration

update() drains _ui_queue each frame and returns a transition string when
the exploration thread signals a mode change (social, trade, change_current_room).
"""

from __future__ import annotations

import queue
import threading
from dataclasses import dataclass
from enum import Enum
from typing import List, Optional, Union

import pygame

from .base_screen import BaseScreen
from ..colors import *
from ..components import Button
from localization import loc

SB_W = 12
SB_PAD = 4


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


# ── Chat entry types ────────────────────────────────────────────────────────

class ChatRole(Enum):
    PLAYER   = "player"    # white – player's own words
    DM       = "dm"        # warm amber – DM narration / scene
    ACTION   = "action"    # soft green – numbered action choices
    QUESTION = "question"  # light blue – DM asks for clarification
    SYSTEM   = "system"    # medium gray – engine notices
    THINKING = "thinking"  # dim – "DM is thinking…"


_ROLE_COLORS = {
    ChatRole.PLAYER:   (220, 220, 220),
    ChatRole.DM:       (220, 195, 110),
    ChatRole.ACTION:   (130, 210, 130),
    ChatRole.QUESTION: (130, 190, 220),
    ChatRole.SYSTEM:   (150, 150, 150),
    ChatRole.THINKING: (80,  80,  80),
}


@dataclass
class ChatEntry:
    text: str
    role: ChatRole


# ── Screen ──────────────────────────────────────────────────────────────────

class MainScreen(BaseScreen):
    """Main game screen: nav bar, chat area, input, quick actions."""

    def __init__(self, screen: pygame.Surface):
        super().__init__(screen)
        s = self._scale
        w, h = self._w, self._h

        self.font       = pygame.font.Font(None, _sc(26, s))
        self.small_font = pygame.font.Font(None, _sc(22, s))

        self.nav_h   = _sc(48, s)
        pad          = _sc(8, s)
        input_h      = _sc(44, s)
        quick_h      = _sc(48, s)
        self.chat_y  = self.nav_h + pad
        self.chat_h  = h - self.nav_h - pad - (input_h + pad) - (quick_h + pad) - pad
        self.input_y = self.chat_y + self.chat_h + pad
        self.input_h = input_h
        self.quick_y = self.input_y + self.input_h + pad
        self.quick_h = quick_h
        self.line_h  = _sc(24, s)

        margin   = _sc(16, s)
        nav_gap  = _sc(10, s)
        nw = (w - 2 * margin - 5 * nav_gap) // 5
        self.nav_buttons: List[Button] = []
        for i, key in enumerate(["nav_inventory", "nav_map", "nav_journal",
                                  "nav_character", "nav_abilities"]):
            x = margin + i * (nw + nav_gap)
            self.nav_buttons.append(
                Button(x, _sc(6, s), nw, self.nav_h - _sc(12, s), loc[key], self.font)
            )

        chat_w       = w - 2 * margin
        self.chat_rect = pygame.Rect(margin, self.chat_y, chat_w, self.chat_h)
        self.chat_scroll   = 0
        self._chat_scroll_dragging = False

        send_w  = _sc(130, s)
        input_w = chat_w - send_w - nav_gap
        self.input_rect = pygame.Rect(margin, self.input_y, input_w, self.input_h)
        self.input_active  = True
        self.input_buffer  = ""
        self.send_btn = Button(
            self.input_rect.right + nav_gap, self.input_y,
            send_w, self.input_h, loc["chat_send"], self.font
        )

        qw = (chat_w - 2 * nav_gap) // 3
        self.quick_buttons = [
            Button(margin,                       self.quick_y, qw, self.quick_h, loc["quick_hide"], self.font),
            Button(margin + qw + nav_gap,        self.quick_y, qw, self.quick_h, loc["quick_look"], self.font),
            Button(margin + 2*(qw + nav_gap),    self.quick_y, qw, self.quick_h, loc["quick_rest"], self.font),
        ]

        # ── Chat entry list (replaces plain string list) ──────────────
        self.chat_entries: List[ChatEntry] = []

        # ── Exploration threading ──────────────────────────────────────
        self._api_manager    = None   # set by start_exploration()
        self._ui_queue:    queue.Queue = queue.Queue()
        self._input_queue: queue.Queue = queue.Queue()
        self._stop_event:  threading.Event = threading.Event()
        self._exploration_thread: Optional[threading.Thread] = None
        self._pending_transition: Optional[str] = None

    # ------------------------------------------------------------------
    # EXPLORATION LIFECYCLE
    # ------------------------------------------------------------------

    def start_exploration(self, api_manager) -> None:
        """Start or resume the exploration background thread.

        If the thread is alive (paused at a social/trade transition), send a
        ``resume`` signal so it continues without re-running describe_scene.
        Otherwise perform a fresh start (new character, room change, combat).
        """
        self._api_manager = api_manager

        # Thread is alive → it paused waiting for resume (social/trade transition)
        if self._exploration_thread and self._exploration_thread.is_alive():
            self._input_queue.put({"type": "resume"})
            return

        # Fresh start: cancel any lingering old thread and clear stale data
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

        self._stop_event   = threading.Event()
        self._ui_queue     = queue.Queue()
        self._input_queue  = queue.Queue()
        self._pending_transition = None

        import core.data as game_data
        from core.gameplay.exploration import run_exploration

        gs = game_data.game_state
        if gs is None:
            self._add_entry("[Система]: игровое состояние не загружено.", ChatRole.SYSTEM)
            return

        self._exploration_thread = threading.Thread(
            target=run_exploration,
            args=(api_manager, gs, self._ui_queue, self._input_queue, self._stop_event),
            daemon=True,
            name="exploration",
        )
        self._exploration_thread.start()

    # ------------------------------------------------------------------
    # CHAT HELPERS
    # ------------------------------------------------------------------

    def _add_entry(self, text: str, role: ChatRole) -> None:
        # Normalise literal \n escape sequences (sometimes returned by LLM JSON)
        # into real newline characters so _wrap_text can split on them.
        text = text.replace(r'\n', '\n')
        self.chat_entries.append(ChatEntry(text, role))
        self.chat_scroll = self._chat_max_scroll()

    def _wrap_text(self, text: str, max_w: int) -> List[str]:
        """Word-wrap a single string to fit within max_w pixels."""
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
        """Return [(text_line, ChatRole)] for all entries, word-wrapped."""
        result = []
        for entry in self.chat_entries:
            wrapped = self._wrap_text(entry.text, max_w)
            for line in wrapped:
                result.append((line, entry.role))
        return result

    def _chat_max_scroll(self) -> int:
        pad    = 12
        max_w  = self.chat_rect.w - 2 * pad - SB_W - SB_PAD - 4
        total  = len(self._all_wrapped_lines(max_w)) * self.line_h
        return max(0, total - self.chat_rect.height + 2 * pad)

    def _chat_scrollbar_rects(self) -> tuple:
        mx = self._chat_max_scroll()
        if mx <= 0:
            return None, None
        pad    = 12
        max_w  = self.chat_rect.w - 2 * pad - SB_W - SB_PAD - 4
        n      = len(self._all_wrapped_lines(max_w))
        total  = n * self.line_h
        rx     = self.chat_rect.right - SB_W - SB_PAD
        track  = pygame.Rect(rx, self.chat_rect.y + SB_PAD,
                             SB_W, self.chat_rect.height - 2 * SB_PAD)
        vis    = self.chat_rect.height / max(1, total)
        th     = max(24, int(track.height * vis))
        ty     = track.y + int((self.chat_scroll / mx) * (track.height - th))
        return track, pygame.Rect(rx, ty, SB_W, th)

    # ------------------------------------------------------------------
    # EXPLORATION QUEUE DRAIN
    # ------------------------------------------------------------------

    def _drain_exploration_queue(self) -> Optional[str]:
        """
        Process all pending messages from the exploration thread.
        Returns a transition string if the thread signals a mode change, else None.
        """
        transition: Optional[str] = None
        while True:
            try:
                msg = self._ui_queue.get_nowait()
            except queue.Empty:
                break

            t = msg.get("type")

            # Any real content clears the thinking indicator
            if t in ("scene", "narration", "question", "actions", "error", "resume"):
                self.chat_entries = [e for e in self.chat_entries
                                     if e.role != ChatRole.THINKING]

            if t == "scene":
                self._add_entry(msg["text"], ChatRole.DM)
            elif t == "narration":
                self._add_entry(msg["text"], ChatRole.DM)
            elif t == "question":
                self._add_entry(msg["text"], ChatRole.QUESTION)
            elif t == "actions":
                for a in msg.get("actions", []):
                    self._add_entry(f"{a['id']}. {a['description']}", ChatRole.ACTION)
            elif t == "thinking":
                # Replace previous thinking entry to avoid clutter
                self.chat_entries = [e for e in self.chat_entries
                                     if e.role != ChatRole.THINKING]
                self._add_entry("Мастер думает…", ChatRole.THINKING)
            elif t == "resume":
                # Thread resumed after social/trade — no visible message needed
                pass
            elif t == "error":
                self._add_entry(msg["text"], ChatRole.SYSTEM)
            elif t == "transition":
                self.chat_entries = [e for e in self.chat_entries
                                     if e.role != ChatRole.THINKING]
                action  = msg.get("action", "")
                npc_id  = msg.get("npc_id")
                room_id = msg.get("room_id")
                if action in ("social", "trade") and npc_id:
                    transition = f"{action}:{npc_id}"
                elif action == "change_current_room":
                    # room_id already updated in exploration.py; just restart
                    transition = "restart_exploration"
                elif action == "combat":
                    transition = "combat"
        return transition

    # ------------------------------------------------------------------
    # SEND
    # ------------------------------------------------------------------

    def _on_send(self) -> None:
        text = self.input_buffer.strip()
        if not text:
            return
        self._add_entry(f"[Вы]: {text}", ChatRole.PLAYER)
        self.input_buffer = ""
        # Forward to exploration thread if running
        if self._exploration_thread and self._exploration_thread.is_alive():
            self._input_queue.put({"type": "input", "text": text})

    # ------------------------------------------------------------------
    # HANDLE EVENTS
    # ------------------------------------------------------------------

    def handle_event(self, event: pygame.event.Event) -> Union[str, None]:
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            return "title"

        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            if self.nav_buttons[0].is_clicked(pos): return "inventory"
            if self.nav_buttons[1].is_clicked(pos): return "map"
            if self.nav_buttons[2].is_clicked(pos): return "journal"
            if self.nav_buttons[3].is_clicked(pos): return "character"
            if self.nav_buttons[4].is_clicked(pos): return "abilities"
            if self.send_btn.is_clicked(pos):
                self._on_send()
                return None
            if self.input_rect.collidepoint(pos):
                self.input_active = True
                return None
            self.input_active = False
            # Scrollbar drag
            if self.chat_rect.collidepoint(pos) and pos[0] >= self.chat_rect.right - SB_W - SB_PAD:
                mx = self._chat_max_scroll()
                if mx > 0:
                    _, thumb = self._chat_scrollbar_rects()
                    if thumb and thumb.collidepoint(pos):
                        self._chat_scroll_dragging = True

        if event.type == pygame.MOUSEBUTTONUP and event.button == 1:
            self._chat_scroll_dragging = False

        if event.type == pygame.MOUSEMOTION and self._chat_scroll_dragging:
            mx = self._chat_max_scroll()
            if mx > 0:
                track, thumb = self._chat_scrollbar_rects()
                if track and thumb:
                    r = (event.pos[1] - track.y) / (track.height - thumb.height) \
                        if track.height > thumb.height else 0
                    self.chat_scroll = int(max(0, min(1, r)) * mx)

        if event.type == pygame.MOUSEWHEEL and self.chat_rect.collidepoint(pygame.mouse.get_pos()):
            mx = self._chat_max_scroll()
            step = self.line_h * 3
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

    # ------------------------------------------------------------------
    # UPDATE  (drains queue; returns transition string or None)
    # ------------------------------------------------------------------

    def update(self) -> Optional[str]:
        pos = pygame.mouse.get_pos()
        for b in self.nav_buttons:
            b.update(pos)
        self.send_btn.update(pos)
        for b in self.quick_buttons:
            b.update(pos)

        return self._drain_exploration_queue()

    # ------------------------------------------------------------------
    # DRAW
    # ------------------------------------------------------------------

    def draw(self) -> None:
        self.screen.fill(BLACK)

        # Nav bar
        nav_rect = pygame.Rect(0, 0, self._w, self.nav_h)
        pygame.draw.rect(self.screen, DARK_GRAY, nav_rect)
        pygame.draw.line(self.screen, GOLD, (0, self.nav_h), (self._w, self.nav_h), 2)
        for b in self.nav_buttons:
            b.draw(self.screen)

        # Chat area background
        pygame.draw.rect(self.screen, MODAL_BG, self.chat_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD,     self.chat_rect, width=2, border_radius=8)

        pad    = 12
        max_w  = self.chat_rect.w - 2 * pad - SB_W - SB_PAD - 4
        lines  = self._all_wrapped_lines(max_w)

        clip_save = self.screen.get_clip()
        self.screen.set_clip(self.chat_rect)
        y = self.chat_rect.y + pad - self.chat_scroll
        for text, role in lines:
            if y + self.line_h > self.chat_rect.y and y < self.chat_rect.bottom:
                color = _ROLE_COLORS.get(role, LIGHT_GRAY)
                surf  = self.small_font.render(text, True, color)
                self.screen.blit(surf, (self.chat_rect.x + pad, y))
            y += self.line_h
        self.screen.set_clip(clip_save)

        # Scrollbar
        mx = self._chat_max_scroll()
        if mx > 0:
            track, thumb = self._chat_scrollbar_rects()
            if track and thumb:
                pygame.draw.rect(self.screen, DARK_GRAY, track, border_radius=4)
                pygame.draw.rect(self.screen, GOLD,      thumb, border_radius=4)

        # Input
        pygame.draw.rect(self.screen, INPUT_BG, self.input_rect, border_radius=6)
        bc = GOLD if self.input_active else LIGHT_GRAY
        pygame.draw.rect(self.screen, bc, self.input_rect, width=2, border_radius=6)
        txt = self.input_buffer or loc["chat_input_placeholder"]
        col = WHITE if self.input_buffer else LIGHT_GRAY
        s = self.font.render(txt[:80], True, col)
        self.screen.blit(s, (self.input_rect.x + 10,
                             self.input_rect.centery - s.get_height() // 2))
        self.send_btn.draw(self.screen)

        # Quick actions
        for b in self.quick_buttons:
            b.draw(self.screen)
