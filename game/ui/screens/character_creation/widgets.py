"""Shared UI widgets for character creation and level-up screens."""
import pygame
from typing import List, Dict, Any, Optional

from ..colors import *

def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


class AbilityCounter:
    """Counter widget for ability scores"""
    
    def __init__(self, x: int, y: int, ability: str, label: str, font: pygame.font.Font):
        self.x = x
        self.y = y
        self.ability = ability
        self.label = label
        self.font = font
        self.small_font = pygame.font.Font(None, 24)
        
        # Buttons will be positioned dynamically in draw() based on label width
        self.minus_rect = pygame.Rect(0, 0, 0, 0)  # Will be set in draw()
        self.plus_rect = pygame.Rect(0, 0, 0, 0)  # Will be set in draw()
        self.value_rect = pygame.Rect(0, 0, 0, 0)  # Will be set in draw()
        
    def draw(self, surface: pygame.Surface, value: int, modifier: int, can_increase: bool, can_decrease: bool):
        """Draw the counter with adaptive positioning"""
        btn_size = 30
        gap = 10  # Gap between label and buttons
        
        # Label - compute width to position buttons after it
        label_surface = self.font.render(self.label, True, WHITE)
        label_width = label_surface.get_width()
        surface.blit(label_surface, (self.x, self.y + 5))
        
        # Position buttons after label with gap
        buttons_start_x = self.x + label_width + gap
        
        # Minus button
        self.minus_rect = pygame.Rect(buttons_start_x, self.y, btn_size, btn_size)
        minus_color = GOLD if can_decrease else DARK_GRAY
        pygame.draw.rect(surface, DARK_GRAY, self.minus_rect, border_radius=4)
        pygame.draw.rect(surface, minus_color, self.minus_rect, width=2, border_radius=4)
        minus_text = self.font.render("-", True, minus_color)
        surface.blit(minus_text, (self.minus_rect.centerx - 5, self.minus_rect.centery - 10))
        
        # Value
        self.value_rect = pygame.Rect(buttons_start_x + btn_size + 5, self.y, 40, btn_size)
        pygame.draw.rect(surface, INPUT_BG, self.value_rect, border_radius=4)
        value_text = self.font.render(str(value), True, WHITE)
        value_rect = value_text.get_rect(center=self.value_rect.center)
        surface.blit(value_text, value_rect)
        
        # Plus button
        self.plus_rect = pygame.Rect(buttons_start_x + btn_size + 5 + 40 + 5, self.y, btn_size, btn_size)
        plus_color = GOLD if can_increase else DARK_GRAY
        pygame.draw.rect(surface, DARK_GRAY, self.plus_rect, border_radius=4)
        pygame.draw.rect(surface, plus_color, self.plus_rect, width=2, border_radius=4)
        plus_text = self.font.render("+", True, plus_color)
        surface.blit(plus_text, (self.plus_rect.centerx - 5, self.plus_rect.centery - 10))
        
        # Modifier
        mod_str = f"+{modifier}" if modifier >= 0 else str(modifier)
        mod_color = DARK_GREEN if modifier > 0 else (DARK_RED if modifier < 0 else LIGHT_GRAY)
        mod_surface = self.font.render(f"({mod_str})", True, mod_color)
        surface.blit(mod_surface, (self.plus_rect.right + 10, self.y + 5))
        
    def handle_click(self, pos: tuple) -> Optional[str]:
        """Handle click, return 'increase' or 'decrease' or None"""
        if self.minus_rect.collidepoint(pos):
            return "decrease"
        if self.plus_rect.collidepoint(pos):
            return "increase"
        return None


class SelectionList:
    """Scrollable selection list with optional scrollbar and highlighted items"""
    
    SCROLLBAR_WIDTH = 12
    SCROLLBAR_PAD = 4
    
    def __init__(self, x: int, y: int, width: int, height: int, font: pygame.font.Font):
        self.rect = pygame.Rect(x, y, width, height)
        self.font = font
        self.items: List[Dict[str, Any]] = []
        self.selected_index: int = -1
        self.scroll_offset: int = 0
        self.item_height = 40
        self.hovered_index = -1
        self.selected_indices: Optional[set] = None  # set of item["index"] to highlight (e.g. chosen cantrips)
        self._scroll_dragging = False
        self._last_items_key: Optional[tuple] = None
        
    def set_items(self, items: List[Dict[str, Any]]):
        """Set list items. Preserves scroll if same items."""
        key = tuple((it.get("index", ""), it.get("name", "")) for it in items) if items else ()
        if key == self._last_items_key:
            return
        self._last_items_key = key
        self.items = items
        self.selected_index = -1
        self.scroll_offset = 0
        
    def get_selected(self) -> Optional[Dict[str, Any]]:
        """Get selected item"""
        if 0 <= self.selected_index < len(self.items):
            return self.items[self.selected_index]
        return None
        
    def get_item_at_pos(self, pos: tuple) -> Optional[Dict[str, Any]]:
        """Get item at screen position (for click-to-toggle)."""
        if not self.rect.collidepoint(pos):
            return None
        rel_y = pos[1] - self.rect.y + self.scroll_offset
        i = rel_y // self.item_height
        if 0 <= i < len(self.items):
            return self.items[i]
        return None
        
    def _max_scroll(self) -> int:
        return max(0, len(self.items) * self.item_height - self.rect.height)
        
    def _is_in_scrollbar(self, pos: tuple) -> bool:
        """True if pos is in the scrollbar strip (don't treat as item click)."""
        if self._max_scroll() <= 0:
            return False
        bar_left = self.rect.right - self.SCROLLBAR_WIDTH - self.SCROLLBAR_PAD
        return pos[0] >= bar_left
        
    def handle_event(self, event: pygame.event.Event) -> bool:
        """Handle events. Returns True if an item was clicked (for toggle)."""
        if event.type == pygame.MOUSEBUTTONDOWN:
            if event.button == 1:
                if self.rect.collidepoint(event.pos):
                    if self._is_in_scrollbar(event.pos):
                        tr, th = self._scrollbar_rects()
                        if th and th.collidepoint(event.pos):
                            self._scroll_dragging = True
                        return False
                    rel_y = event.pos[1] - self.rect.y + self.scroll_offset
                    idx = rel_y // self.item_height
                    if 0 <= idx < len(self.items):
                        self.selected_index = idx
                        return True
                self._scroll_dragging = False
            elif event.button in (4, 5) and self.rect.collidepoint(event.pos):
                mx = self._max_scroll()
                if mx > 0:
                    if event.button == 4:
                        self.scroll_offset = max(0, self.scroll_offset - 24)
                    else:
                        self.scroll_offset = min(mx, self.scroll_offset + 24)
        elif event.type == pygame.MOUSEBUTTONUP and event.button == 1:
            self._scroll_dragging = False
        elif event.type == pygame.MOUSEMOTION:
            if self._scroll_dragging:
                mx = self._max_scroll()
                if mx > 0:
                    track, thumb = self._scrollbar_rects()
                    if track and thumb:
                        rel = event.pos[1] - track.y
                        t = max(0, min(1, rel / (track.height - thumb.height))) if track.height > thumb.height else 0
                        self.scroll_offset = int(t * mx)
            elif self.rect.collidepoint(event.pos):
                rel_y = event.pos[1] - self.rect.y + self.scroll_offset
                self.hovered_index = rel_y // self.item_height
                if self.hovered_index < 0 or self.hovered_index >= len(self.items):
                    self.hovered_index = -1
            else:
                self.hovered_index = -1
        return False
        
    def _scrollbar_rects(self) -> tuple:
        """(track_rect, thumb_rect). Thumb None if no scroll."""
        mx = self._max_scroll()
        if mx <= 0:
            return (None, None)
        rx = self.rect.right - self.SCROLLBAR_WIDTH - self.SCROLLBAR_PAD
        track = pygame.Rect(rx, self.rect.y + self.SCROLLBAR_PAD, self.SCROLLBAR_WIDTH,
                            self.rect.height - 2 * self.SCROLLBAR_PAD)
        visible = self.rect.height / max(1, len(self.items) * self.item_height)
        thumb_h = max(24, int(track.height * visible))
        thumb_y = track.y + int((self.scroll_offset / mx) * (track.height - thumb_h))
        thumb = pygame.Rect(rx, thumb_y, self.SCROLLBAR_WIDTH, thumb_h)
        return (track, thumb)
        
    def draw(self, surface: pygame.Surface):
        """Draw the list. Uses selected_indices for extra highlight (e.g. chosen cantrips)."""
        pygame.draw.rect(surface, MODAL_BG, self.rect, border_radius=8)
        pygame.draw.rect(surface, GOLD, self.rect, width=2, border_radius=8)
        
        list_width = self.rect.width
        has_scroll = self._max_scroll() > 0
        if has_scroll:
            list_width -= self.SCROLLBAR_WIDTH + 2 * self.SCROLLBAR_PAD
        
        clip_rect = surface.get_clip()
        surface.set_clip(self.rect)
        
        for i, item in enumerate(self.items):
            y = self.rect.y + i * self.item_height - self.scroll_offset
            if y + self.item_height < self.rect.y or y > self.rect.bottom:
                continue
            item_rect = pygame.Rect(self.rect.x + 5, y + 2, list_width - 10, self.item_height - 4)
            is_sel = self.selected_indices and item.get("index") in self.selected_indices
            if i == self.selected_index:
                pygame.draw.rect(surface, DARK_GREEN, item_rect, border_radius=4)
            elif is_sel:
                pygame.draw.rect(surface, (80, 60, 20), item_rect, border_radius=4)
                pygame.draw.rect(surface, GOLD, item_rect, width=1, border_radius=4)
            elif i == self.hovered_index:
                pygame.draw.rect(surface, HOVER_COLOR, item_rect, border_radius=4)
            name = item.get("name", str(item))
            text_surface = self.font.render(name, True, GOLD if is_sel else WHITE)
            surface.blit(text_surface, (item_rect.x + 10, item_rect.centery - 10))
            
        surface.set_clip(clip_rect)
        
        if has_scroll:
            track, thumb = self._scrollbar_rects()
            if track and thumb:
                pygame.draw.rect(surface, DARK_GRAY, track, border_radius=4)
                pygame.draw.rect(surface, GOLD, thumb, border_radius=4)

