"""
Reusable UI components
"""

import pygame
from datetime import datetime as _datetime
from typing import Optional, List, Union
from .colors import *
from .layout import get_size, scale_factor
from localization import loc


class Tooltip:
    """Floating tooltip that appears on hover"""
    
    def __init__(self, max_width: int = 300):
        self.max_width = max_width
        self.font = pygame.font.Font(None, 24)
        self.title_font = pygame.font.Font(None, 28)
        self.padding = 10
        self.visible = False
        self.title: str = ""
        self.text: str = ""
        self.position = (0, 0)
        self._lines: List[str] = []
        self._surface: Optional[pygame.Surface] = None
        
    def show(self, title: str, text: str, pos: tuple):
        """Show tooltip at position"""
        self.title = title
        self.text = text
        self.position = pos
        self.visible = True
        self._build_surface()
        
    def hide(self):
        """Hide tooltip"""
        self.visible = False
        
    def _wrap_text(self, text: str, font: pygame.font.Font, max_width: int) -> List[str]:
        """Word-wrap text to fit max width"""
        words = text.split()
        lines = []
        current_line = ""
        
        for word in words:
            test_line = current_line + " " + word if current_line else word
            if font.size(test_line)[0] < max_width:
                current_line = test_line
            else:
                if current_line:
                    lines.append(current_line)
                current_line = word
        if current_line:
            lines.append(current_line)
        return lines
        
    def _build_surface(self):
        """Build the tooltip surface. Preserves \\n as paragraph breaks."""
        content_width = self.max_width - self.padding * 2
        self._lines = []
        for para in self.text.split("\n"):
            self._lines.extend(self._wrap_text(para.strip(), self.font, content_width))
        if not self._lines and self.text.strip():
            self._lines = self._wrap_text(self.text, self.font, content_width)
        
        # Calculate dimensions
        title_height = self.title_font.get_height() if self.title else 0
        text_height = len(self._lines) * (self.font.get_height() + 2)
        
        width = self.max_width
        height = self.padding * 2 + title_height + text_height + (10 if self.title else 0)
        
        # Create surface
        self._surface = pygame.Surface((width, height), pygame.SRCALPHA)
        
        # Background
        pygame.draw.rect(self._surface, (20, 20, 20, 240), 
                        (0, 0, width, height), border_radius=6)
        pygame.draw.rect(self._surface, GOLD, 
                        (0, 0, width, height), width=1, border_radius=6)
        
        y = self.padding
        
        # Title
        if self.title:
            title_surf = self.title_font.render(self.title, True, GOLD)
            self._surface.blit(title_surf, (self.padding, y))
            y += title_height + 10
            
        # Text lines
        for line in self._lines:
            line_surf = self.font.render(line, True, LIGHT_GRAY)
            self._surface.blit(line_surf, (self.padding, y))
            y += self.font.get_height() + 2
            
    def draw(self, surface: pygame.Surface):
        """Draw tooltip"""
        if not self.visible or not self._surface:
            return
            
        # Adjust position to stay on screen
        x, y = self.position
        tooltip_rect = self._surface.get_rect()
        
        # Offset from cursor
        x += 15
        y += 15
        
        # Keep on screen
        sw, sh = get_size(surface)
        if x + tooltip_rect.width > sw:
            x = sw - tooltip_rect.width - 5
        if y + tooltip_rect.height > sh:
            y = y - tooltip_rect.height - 30
            
        surface.blit(self._surface, (x, y))


class Button:
    """Universal button component"""
    
    def __init__(self, x: int, y: int, width: int, height: int, text: str, 
                 font: pygame.font.Font, color: tuple = None):
        self.rect = pygame.Rect(x, y, width, height)
        self.text = text
        self.font = font
        self.hovered = False
        self.custom_color = color
        self.enabled = True
        
    def draw(self, surface: pygame.Surface):
        """Draw the button"""
        # Priority: custom_color > hover > default
        if self.custom_color:
            bg_color = self.custom_color
        elif self.hovered and self.enabled:
            bg_color = HOVER_COLOR
        else:
            bg_color = DARK_GRAY
            
        pygame.draw.rect(surface, bg_color, self.rect, border_radius=8)
        # Use brighter/thicker border if custom_color is set (for level up indicator)
        if self.custom_color:
            # Bright yellow border with thicker width for level up indicator
            pygame.draw.rect(surface, (255, 255, 0), self.rect, width=3, border_radius=8)
        else:
            pygame.draw.rect(surface, GOLD, self.rect, width=2, border_radius=8)
        
        text_color = WHITE if self.enabled else LIGHT_GRAY
        text_surface = self.font.render(self.text, True, text_color)
        text_rect = text_surface.get_rect(center=self.rect.center)
        surface.blit(text_surface, text_rect)
        
    def update(self, mouse_pos: tuple):
        """Update button state"""
        self.hovered = self.rect.collidepoint(mouse_pos)
        
    def is_clicked(self, mouse_pos: tuple) -> bool:
        """Check if button was clicked"""
        return self.rect.collidepoint(mouse_pos) and self.enabled


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


class InputModal:
    """Modal window for text input"""
    
    def __init__(self, screen: pygame.Surface, title: str, placeholder: str = ""):
        self.screen = screen
        self.title = title
        self.placeholder = placeholder
        self.input_text = ""
        self.active = False
        self.result = None
        sw, sh = get_size(screen)
        s = scale_factor(screen)
        
        self.title_font = pygame.font.Font(None, _sc(48, s))
        self.input_font = pygame.font.Font(None, _sc(32, s))
        self.button_font = pygame.font.Font(None, _sc(36, s))
        
        self.width = _sc(600, s)
        self.height = _sc(250, s)
        self.x = (sw - self.width) // 2
        self.y = (sh - self.height) // 2
        self.modal_rect = pygame.Rect(self.x, self.y, self.width, self.height)
        
        self.input_rect = pygame.Rect(
            self.x + _sc(30, s),
            self.y + _sc(100, s),
            self.width - _sc(60, s),
            _sc(45, s)
        )
        
        bw, bh = _sc(120, s), _sc(45, s)
        btn_y = self.y + self.height - _sc(70, s)
        self.confirm_btn = Button(
            self.x + self.width // 2 - bw - _sc(20, s), btn_y,
            bw, bh, loc["confirm"], self.button_font
        )
        self.cancel_btn = Button(
            self.x + self.width // 2 + _sc(20, s), btn_y,
            bw, bh, loc["cancel"], self.button_font
        )
        
        self.cursor_visible = True
        self.cursor_timer = 0
        
    def show(self):
        """Show the modal"""
        self.active = True
        self.result = None
        self.input_text = ""
        
    def hide(self):
        """Hide the modal"""
        self.active = False
        
    def handle_event(self, event: pygame.event.Event) -> Union[str, None]:
        """Handle events"""
        if not self.active:
            return None
            
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mouse_pos = pygame.mouse.get_pos()
            
            if self.confirm_btn.is_clicked(mouse_pos):
                self.result = "confirm"
                self.active = False
                return self.result
                
            if self.cancel_btn.is_clicked(mouse_pos):
                self.result = "cancel"
                self.active = False
                return self.result
                
        elif event.type == pygame.KEYDOWN:
            if event.key == pygame.K_RETURN:
                self.result = "confirm"
                self.active = False
                return self.result
            elif event.key == pygame.K_ESCAPE:
                self.result = "cancel"
                self.active = False
                return self.result
            elif event.key == pygame.K_BACKSPACE:
                self.input_text = self.input_text[:-1]
            elif event.key == pygame.K_v and pygame.key.get_mods() & pygame.KMOD_CTRL:
                try:
                    clipboard = pygame.scrap.get(pygame.SCRAP_TEXT)
                    if clipboard:
                        self.input_text += clipboard.decode('utf-8').strip('\x00')
                except:
                    pass
            elif event.unicode and len(event.unicode) == 1:
                self.input_text += event.unicode
                
        return None
        
    def update(self):
        """Update modal state"""
        if not self.active:
            return
            
        mouse_pos = pygame.mouse.get_pos()
        self.confirm_btn.update(mouse_pos)
        self.cancel_btn.update(mouse_pos)
        
        self.cursor_timer += 1
        if self.cursor_timer >= 30:
            self.cursor_timer = 0
            self.cursor_visible = not self.cursor_visible
            
    def draw(self):
        """Draw the modal"""
        if not self.active:
            return
        sw, sh = get_size(self.screen)
        overlay = pygame.Surface((sw, sh))
        overlay.set_alpha(180)
        overlay.fill(BLACK)
        self.screen.blit(overlay, (0, 0))
        
        # Modal background
        pygame.draw.rect(self.screen, MODAL_BG, self.modal_rect, border_radius=12)
        pygame.draw.rect(self.screen, GOLD, self.modal_rect, width=2, border_radius=12)
        
        # Title
        title_surface = self.title_font.render(self.title, True, GOLD)
        title_rect = title_surface.get_rect(centerx=self.modal_rect.centerx, top=self.y + 25)
        self.screen.blit(title_surface, title_rect)
        
        # Input field
        pygame.draw.rect(self.screen, INPUT_BG, self.input_rect, border_radius=6)
        pygame.draw.rect(self.screen, LIGHT_GRAY, self.input_rect, width=1, border_radius=6)
        
        # Input text (masked)
        display_text = "*" * len(self.input_text) if self.input_text else self.placeholder
        text_color = WHITE if self.input_text else LIGHT_GRAY
        
        max_chars = 50
        if len(display_text) > max_chars:
            display_text = display_text[-max_chars:]
            
        input_surface = self.input_font.render(display_text, True, text_color)
        input_text_rect = input_surface.get_rect(
            midleft=(self.input_rect.left + 10, self.input_rect.centery)
        )
        self.screen.blit(input_surface, input_text_rect)
        
        # Cursor
        if self.cursor_visible:
            if self.input_text:
                cursor_x = input_text_rect.right + 2
            else:
                cursor_x = self.input_rect.left + 10
            cursor_y = self.input_rect.centery - 12
            pygame.draw.line(self.screen, WHITE, (cursor_x, cursor_y), (cursor_x, cursor_y + 24), 2)
        
        # Buttons
        self.confirm_btn.draw(self.screen)
        self.cancel_btn.draw(self.screen)


class SaveSlotsModal:
    """Modal with 10 save slots (save mode) or available saves (load mode)."""

    def __init__(self, screen: pygame.Surface):
        self.screen = screen
        self.active = False
        self.mode: str = "save"  # "save" | "load"
        self.result: Optional[tuple] = None  # ("save", i) | ("load", i) | None
        sw, sh = get_size(screen)
        s = scale_factor(screen)

        self.title_font = pygame.font.Font(None, _sc(42, s))
        self.slot_font = pygame.font.Font(None, _sc(28, s))
        self.button_font = pygame.font.Font(None, _sc(36, s))

        self.width = _sc(800, s)
        self.height = _sc(540, s)
        self.x = (sw - self.width) // 2
        self.y = (sh - self.height) // 2
        self.modal_rect = pygame.Rect(self.x, self.y, self.width, self.height)

        self.pad = _sc(24, s)
        self.gap = _sc(16, s)
        self.slot_h = _sc(44, s)
        self.col_w = (self.width - 2 * self.pad - self.gap) // 2
        self._slot_top = self.y + _sc(70, s)
        self._slot_gap = _sc(8, s)
        self._cancel_btn: Optional[Button] = None
        self._hovered_slot: Optional[int] = None

    def show(self, mode: str):
        self.active = True
        self.mode = mode
        self.result = None
        self._hovered_slot = None
        cw, ch = _sc(140, scale_factor(self.screen)), _sc(44, scale_factor(self.screen))
        self._cancel_btn = Button(
            self.x + self.width // 2 - cw // 2,
            self.y + self.height - _sc(60, scale_factor(self.screen)),
            cw, ch, loc["cancel"], self.button_font
        )

    def hide(self):
        self.active = False

    def _build_slots(self) -> "List[tuple[pygame.Rect, int]]":
        out: List[tuple] = []
        from core import data as game_data

        if self.mode == "save":
            for idx in range(10):
                row = idx % 5
                col = idx // 5
                rx = self.x + self.pad + col * (self.col_w + self.gap)
                ry = self._slot_top + row * (self.slot_h + self._slot_gap)
                r = pygame.Rect(rx, ry, self.col_w, self.slot_h)
                out.append((r, idx + 1))
        else:
            slots = game_data.MainGameState.list_saves()
            for i, (slot_i, _) in enumerate(slots):
                row = i % 5
                col = i // 5
                rx = self.x + self.pad + col * (self.col_w + self.gap)
                ry = self._slot_top + row * (self.slot_h + self._slot_gap)
                r = pygame.Rect(rx, ry, self.col_w, self.slot_h)
                out.append((r, slot_i))
        return out

    def _slot_label(self, slot_i: int, dt: Optional[_datetime] = None) -> str:
        base = loc["slot_n"].format(slot_i)
        if dt is not None:
            return f"{base} — {dt.strftime('%d.%m.%Y %H:%M')}"
        return base

    def handle_event(self, event: pygame.event.Event) -> Optional[tuple]:
        if not self.active or not self._cancel_btn:
            return None
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mouse_pos = event.pos
            slots = self._build_slots()
            for r, slot_i in slots:
                if r.collidepoint(mouse_pos):
                    self.result = (self.mode, slot_i)
                    self.hide()
                    return self.result
            if self._cancel_btn.is_clicked(mouse_pos):
                self.result = None
                self.hide()
                return None
        elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            self.result = None
            self.hide()
            return None
        return None

    def update(self):
        if not self.active:
            return
        mouse_pos = pygame.mouse.get_pos()
        slots = self._build_slots()
        self._hovered_slot = None
        for r, slot_i in slots:
            if r.collidepoint(mouse_pos):
                self._hovered_slot = slot_i
                break
        if self._cancel_btn:
            self._cancel_btn.update(mouse_pos)

    def draw(self):
        if not self.active or not self._cancel_btn:
            return
        from core import data as game_data
        sw, sh = get_size(self.screen)
        overlay = pygame.Surface((sw, sh))
        overlay.set_alpha(180)
        overlay.fill(BLACK)
        self.screen.blit(overlay, (0, 0))

        pygame.draw.rect(self.screen, MODAL_BG, self.modal_rect, border_radius=12)
        pygame.draw.rect(self.screen, GOLD, self.modal_rect, width=2, border_radius=12)

        title = loc["save_slots_title"] if self.mode == "save" else loc["load_slots_title"]
        title_surf = self.title_font.render(title, True, GOLD)
        title_rect = title_surf.get_rect(centerx=self.modal_rect.centerx, top=self.y + 22)
        self.screen.blit(title_surf, title_rect)

        existing = {i: dt for i, dt in game_data.MainGameState.list_saves()}
        slots = self._build_slots()

        if self.mode == "load" and not slots:
            no_surf = self.slot_font.render(loc["no_saves"], True, LIGHT_GRAY)
            no_rect = no_surf.get_rect(centerx=self.modal_rect.centerx, centery=self.y + self.height // 2 - 30)
            self.screen.blit(no_surf, no_rect)
        else:
            for r, slot_i in slots:
                dt = existing.get(slot_i)
                label = self._slot_label(slot_i, dt)
                bg = HOVER_COLOR if self._hovered_slot == slot_i else DARK_GRAY
                pygame.draw.rect(self.screen, bg, r, border_radius=6)
                pygame.draw.rect(self.screen, GOLD, r, width=1, border_radius=6)
                txt = self.slot_font.render(label, True, WHITE)
                tr = txt.get_rect(midleft=(r.left + 10, r.centery))
                self.screen.blit(txt, tr)

        self._cancel_btn.draw(self.screen)
