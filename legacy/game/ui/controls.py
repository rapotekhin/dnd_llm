"""
Advanced UI controls - Slider, Toggle, Dropdown
"""

import pygame
from .colors import *


class Slider:
    """Horizontal slider control"""
    
    def __init__(self, x: int, y: int, width: int, height: int, 
                 min_val: float = 0.0, max_val: float = 1.0, 
                 initial: float = 0.5, label: str = ""):
        self.rect = pygame.Rect(x, y, width, height)
        self.min_val = min_val
        self.max_val = max_val
        self.value = initial
        self.label = label
        self.dragging = False
        self.font = pygame.font.Font(None, 28)
        
        # Track and handle dimensions
        self.track_height = 8
        self.handle_radius = 12
        
    @property
    def normalized_value(self) -> float:
        """Get value normalized to 0-1 range"""
        return (self.value - self.min_val) / (self.max_val - self.min_val)
        
    @property
    def handle_x(self) -> int:
        """Get handle X position"""
        return int(self.rect.x + self.normalized_value * self.rect.width)
        
    def handle_event(self, event: pygame.event.Event) -> bool:
        """Handle events, return True if value changed"""
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mouse_pos = pygame.mouse.get_pos()
            # Check if click is on handle or track
            handle_rect = pygame.Rect(
                self.handle_x - self.handle_radius,
                self.rect.centery - self.handle_radius,
                self.handle_radius * 2,
                self.handle_radius * 2
            )
            if handle_rect.collidepoint(mouse_pos) or self.rect.collidepoint(mouse_pos):
                self.dragging = True
                return self._update_value_from_mouse(mouse_pos[0])
                
        elif event.type == pygame.MOUSEBUTTONUP and event.button == 1:
            self.dragging = False
            
        elif event.type == pygame.MOUSEMOTION and self.dragging:
            return self._update_value_from_mouse(event.pos[0])
            
        return False
        
    def _update_value_from_mouse(self, mouse_x: int) -> bool:
        """Update value based on mouse X position"""
        old_value = self.value
        normalized = (mouse_x - self.rect.x) / self.rect.width
        normalized = max(0, min(1, normalized))
        self.value = self.min_val + normalized * (self.max_val - self.min_val)
        return old_value != self.value
        
    def draw(self, surface: pygame.Surface):
        """Draw the slider"""
        # Label
        if self.label:
            label_surface = self.font.render(self.label, True, WHITE)
            surface.blit(label_surface, (self.rect.x, self.rect.y - 25))
            
        # Track background
        track_rect = pygame.Rect(
            self.rect.x,
            self.rect.centery - self.track_height // 2,
            self.rect.width,
            self.track_height
        )
        pygame.draw.rect(surface, DARK_GRAY, track_rect, border_radius=4)
        
        # Filled part
        filled_rect = pygame.Rect(
            self.rect.x,
            self.rect.centery - self.track_height // 2,
            int(self.normalized_value * self.rect.width),
            self.track_height
        )
        pygame.draw.rect(surface, GOLD, filled_rect, border_radius=4)
        
        # Handle
        pygame.draw.circle(surface, GOLD, (self.handle_x, self.rect.centery), self.handle_radius)
        pygame.draw.circle(surface, WHITE, (self.handle_x, self.rect.centery), self.handle_radius - 3)
        
        # Value text
        value_text = f"{int(self.value * 100)}%"
        value_surface = self.font.render(value_text, True, LIGHT_GRAY)
        surface.blit(value_surface, (self.rect.right + 15, self.rect.centery - 10))


class Toggle:
    """Toggle switch control"""
    
    def __init__(self, x: int, y: int, label: str = "", initial: bool = False):
        self.x = x
        self.y = y
        self.width = 60
        self.height = 30
        self.label = label
        self.value = initial
        self.font = pygame.font.Font(None, 28)
        
        self.rect = pygame.Rect(x, y, self.width, self.height)
        
    def handle_event(self, event: pygame.event.Event) -> bool:
        """Handle events, return True if value changed"""
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mouse_pos = pygame.mouse.get_pos()
            if self.rect.collidepoint(mouse_pos):
                self.value = not self.value
                return True
        return False
        
    def draw(self, surface: pygame.Surface):
        """Draw the toggle"""
        # Label
        if self.label:
            label_surface = self.font.render(self.label, True, WHITE)
            surface.blit(label_surface, (self.x - label_surface.get_width() - 20, self.y + 5))
            
        # Background
        bg_color = DARK_GREEN if self.value else DARK_GRAY
        pygame.draw.rect(surface, bg_color, self.rect, border_radius=15)
        pygame.draw.rect(surface, GOLD, self.rect, width=2, border_radius=15)
        
        # Handle
        handle_x = self.x + self.width - 18 if self.value else self.x + 18
        pygame.draw.circle(surface, WHITE, (handle_x, self.y + self.height // 2), 11)


class Dropdown:
    """Dropdown selector control"""
    
    def __init__(self, x: int, y: int, width: int, height: int, 
                 options: list, initial_index: int = 0, label: str = ""):
        self.rect = pygame.Rect(x, y, width, height)
        self.options = options
        self.selected_index = initial_index
        self.label = label
        self.expanded = False
        self.font = pygame.font.Font(None, 28)
        self.hovered_index = -1
        
    @property
    def value(self) -> str:
        """Get selected value"""
        return self.options[self.selected_index] if self.options else ""
        
    def handle_event(self, event: pygame.event.Event) -> bool:
        """Handle events, return True if value changed"""
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mouse_pos = pygame.mouse.get_pos()
            
            if self.expanded:
                # Check if clicked on an option
                for i, option in enumerate(self.options):
                    option_rect = pygame.Rect(
                        self.rect.x,
                        self.rect.bottom + i * self.rect.height,
                        self.rect.width,
                        self.rect.height
                    )
                    if option_rect.collidepoint(mouse_pos):
                        if self.selected_index != i:
                            self.selected_index = i
                            self.expanded = False
                            return True
                        self.expanded = False
                        return False
                # Clicked outside
                self.expanded = False
            elif self.rect.collidepoint(mouse_pos):
                self.expanded = True
                
        elif event.type == pygame.MOUSEMOTION and self.expanded:
            mouse_pos = pygame.mouse.get_pos()
            self.hovered_index = -1
            for i in range(len(self.options)):
                option_rect = pygame.Rect(
                    self.rect.x,
                    self.rect.bottom + i * self.rect.height,
                    self.rect.width,
                    self.rect.height
                )
                if option_rect.collidepoint(mouse_pos):
                    self.hovered_index = i
                    break
                    
        return False
        
    def draw(self, surface: pygame.Surface):
        """Draw the dropdown"""
        # Label
        if self.label:
            label_surface = self.font.render(self.label, True, WHITE)
            surface.blit(label_surface, (self.rect.x, self.rect.y - 25))
            
        # Main button
        bg_color = HOVER_COLOR if self.expanded else DARK_GRAY
        pygame.draw.rect(surface, bg_color, self.rect, border_radius=6)
        pygame.draw.rect(surface, GOLD, self.rect, width=2, border_radius=6)
        
        # Selected text
        text_surface = self.font.render(self.value, True, WHITE)
        text_rect = text_surface.get_rect(midleft=(self.rect.x + 15, self.rect.centery))
        surface.blit(text_surface, text_rect)
        
        # Arrow
        arrow = "▼" if not self.expanded else "▲"
        arrow_surface = self.font.render(arrow, True, GOLD)
        surface.blit(arrow_surface, (self.rect.right - 30, self.rect.centery - 8))
        
        # Dropdown options
        if self.expanded:
            for i, option in enumerate(self.options):
                option_rect = pygame.Rect(
                    self.rect.x,
                    self.rect.bottom + i * self.rect.height,
                    self.rect.width,
                    self.rect.height
                )
                
                bg = HOVER_COLOR if i == self.hovered_index else MODAL_BG
                pygame.draw.rect(surface, bg, option_rect)
                pygame.draw.rect(surface, GOLD, option_rect, width=1)
                
                option_surface = self.font.render(option, True, WHITE)
                option_text_rect = option_surface.get_rect(
                    midleft=(option_rect.x + 15, option_rect.centery)
                )
                surface.blit(option_surface, option_text_rect)
