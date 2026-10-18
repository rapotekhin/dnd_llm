"""
Base screen class - all screens inherit from this
"""

import pygame
from abc import ABC, abstractmethod
from typing import Union, Any
from core.entities.character import Character
from ..layout import get_size, scale_factor


class BaseScreen(ABC):
    """Abstract base class for all game screens.
    Provides self._w, self._h (actual size) and self._scale (min(w/BASE_W, h/BASE_H))."""
    
    def __init__(self, screen: pygame.Surface):
        self.screen = screen
        self._refresh_layout()
    
    def _refresh_layout(self):
        """Update _w, _h, _scale from current screen size. Call after resize."""
        self._w, self._h = get_size(self.screen)
        self._scale = scale_factor(self.screen)
        
    @abstractmethod
    def handle_event(self, event: pygame.event.Event) -> Union[str, None, Character]:
        """Handle pygame events. Return screen transition command, Character object, or None."""
        pass
        
    @abstractmethod
    def update(self):
        """Update screen state"""
        pass
        
    @abstractmethod
    def draw(self):
        """Draw the screen"""
        pass
