"""Character creation: load DB data and build step UI."""
import pygame
from typing import Any, Dict, List, Optional

from ..colors import *
from ..components import Button, Tooltip
from localization import loc

from .widgets import AbilityCounter, SelectionList, _sc


class CharacterCreationSetupMixin:
    def _load_data(self):
        """Load all necessary data from database"""
        # Alignments
        alignments_data = self.db.get("/alignments.json")
        self.alignments = alignments_data.get("results", [])
        self.alignment_data: Optional[Dict[str, Any]] = None
        
        # Races
        races_data = self.db.get("/races.json")
        self.races = races_data.get("results", [])
        
        # Classes
        classes_data = self.db.get("/classes.json")
        self.classes = classes_data.get("results", [])
        
        # Backgrounds
        backgrounds_data = self.db.get("/backgrounds.json")
        self.backgrounds = backgrounds_data.get("results", [])
        
        # Traits cache for tooltips
        self.traits_cache: Dict[str, Dict[str, Any]] = {}
        # Spell cache for cantrip/spell tooltips
        self.spell_cache: Dict[str, Dict[str, Any]] = {}
        # Proficiency cache for proficiency_choices tooltips
        self.proficiency_cache: Dict[str, str] = {}
        
        # Ability scores
        self.ability_labels = {
            "str": loc["ability_str"],
            "dex": loc["ability_dex"],
            "con": loc["ability_con"],
            "int": loc["ability_int"],
            "wis": loc["ability_wis"],
            "cha": loc["ability_cha"],
        }
        
    def _create_ui(self):
        """Create UI components"""
        s = self._scale
        w, h = self._w, self._h
        bw, bh = _sc(150, s), _sc(50, s)
        btn_y = h - _sc(70, s)
        self.prev_btn = Button(
            _sc(50, s), btn_y, bw, bh,
            f"< {loc['back']}", self.font
        )
        self.next_btn = Button(
            w - _sc(200, s), btn_y, bw, bh,
            f"{loc['next']} >", self.font
        )
        self.finish_btn = Button(
            w - _sc(200, s), btn_y, bw, bh,
            loc["finish"], self.font
        )
        
        self.tooltip = Tooltip(max_width=_sc(350, s))
        
        # Trait rects for hover detection (filled when drawing race)
        self.trait_rects: List[tuple] = []  # [(rect, trait_index), ...]
        
        # Confirmation screen scroll
        self.confirmation_scroll_offset = 0
        self._confirmation_scroll_dragging = False
        self._confirmation_scroll_start_y = 0
        self._confirmation_panel_rect: Optional[pygame.Rect] = None
        
        # Step-specific UI
        self._create_biography_ui()
        self._create_race_ui()
        self._create_class_ui()
        self._create_background_ui()
        self._create_abilities_ui()
        
    def _create_biography_ui(self):
        """Create biography step UI"""
        self.name_input_rect = pygame.Rect(100, 178, 350, 42)
        self.name_input_active = False
        self.random_name_btn = Button(
            460, 176, 200, 46,
            loc["random_name"],
            self.font
        )
        self.gender_male_btn = Button(100, 238, 120, 36, loc["gender_male"], self.small_font)
        self.gender_female_btn = Button(230, 238, 120, 36, loc["gender_female"], self.small_font)
        self.age_input_rect = pygame.Rect(100, 292, 80, 36)
        self.age_input_active = False
        self.bio_age_buffer = ""
        self.weight_input_rect = pygame.Rect(220, 292, 80, 36)
        self.weight_input_active = False
        self.bio_weight_buffer = ""
        self.alignment_list = SelectionList(100, 348, 350, 320, self.font)
        self.alignment_list.set_items(self.alignments)
        
    def _create_race_ui(self):
        """Create race step UI"""
        self.race_list = SelectionList(100, 150, 350, 450, self.font)
        self.race_list.set_items(self.races)
        
        self.subrace_list = SelectionList(100, 150, 350, 450, self.font)
        
    def _create_class_ui(self):
        """Create class step UI"""
        self.class_list = SelectionList(100, 150, 350, 450, self.font)
        self.class_list.set_items(self.classes)
        
        self.spell_list = SelectionList(500, 150, 350, 300, self.font)
        self.selected_spells_list = SelectionList(500, 470, 350, 150, self.font)
        
    def _create_background_ui(self):
        """Create background step UI"""
        self.background_list = SelectionList(100, 150, 350, 450, self.font)
        self.background_list.set_items(self.backgrounds)
        
    def _create_abilities_ui(self):
        """Create abilities step UI"""
        self.ability_counters = {}
        y = 180
        for ability, label in self.ability_labels.items():
            self.ability_counters[ability] = AbilityCounter(150, y, ability, label, self.font)
            y += 50
            
    def _get_visible_steps(self) -> List[str]:
        """Get list of visible steps based on current choices"""
        steps = ["race"]
        
        # Check for subrace
        if self.build.race_data:
            subraces = self.build.race_data.get("subraces", [])
            if subraces:
                steps.append("subrace")
                
        steps.append("class")
        
        # Features step (always show after class selection)
        if self.build.class_type:
            steps.append("features")
        
        # Check for subclass at level 1 (most don't have it)
        # For now, skip subclass
        
        # Check for spellcasting
        if self.build.class_data:
            spellcasting = self.build.class_data.get("spellcasting")
            if spellcasting:
                # Load cantrips/spells info
                class_index = self.build.class_type
                try:
                    level_data = self.db.get(f"/classes/{class_index}/levels/1.json")
                    spellcasting_info = level_data.get("spellcasting", {})
                    
                    cantrips = spellcasting_info.get("cantrips_known", 0)
                    if cantrips > 0:
                        self.build.cantrips_known = cantrips
                        steps.append("cantrips")
                        
                    spells = spellcasting_info.get("spells_known", 0)
                    if spells > 0:
                        self.build.spells_known = spells
                        steps.append("spells")
                except:
                    pass
                    
        steps.extend(["background", "abilities"])
        
        # Proficiency choices (after abilities) if class has any
        if self.build.class_data:
            choices = self.build.class_data.get("proficiency_choices", [])
            for c in choices:
                opts = c.get("from", {}).get("options", [])
                if opts and c.get("choose", 0) > 0:
                    steps.append("proficiency_choices")
                    break
        
        # Biography (name + alignment) just before confirmation
        steps.append("biography")
        steps.append("confirmation")
        
        return steps
