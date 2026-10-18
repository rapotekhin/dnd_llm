"""
Adaptive UI layout - use actual display size and scale factor.
Design base: 1280x720. Scale = min(w/1280, h/720).
"""

import pygame
from typing import Tuple

BASE_W = 1280
BASE_H = 720


def get_size(surface: pygame.Surface) -> Tuple[int, int]:
    """Return (width, height) of surface (actual display size)."""
    return surface.get_size()


def scale_factor(surface: pygame.Surface) -> float:
    """Return scale factor: min(actual_w/BASE_W, actual_h/BASE_H)."""
    w, h = get_size(surface)
    return min(w / BASE_W, h / BASE_H)


def scaled(value: float, surface: pygame.Surface) -> int:
    """Scale a design-dimension value by scale factor."""
    return max(1, int(value * scale_factor(surface)))
