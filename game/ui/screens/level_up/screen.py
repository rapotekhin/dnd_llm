"""Level-up main screen."""
from __future__ import annotations

import pygame
from typing import Dict, Union

from ..base_screen import BaseScreen
from ..colors import *
from ..components import Button, Tooltip
from core.entities.character import Character
from core.database.json_database import JsonDatabase
from core.builders.level_up_builder import LevelUpBuild
from core.utils.level_up_utils import get_level_data
from core import data as game_data
from localization import loc

from ..character_creation.widgets import AbilityCounter, SelectionList, _sc
from .mixins.setup import LevelUpSetupMixin
from .mixins.logic import LevelUpLogicMixin
from .mixins.events import LevelUpEventsMixin
from .mixins.drawing import LevelUpDrawingMixin


class LevelUpScreen(
    LevelUpDrawingMixin,
    LevelUpEventsMixin,
    LevelUpLogicMixin,
    LevelUpSetupMixin,
    BaseScreen,
):
    """Level up screen with multiple steps"""
    
    STEPS = [
        "features",           # 0: New features
        "abilities",          # 1: Ability score improvements
        "cantrips",           # 2: New cantrips (if spellcaster)
        "spells",            # 3: New spells (if spellcaster)
        "proficiency_choices", # 4: Proficiency choices (if any)
        "confirmation",       # 5: Summary and finish
    ]
    
    @staticmethod
    def _get_step_names() -> Dict[str, str]:
        """Get localized step names"""
        return {
            "features": loc.get("step_features", "Особенности"),
            "abilities": loc.get("step_abilities", "Характеристики"),
            "cantrips": loc.get("step_cantrips", "Заговоры"),
            "spells": loc.get("step_spells", "Заклинания"),
            "proficiency_choices": loc.get("step_proficiency_choices", "Навыки"),
            "confirmation": loc.get("step_confirmation", "Подтверждение"),
        }
    
    def __init__(self, screen: pygame.Surface):
        super().__init__(screen)
        s = self._scale
        self.db = JsonDatabase()
        
        # Get current player
        gs = game_data.game_state
        self.player = gs.player if gs else None
        
        if not self.player:
            raise ValueError("No player found for level up")
        
        # Initialize level up build
        self.build = LevelUpBuild()
        self.build.new_level = self.player.level + 1
        
        # Load level data for new level
        class_index = self.player.class_type.index if hasattr(self.player.class_type, 'index') else str(self.player.class_type)
        self.level_data = get_level_data(class_index, self.build.new_level)
        
        if not self.level_data:
            raise ValueError(f"Could not load level data for {class_index} level {self.build.new_level}")
        
        # Initialize build from level data
        self.build.ability_score_bonuses = self.level_data.get("ability_score_bonuses", 0)
        self.build.abilities = {
            "str": 0, "dex": 0, "con": 0, "int": 0, "wis": 0, "cha": 0
        }
        
        # Load features
        features_data = self.level_data.get("features", [])
        self.features_list = features_data
        self.build.features = [f.get("index", "") for f in features_data if f.get("index")]
        
        self.current_step = 0
        self.new_spells_count = 0  # How many new spells can be learned
        
        self.title_font = pygame.font.Font(None, _sc(56, s))
        self.header_font = pygame.font.Font(None, _sc(42, s))
        self.font = pygame.font.Font(None, _sc(32, s))
        self.small_font = pygame.font.Font(None, _sc(26, s))
        
        self._load_data()
        self._create_ui()
        
    def handle_event(self, event: pygame.event.Event) -> Union[str, None, Character]:
        """Handle events"""
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            return "character"
        
        visible_steps = self._get_visible_steps()
        if not visible_steps:
            return "character"
        
        current_step_name = visible_steps[self.current_step] if self.current_step < len(visible_steps) else "confirmation"
        
        # Navigation buttons
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            if self.current_step > 0 and self.prev_btn.is_clicked(pos):
                self.current_step -= 1
                return None
            if self.current_step < len(visible_steps) - 1:
                if self.next_btn.is_clicked(pos):
                    # Validate current step before proceeding
                    if self._validate_step(current_step_name):
                        self.current_step += 1
                    return None
            else:
                if self.finish_btn.is_clicked(pos):
                    # Apply level up and return updated character
                    updated_player = self.build.apply_level_up(self.player)
                    gs = game_data.game_state
                    if gs:
                        gs.player = updated_player
                    return "character"
        
        # Step-specific handling
        if current_step_name == "features":
            if self._subfeature_modal_active:
                self._handle_subfeature_modal_event(event)
            else:
                self._handle_features_event(event)
        elif current_step_name == "abilities":
            self._handle_abilities_event(event)
        elif current_step_name == "cantrips":
            self._handle_cantrips_event(event)
        elif current_step_name == "spells":
            self._handle_spells_event(event)
        elif current_step_name == "proficiency_choices":
            self._handle_proficiency_choices_event(event)
        elif current_step_name == "confirmation":
            self._handle_confirmation_event(event)
            
        return None
    def update(self):
        """Update screen state"""
        pos = pygame.mouse.get_pos()
        self.prev_btn.update(pos)
        self.next_btn.update(pos)
        self.finish_btn.update(pos)
        
    def draw(self):
        """
        Draw the screen.
        
        Z-order (drawing order) to prevent overlapping:
        1. Background (screen.fill)
        2. Static UI elements (title, indicators, nav bar)
        3. Step content (lists, forms, etc.)
        4. Navigation buttons
        5. Modals (with overlay - draws after everything else)
        6. Tooltips (always last, always on top)
        """
        self.screen.fill(BLACK)
        
        visible_steps = self._get_visible_steps()
        if not visible_steps:
            return
        
        current_step_name = visible_steps[self.current_step] if self.current_step < len(visible_steps) else "confirmation"
        
        # 1. Background is already filled with BLACK
        
        # 2. Static UI elements (title, indicators)
        step_names = self._get_step_names()
        title = f"{loc.get('level_up_title', 'Поднятие уровня')} - {step_names.get(current_step_name, '')}"
        title_surface = self.title_font.render(title, True, GOLD)
        self.screen.blit(title_surface, (50, 30))
        
        level_text = f"Уровень {self.player.level} → {self.build.new_level}"
        level_surface = self.font.render(level_text, True, WHITE)
        self.screen.blit(level_surface, (50, 90))
        
        self._draw_step_indicators(visible_steps)
        
        # 3. Step content (draw before navigation buttons)
        if current_step_name == "features":
            self._draw_features()
        elif current_step_name == "abilities":
            self._draw_abilities()
        elif current_step_name == "cantrips":
            self._draw_cantrips()
        elif current_step_name == "spells":
            self._draw_spells()
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
