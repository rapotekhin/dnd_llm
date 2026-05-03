"""Character creation main screen."""
from __future__ import annotations

import pygame
from typing import Dict, List, Optional, Union

from ..base_screen import BaseScreen
from ...colors import *
from ...components import Button, Tooltip
from core.entities.character import Character
from core.database.json_database import JsonDatabase
from core.builders.character_builder import CharacterBuild
from localization import loc

from .widgets import _sc
from .mixins.setup import CharacterCreationSetupMixin
from .mixins.logic import CharacterCreationLogicMixin
from .mixins.events import CharacterCreationEventsMixin
from .mixins.finish import CharacterCreationFinishMixin
from .mixins.drawing import CharacterCreationDrawingMixin


class CharacterCreationScreen(
    CharacterCreationDrawingMixin,
    CharacterCreationEventsMixin,
    CharacterCreationFinishMixin,
    CharacterCreationLogicMixin,
    CharacterCreationSetupMixin,
    BaseScreen,
):
    """Character creation with multiple steps"""

    STEPS = [
        "biography",      # 0: Name, Alignment
        "race",           # 1: Race selection
        "subrace",        # 2: Subrace (if available)
        "class",          # 3: Class selection
        "subclass",       # 4: Subclass (if available)
        "cantrips",       # 5: Cantrips (if spellcaster)
        "spells",         # 6: Spells (if spellcaster)
        "prepared",       # 7: Prepared spells
        "background",     # 8: Background
        "abilities",      # 9: Ability scores
        "proficiency_choices",  # 10: Class proficiency choices (skills, etc.)
    ]
    
    @staticmethod
    def _get_step_names() -> Dict[str, str]:
        """Get localized step names"""
        return {
            "biography": loc["step_biography"],
            "race": loc["step_race"],
            "subrace": loc["step_subrace"],
            "class": loc["step_class"],
            "features": loc["step_features"],
            "subclass": loc["step_subclass"],
            "cantrips": loc["step_cantrips"],
            "spells": loc["step_spells"],
            "prepared": loc["step_prepared"],
            "background": loc["step_background"],
            "abilities": loc["step_abilities"],
            "proficiency_choices": loc["step_proficiency_choices"],
            "confirmation": loc["step_confirmation"],
        }
    
    def __init__(self, screen: pygame.Surface):
        super().__init__(screen)
        s = self._scale
        self.db = JsonDatabase()
        self.build = CharacterBuild()
        self.current_step = 0
        
        self.title_font = pygame.font.Font(None, _sc(56, s))
        self.header_font = pygame.font.Font(None, _sc(42, s))
        self.font = pygame.font.Font(None, _sc(32, s))
        self.small_font = pygame.font.Font(None, _sc(26, s))
        
        self._load_data()
        self._create_ui()
        
    def handle_event(self, event: pygame.event.Event) -> Union[str, None, Character]:
        """Handle events"""
        visible_steps = self._get_visible_steps()
        current_step_name = visible_steps[self.current_step] if self.current_step < len(visible_steps) else "abilities"
        
        # Navigation buttons
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mouse_pos = pygame.mouse.get_pos()
            
            if self.prev_btn.is_clicked(mouse_pos) and self.current_step > 0:
                self.current_step -= 1
                self.tooltip.hide()
                self.trait_rects = []
                return None
                
            # Check if on confirmation step (last step)
            if self.current_step == len(visible_steps) - 1:
                if self.finish_btn.is_clicked(mouse_pos):
                    character = self._finish_creation()
                    return character
            else:
                if self.next_btn.is_clicked(mouse_pos):
                    self.current_step += 1
                    self.tooltip.hide()
                    self.trait_rects = []
                    visible = self._get_visible_steps()
                    if self.current_step < len(visible) and visible[self.current_step] == "confirmation":
                        self.confirmation_scroll_offset = 0
                    return None
                    
        # ESC to go back
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            return "title"
            
        # Step-specific handling
        if current_step_name == "biography":
            self._handle_biography_event(event)
        elif current_step_name == "race":
            self._handle_race_event(event)
        elif current_step_name == "subrace":
            self._handle_subrace_event(event)
        elif current_step_name == "class":
            self._handle_class_event(event)
        elif current_step_name == "features":
            if self._subfeature_modal_active:
                self._handle_subfeature_modal_event(event)
            else:
                self._handle_features_event(event)
        elif current_step_name == "cantrips":
            self._handle_cantrips_event(event)
        elif current_step_name == "spells":
            self._handle_spells_event(event)
        elif current_step_name == "background":
            self._handle_background_event(event)
        elif current_step_name == "abilities":
            self._handle_abilities_event(event)
        elif current_step_name == "proficiency_choices":
            self._handle_proficiency_choices_event(event)
        elif current_step_name == "confirmation":
            self._handle_confirmation_event(event)
            
        return None
    def update(self):
        """Update screen"""
        mouse_pos = pygame.mouse.get_pos()
        self.prev_btn.update(mouse_pos)
        self.next_btn.update(mouse_pos)
        self.finish_btn.update(mouse_pos)
        visible = self._get_visible_steps()
        if self.current_step < len(visible) and visible[self.current_step] == "biography":
            self.random_name_btn.update(mouse_pos)
            self.gender_male_btn.update(mouse_pos)
            self.gender_female_btn.update(mouse_pos)
        
    def draw(self):
        """
        Draw the screen.
        
        Z-order (drawing order) to prevent overlapping:
        1. Background (screen.fill)
        2. Static UI elements (title, indicators)
        3. Step content (lists, forms, etc.)
        4. Navigation buttons
        5. Modals (with overlay - draws after everything else)
        6. Tooltips (always last, always on top)
        """
        self.screen.fill(BLACK)
        
        visible_steps = self._get_visible_steps()
        current_step_name = visible_steps[self.current_step] if self.current_step < len(visible_steps) else "abilities"
        
        # 1. Background is already filled with BLACK
        
        # 2. Static UI elements (title, indicators)
        step_names = self._get_step_names()
        title = f"{loc['char_creation_title']} - {step_names.get(current_step_name, '')}"
        title_surface = self.title_font.render(title, True, GOLD)
        self.screen.blit(title_surface, (50, 30))
        
        self._draw_step_indicators(visible_steps)
        
        # 3. Step content (draw before navigation buttons)
        if current_step_name == "biography":
            self._draw_biography()
        elif current_step_name == "race":
            self._draw_race()
        elif current_step_name == "subrace":
            self._draw_subrace()
        elif current_step_name == "class":
            self._draw_class()
        elif current_step_name == "features":
            self._draw_features()
        elif current_step_name == "cantrips":
            self._draw_cantrips()
        elif current_step_name == "spells":
            self._draw_spells()
        elif current_step_name == "background":
            self._draw_background()
        elif current_step_name == "abilities":
            self._draw_abilities()
        elif current_step_name == "proficiency_choices":
            self._draw_proficiency_choices()
        elif current_step_name == "confirmation":
            self._draw_confirmation()
            
        # 4. Navigation buttons (draw after content, before modals)
        if self.current_step > 0:
            self.prev_btn.draw(self.screen)
            
        if self.current_step == len(visible_steps) - 1:
            self.finish_btn.draw(self.screen)
        else:
            self.next_btn.draw(self.screen)
        
        # 5. Modals (draw after everything else, with overlay that darkens background)
        if current_step_name == "features" and self._subfeature_modal_active:
            self._draw_subfeature_modal()
            
        # 6. Tooltip (draw last, always on top of everything)
        self.tooltip.draw(self.screen)
