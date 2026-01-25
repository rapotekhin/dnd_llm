"""
Journal screen - quests grouped by status with collapsible sections.
"""

from __future__ import annotations

import pygame
from typing import List, Optional, Union, Dict, Set
from .base_screen import BaseScreen
from ..colors import *
from ..components import Button
from core import data as game_data
from core.data.quest import Quest, QuestStatus, ObjectiveStatus
from localization import loc

SB_W = 12
SB_PAD = 4


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


class JournalScreen(BaseScreen):
    """Journal: quests grouped by status (Current, Completed, Failed). Nav + Back."""

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
        
        content_top = self.nav_h + _sc(12, s)
        content_h = h - content_top - _sc(64, s)
        self.content_rect = pygame.Rect(margin, content_top, w - 2 * margin, content_h)
        self._scroll = 0
        self.line_h = _sc(24, s)
        self.pad = _sc(12, s)
        
        # Collapsible sections state
        self._sections_expanded: Dict[str, bool] = {
            "current": True,
            "completed": True,
            "failed": True
        }
        
        # Expanded quests (show details)
        self._expanded_quests: Set[str] = set()  # quest.id
        
        # Quest rects for click detection
        self._quest_rects: List[tuple] = []  # (rect, quest_id, is_header)
        self._section_rects: List[tuple] = []  # (rect, section_key)

    def _get_quests(self) -> List[Quest]:
        """Get all quests from game state"""
        gs = game_data.game_state
        if not gs:
            return []
        return gs.quests or []

    def _group_quests_by_status(self) -> Dict[str, List[Quest]]:
        """Group quests by status"""
        quests = self._get_quests()
        grouped = {
            "current": [],
            "completed": [],
            "failed": []
        }
        
        for quest in quests:
            if quest.status == QuestStatus.IN_PROGRESS:
                grouped["current"].append(quest)
            elif quest.status == QuestStatus.COMPLETED:
                grouped["completed"].append(quest)
            elif quest.status == QuestStatus.FAILED:
                grouped["failed"].append(quest)
            # NOT_STARTED can be ignored or added to "current" if needed
        
        return grouped

    def _get_objectives_by_order(self, quest: Quest) -> List:
        """Get objectives grouped by order, excluding LOCKED"""
        objectives = [obj for obj in quest.objectives if obj.status != ObjectiveStatus.LOCKED]
        # Group by order
        by_order: Dict[int, List] = {}
        for obj in objectives:
            if obj.order not in by_order:
                by_order[obj.order] = []
            by_order[obj.order].append(obj)
        
        # Sort by order and flatten
        result = []
        for order in sorted(by_order.keys()):
            result.extend(by_order[order])
        return result

    def handle_event(self, event: pygame.event.Event) -> Union[str, None]:
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            return "main"

        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            if self.back_btn.is_clicked(pos):
                return "main"
            
            # Check section header clicks (toggle expand/collapse)
            for rect, section_key in self._section_rects:
                if rect.collidepoint(pos):
                    self._sections_expanded[section_key] = not self._sections_expanded[section_key]
                    return None
            
            # Check quest clicks (toggle expand/collapse)
            for rect, quest_id, is_header in self._quest_rects:
                if rect.collidepoint(pos) and is_header:
                    if quest_id in self._expanded_quests:
                        self._expanded_quests.remove(quest_id)
                    else:
                        self._expanded_quests.add(quest_id)
                    return None
            
            # Nav buttons
            for i, key in enumerate(self.nav_keys):
                if not self.nav_buttons[i].is_clicked(pos):
                    continue
                if key == "nav_journal":
                    return None
                if key == "nav_inventory":
                    return "inventory"
                if key == "nav_character":
                    return "character"
                if key == "nav_abilities":
                    return "abilities"
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

    def _total_height(self) -> int:
        """Calculate total content height"""
        grouped = self._group_quests_by_status()
        height = self.pad
        
        section_names = {
            "current": loc["journal_current"],
            "completed": loc["journal_completed"],
            "failed": loc["journal_failed"]
        }
        
        for section_key in ["current", "completed", "failed"]:
            quests = grouped[section_key]
            if not quests:
                continue
            
            # Section header
            height += self.line_h + _sc(4, self._scale)
            
            if self._sections_expanded[section_key]:
                for quest in quests:
                    # Quest header
                    height += self.line_h + _sc(4, self._scale)
                    
                    # Quest details if expanded
                    if quest.id in self._expanded_quests:
                        # Description
                        desc_lines = self._wrap_text(quest.description, self.content_rect.width - 2 * self.pad)
                        height += len(desc_lines) * self.line_h
                        
                        # Objectives
                        objectives = self._get_objectives_by_order(quest)
                        if objectives:
                            height += self.line_h  # "Objectives:" header
                            for obj in objectives:
                                height += self.line_h
        
        return height

    def _wrap_text(self, text: str, max_width: int) -> List[str]:
        """Word-wrap text to fit max width"""
        words = text.split()
        lines = []
        current_line = ""
        for word in words:
            test_line = current_line + " " + word if current_line else word
            if self.small_font.size(test_line)[0] < max_width:
                current_line = test_line
            else:
                if current_line:
                    lines.append(current_line)
                current_line = word
        if current_line:
            lines.append(current_line)
        return lines

    def update(self):
        pos = pygame.mouse.get_pos()
        for b in self.nav_buttons:
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
            if i == 2:  # nav_journal is index 2
                btn.custom_color = DARK_GREEN
            else:
                btn.custom_color = None  # type: ignore
            btn.draw(self.screen)

        # Content
        pygame.draw.rect(self.screen, MODAL_BG, self.content_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, self.content_rect, width=2, border_radius=8)
        
        grouped = self._group_quests_by_status()
        self._quest_rects = []
        self._section_rects = []
        
        section_names = {
            "current": loc["journal_current"],
            "completed": loc["journal_completed"],
            "failed": loc["journal_failed"]
        }
        
        clip = self.screen.get_clip()
        self.screen.set_clip(self.content_rect)
        y = self.content_rect.y + self.pad - self._scroll
        
        for section_key in ["current", "completed", "failed"]:
            quests = grouped[section_key]
            if not quests:
                continue
            
            # Section header
            section_name = section_names[section_key]
            expanded = self._sections_expanded[section_key]
            header_text = f"{'▼' if expanded else '▶'} {section_name} ({len(quests)})"
            
            if y + self.line_h >= self.content_rect.y and y < self.content_rect.bottom:
                header_surf = self.font.render(header_text, True, GOLD)
                self.screen.blit(header_surf, (self.content_rect.x + self.pad, y))
                
                # Store section rect for click detection
                section_rect = pygame.Rect(self.content_rect.x, y, self.content_rect.width, self.line_h)
                self._section_rects.append((section_rect, section_key))
            
            y += self.line_h + _sc(4, s)
            
            if expanded:
                for quest in quests:
                    # Quest header
                    is_expanded = quest.id in self._expanded_quests
                    quest_header = f"{'▼' if is_expanded else '▶'} {quest.name}"
                    
                    if y + self.line_h >= self.content_rect.y and y < self.content_rect.bottom:
                        quest_surf = self.small_font.render(quest_header[:60], True, WHITE)
                        self.screen.blit(quest_surf, (self.content_rect.x + self.pad + _sc(20, s), y))
                        
                        # Store quest header rect
                        quest_rect = pygame.Rect(self.content_rect.x + self.pad + _sc(20, s), y, 
                                               self.content_rect.width - self.pad - _sc(20, s), self.line_h)
                        self._quest_rects.append((quest_rect, quest.id, True))
                    
                    y += self.line_h + _sc(4, s)
                    
                    # Quest details if expanded
                    if is_expanded:
                        # Description
                        desc_lines = self._wrap_text(quest.description, self.content_rect.width - 2 * self.pad - _sc(20, s))
                        for line in desc_lines:
                            if y + self.line_h >= self.content_rect.y and y < self.content_rect.bottom:
                                desc_surf = self.small_font.render(line[:80], True, LIGHT_GRAY)
                                self.screen.blit(desc_surf, (self.content_rect.x + self.pad + _sc(40, s), y))
                            y += self.line_h
                        
                        # Objectives
                        objectives = self._get_objectives_by_order(quest)
                        if objectives:
                            if y + self.line_h >= self.content_rect.y and y < self.content_rect.bottom:
                                obj_header = self.small_font.render(loc["journal_objectives"], True, GOLD)
                                self.screen.blit(obj_header, (self.content_rect.x + self.pad + _sc(40, s), y))
                            y += self.line_h
                            
                            for obj in objectives:
                                # Status indicator
                                status_indicator = ""
                                if obj.status == ObjectiveStatus.COMPLETED:
                                    status_indicator = "✓ "
                                elif obj.status == ObjectiveStatus.IN_PROGRESS:
                                    status_indicator = "→ "
                                elif obj.status == ObjectiveStatus.AVAILABLE:
                                    status_indicator = "○ "
                                
                                obj_text = f"{status_indicator}{obj.description}"
                                if obj.required_amount > 1:
                                    obj_text += f" ({obj.current_amount}/{obj.required_amount})"
                                
                                if y + self.line_h >= self.content_rect.y and y < self.content_rect.bottom:
                                    obj_color = DARK_GREEN if obj.status == ObjectiveStatus.COMPLETED else (
                                        GOLD if obj.status == ObjectiveStatus.IN_PROGRESS else LIGHT_GRAY
                                    )
                                    obj_surf = self.small_font.render(obj_text[:70], True, obj_color)
                                    self.screen.blit(obj_surf, (self.content_rect.x + self.pad + _sc(60, s), y))
                                y += self.line_h
        
        self.screen.set_clip(clip)

        # Scrollbar
        total_h = self._total_height()
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
