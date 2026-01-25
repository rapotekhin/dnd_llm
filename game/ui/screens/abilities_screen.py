"""
Abilities screen - features, cantrips, spells, spell slots.
"""

from __future__ import annotations

import pygame
from typing import List, Optional, Union, Dict, Any
from .base_screen import BaseScreen
from ..colors import *
from ..components import Button, Tooltip
from core import data as game_data
from core.database.json_database import JsonDatabase
from localization import loc

SB_W = 12
SB_PAD = 4


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


class AbilitiesScreen(BaseScreen):
    """Abilities: features, cantrips, spells tabs. Nav + Back."""

    def __init__(self, screen: pygame.Surface):
        super().__init__(screen)
        s = self._scale
        w, h = self._w, self._h
        self.font = pygame.font.Font(None, _sc(26, s))
        self.small_font = pygame.font.Font(None, _sc(22, s))

        self.nav_h = _sc(48, s)
        margin = _sc(16, s)
        nav_gap = _sc(10, s)
        nw = (w - 2 * margin - 5 * nav_gap) // 5
        self.nav_buttons: List[Button] = []
        self.nav_keys = ["nav_inventory", "nav_map", "nav_journal", "nav_character", "nav_abilities"]
        for i, key in enumerate(self.nav_keys):
            x = margin + i * (nw + nav_gap)
            self.nav_buttons.append(Button(x, _sc(6, s), nw, self.nav_h - _sc(12, s), loc[key], self.font))

        self.back_btn = Button(margin, h - _sc(56, s), _sc(120, s), _sc(44, s), loc["back"], self.font)
        
        # Tab buttons
        tab_y = self.nav_h + _sc(8, s)
        tab_h = _sc(36, s)
        tab_w = _sc(150, s)
        tab_gap = _sc(10, s)
        tab_x = margin
        self.tab_buttons: List[Button] = []
        self.tab_keys = ["abilities_tab_features", "abilities_tab_cantrips", "abilities_tab_spells"]
        for i, key in enumerate(self.tab_keys):
            self.tab_buttons.append(Button(tab_x + i * (tab_w + tab_gap), tab_y, tab_w, tab_h, loc[key], self.small_font))
        
        self.current_tab = 0  # 0=features, 1=cantrips, 2=spells
        
        content_top = tab_y + tab_h + _sc(8, s)
        content_h = h - content_top - _sc(64, s)
        self.content_rect = pygame.Rect(margin, content_top, w - 2 * margin, content_h)
        self._scroll = 0
        self.line_h = _sc(24, s)
        self.pad = _sc(12, s)
        self.tooltip = Tooltip()
        self.db = JsonDatabase()
        self.features_cache: Dict[str, Dict[str, Any]] = {}
        self.spells_cache: Dict[str, Dict[str, Any]] = {}
        self._item_line_rects: Dict[int, str] = {}  # line_index -> item_index (feature/spell)

    def _player(self):
        gs = game_data.game_state
        return gs.player if gs else None

    def _build_lines(self) -> List[str]:
        """Build list of display lines for current tab."""
        p = self._player()
        if not p:
            return []
        lines: List[str] = []
        self._item_line_rects = {}  # Reset line mapping

        if self.current_tab == 0:  # Features
            features = getattr(p, "features", None) or []
            if features:
                for feat_index in features:
                    if feat_index:
                        line_idx = len(lines)
                        self._item_line_rects[line_idx] = feat_index
                        # Try to get feature name
                        feat_name = feat_index
                        try:
                            if feat_index not in self.features_cache:
                                self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                            feat_data = self.features_cache[feat_index]
                            feat_name = feat_data.get("name", feat_index)
                        except:
                            pass
                        lines.append(f"  • {feat_name}")
            else:
                lines.append("  —")
        
        elif self.current_tab == 1:  # Cantrips
            if getattr(p, "is_spell_caster", False) and getattr(p, "sc", None):
                # Use cantrips property
                cantrips = p.sc.cantrips if hasattr(p.sc, "cantrips") else []
                if cantrips:
                    for cantrip in cantrips:
                        if cantrip:
                            line_idx = len(lines)
                            spell_index = getattr(cantrip, "index", None) or getattr(cantrip, "name", "")
                            if spell_index:
                                self._item_line_rects[line_idx] = spell_index
                            spell_name = getattr(cantrip, "name", str(cantrip))
                            lines.append(f"  • {spell_name}")
                else:
                    lines.append("  —")
            else:
                lines.append("  —")
        
        elif self.current_tab == 2:  # Spells
            if getattr(p, "is_spell_caster", False) and getattr(p, "sc", None):
                # Use leveled_spells property
                spells = p.sc.leveled_spells if hasattr(p.sc, "leveled_spells") else []
                if spells:
                    # Group by level
                    by_level: Dict[int, List[Any]] = {}
                    for spell in spells:
                        level = getattr(spell, "level", 1)
                        if level not in by_level:
                            by_level[level] = []
                        by_level[level].append(spell)
                    
                    for level in sorted(by_level.keys()):
                        lines.append(f"")
                        lines.append(f"—— Уровень {level} ——")
                        for spell in sorted(by_level[level], key=lambda s: getattr(s, "name", str(s))):
                            line_idx = len(lines)
                            spell_index = getattr(spell, "index", None) or getattr(spell, "name", "")
                            if spell_index:
                                self._item_line_rects[line_idx] = spell_index
                            spell_name = getattr(spell, "name", str(spell))
                            lines.append(f"  • {spell_name}")
                else:
                    lines.append("  —")
            else:
                lines.append("  —")

        return lines

    def _total_height(self) -> int:
        return self.pad + len(self._build_lines()) * self.line_h

    def _get_spell_slots_info(self) -> List[str]:
        """Get spell slots information."""
        p = self._player()
        if not p or not getattr(p, "is_spell_caster", False) or not getattr(p, "sc", None):
            return []
        
        current_slots = getattr(p.sc, "spell_slots", None) or []
        if not current_slots or all(s == 0 for s in current_slots):
            return []
        
        # Get max slots from class_type
        max_slots_list = current_slots.copy()  # Default to current if max not available
        if hasattr(p, "class_type") and p.class_type:
            class_slots = getattr(p.class_type, "spell_slots", None)
            if isinstance(class_slots, dict):
                # spell_slots is a dict: {level: [slots for each spell level]}
                char_level = getattr(p, "level", 1)
                max_slots_list = class_slots.get(char_level, current_slots)
            elif isinstance(class_slots, list):
                max_slots_list = class_slots
        
        lines = []
        lines.append("")
        lines.append("—— Ячейки заклинаний ——")
        for level in range(len(current_slots)):
            current = current_slots[level]
            max_slots = max_slots_list[level] if level < len(max_slots_list) else current
            if max_slots > 0:  # Show only if max > 0
                lines.append(f"  Уровень {level + 1}: {current}/{max_slots}")
        
        return lines

    def handle_event(self, event: pygame.event.Event) -> Union[str, None]:
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            return "main"

        # Tooltip on hover
        if event.type == pygame.MOUSEMOTION:
            mouse_pos = event.pos
            if self.content_rect.collidepoint(mouse_pos):
                # Calculate which line is hovered
                rel_y = mouse_pos[1] - self.content_rect.y - self.pad + self._scroll
                line_idx = rel_y // self.line_h
                item_index = self._item_line_rects.get(line_idx)
                if item_index:
                    # Load item data based on tab
                    if self.current_tab == 0:  # Features
                        if item_index not in self.features_cache:
                            try:
                                self.features_cache[item_index] = self.db.get(f"/features/{item_index}.json")
                            except:
                                self.features_cache[item_index] = {"name": item_index, "desc": ["No description"]}
                        item_data = self.features_cache[item_index]
                        desc = item_data.get("desc", [""])
                        if isinstance(desc, list):
                            desc = " ".join(desc)
                        self.tooltip.show(item_data.get("name", item_index), desc, mouse_pos)
                    elif self.current_tab in (1, 2):  # Cantrips or Spells
                        if item_index not in self.spells_cache:
                            try:
                                self.spells_cache[item_index] = self.db.get(f"/spells/{item_index}.json")
                            except:
                                self.spells_cache[item_index] = {"name": item_index, "desc": ["No description"]}
                        spell_data = self.spells_cache[item_index]
                        desc = spell_data.get("desc", [""])
                        if isinstance(desc, list):
                            desc = " ".join(desc)
                        self.tooltip.show(spell_data.get("name", item_index), desc, mouse_pos)
                else:
                    self.tooltip.hide()
            else:
                self.tooltip.hide()

        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            if self.back_btn.is_clicked(pos):
                return "main"
            
            # Tab buttons
            for i, btn in enumerate(self.tab_buttons):
                if btn.is_clicked(pos):
                    if i != self.current_tab:
                        self.current_tab = i
                        self._scroll = 0
                    return None
            
            # Nav buttons
            for i, key in enumerate(self.nav_keys):
                if not self.nav_buttons[i].is_clicked(pos):
                    continue
                if key == "nav_abilities":
                    return None
                if key == "nav_inventory":
                    return "inventory"
                if key == "nav_journal":
                    return "journal"
                if key == "nav_character":
                    return "character"
                return "main"

        if event.type == pygame.MOUSEWHEEL and self.content_rect.collidepoint(pygame.mouse.get_pos()):
            mx = max(0, self._total_height() - self.content_rect.height)
            step = 48
            if event.y > 0:
                self._scroll = max(0, self._scroll - step)
            else:
                self._scroll = min(mx, self._scroll + step)
            return None

        return None

    def update(self):
        pos = pygame.mouse.get_pos()
        for b in self.nav_buttons:
            b.update(pos)
        for b in self.tab_buttons:
            b.update(pos)
        self.back_btn.update(pos)

    def draw(self):
        self.screen.fill(BLACK)
        s = self._scale
        w, h = self._w, self._h
        margin = _sc(16, s)

        # Nav bar
        nav_rect = pygame.Rect(0, 0, w, self.nav_h)
        pygame.draw.rect(self.screen, DARK_GRAY, nav_rect)
        pygame.draw.line(self.screen, GOLD, (0, self.nav_h), (w, self.nav_h), 2)
        for i, btn in enumerate(self.nav_buttons):
            if i == 4:  # nav_abilities is index 4
                btn.custom_color = DARK_GREEN
            else:
                btn.custom_color = None  # type: ignore
            btn.draw(self.screen)

        player = self._player()
        if not player:
            no_pl = self.font.render(loc["inv_no_player"], True, LIGHT_GRAY)
            nr = no_pl.get_rect(center=(w // 2, h // 2))
            self.screen.blit(no_pl, nr)
            self.back_btn.draw(self.screen)
            self.tooltip.draw(self.screen)
            return

        # Tab buttons
        for i, btn in enumerate(self.tab_buttons):
            if i == self.current_tab:
                btn.custom_color = DARK_GREEN
            else:
                btn.custom_color = None  # type: ignore
            btn.draw(self.screen)

        # Content
        pygame.draw.rect(self.screen, MODAL_BG, self.content_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, self.content_rect, width=2, border_radius=8)
        
        lines = self._build_lines()
        
        # Add spell slots info if on spells tab
        if self.current_tab == 2:
            slots_lines = self._get_spell_slots_info()
            lines.extend(slots_lines)
        
        clip = self.screen.get_clip()
        self.screen.set_clip(self.content_rect)
        y = self.content_rect.y + self.pad - self._scroll
        for line in lines:
            if y + self.line_h >= self.content_rect.y and y < self.content_rect.bottom:
                is_header = line.startswith("——")
                col = GOLD if is_header else WHITE
                surf = self.small_font.render(line[:80], True, col)
                self.screen.blit(surf, (self.content_rect.x + self.pad, y))
            y += self.line_h
        self.screen.set_clip(clip)

        # Scrollbar
        total_h = self._total_height()
        if self.current_tab == 2:
            slots_lines = self._get_spell_slots_info()
            total_h += len(slots_lines) * self.line_h
        mx = max(0, total_h - self.content_rect.height)
        if mx > 0:
            track_h = self.content_rect.height - 2 * SB_PAD
            vis_ratio = self.content_rect.height / max(1, total_h)
            th = max(24, int(track_h * vis_ratio))
            ty = self.content_rect.y + SB_PAD + int((self._scroll / mx) * (track_h - th))
            rx = self.content_rect.right - SB_W - SB_PAD
            track = pygame.Rect(rx, self.content_rect.y + SB_PAD, SB_W, track_h)
            thumb = pygame.Rect(rx, ty, SB_W, th)
            pygame.draw.rect(self.screen, DARK_GRAY, track, border_radius=4)
            pygame.draw.rect(self.screen, GOLD, thumb, border_radius=4)

        self.back_btn.draw(self.screen)
        self.tooltip.draw(self.screen)
