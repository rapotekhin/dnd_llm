"""Level-up: load data and build widgets."""
import pygame
from typing import Any, Dict, List

from ....colors import *
from ....components import Button, Tooltip
from core.database.json_database import JsonDatabase
from core.utils.level_up_utils import get_level_data
from localization import loc

from ...character_creation.widgets import AbilityCounter, SelectionList, _sc


class LevelUpSetupMixin:
    def _load_data(self):
        """Load all necessary data from database"""
        # Spell cache
        self.spell_cache: Dict[str, Dict[str, Any]] = {}
        # Features cache
        self.features_cache: Dict[str, Dict[str, Any]] = {}
        # Proficiency cache
        self.proficiency_cache: Dict[str, str] = {}
        
        # Ability labels
        self.ability_labels = {
            "str": loc.get("ability_str", "Сила"),
            "dex": loc.get("ability_dex", "Ловкость"),
            "con": loc.get("ability_con", "Телосложение"),
            "int": loc.get("ability_int", "Интеллект"),
            "wis": loc.get("ability_wis", "Мудрость"),
            "cha": loc.get("ability_cha", "Харизма"),
        }
        
        # Load spells if spellcaster
        if self.player.sc:
            class_index = self.player.class_type.index if hasattr(self.player.class_type, 'index') else str(self.player.class_type)
            try:
                spells_data = self.db.get(f"/classes/{class_index}/spells.json")
                spells = spells_data.get("results", [])
                
                # Separate cantrips and spells
                self.cantrips = [s for s in spells if s.get("level", 1) == 0]
                # Get spells up to new level
                max_spell_level = (self.build.new_level + 1) // 2  # Rough estimate
                self.available_spells = [s for s in spells if 1 <= s.get("level", 1) <= max_spell_level]
            except Exception as e:
                print(f"Error loading spells: {e}")
                self.cantrips = []
                self.available_spells = []
        else:
            self.cantrips = []
            self.available_spells = []
        
        # Load proficiency options if any - ONLY from level_data, not from class_data
        # Proficiency choices are only available at specific levels (usually level 1)
        self.proficiency_options: List[Dict[str, Any]] = []
        self.proficiency_choose_count = 0  # How many to choose
        
        if self.level_data:
            # Check for proficiency choices in level data ONLY
            # Do NOT load from class_data - those are for level 1 only
            level_choices = self.level_data.get("proficiency_choices", [])
            if level_choices:
                for c in level_choices:
                    opts = c.get("from", {}).get("options", [])
                    choose_count = c.get("choose", 0)
                    if opts and choose_count > 0:
                        self.proficiency_choose_count = choose_count
                        for o in opts:
                            item = o.get("item") if isinstance(o.get("item"), dict) else None
                            if item:
                                self.proficiency_options.append({
                                    "index": item.get("index"),
                                    "name": item.get("name", "")
                                })
                        break
        
    def _create_ui(self):
        """Create UI components"""
        s = self._scale
        w, h = self._w, self._h
        bw, bh = _sc(150, s), _sc(50, s)
        btn_y = h - _sc(70, s)
        self.prev_btn = Button(
            _sc(50, s), btn_y, bw, bh,
            f"< {loc.get('back', 'Назад')}", self.font
        )
        self.next_btn = Button(
            w - _sc(200, s), btn_y, bw, bh,
            f"{loc.get('next', 'Далее')} >", self.font
        )
        self.finish_btn = Button(
            w - _sc(200, s), btn_y, bw, bh,
            loc.get("finish", "Готово"), self.font
        )
        
        self.tooltip = Tooltip(max_width=_sc(350, s))
        
        # Step-specific UI
        self._create_features_ui()
        self._create_abilities_ui()
        self._create_spells_ui()
        self._create_proficiency_ui()
        
        # Feature modal state
        self._subfeature_modal_active = False
        self._subfeature_modal_feature: Optional[str] = None
        self._subfeature_modal_options: List[Dict[str, Any]] = []
        self._subfeature_modal_choose = 1
        self._subfeature_modal_selected: List[str] = []
        self._subfeature_modal_scroll = 0  # Scroll position for options list
        self.feature_rects: List[tuple] = []  # (rect, feature_index)
        
    def _create_features_ui(self):
        """Create features step UI"""
        pass  # Features are drawn dynamically
        
    def _create_abilities_ui(self):
        """Create abilities step UI"""
        s = self._scale
        self.ability_counters = {}
        # Start below info text (y=160 + text height ~30 + gap)
        y = _sc(200, s)
        for ability, label in self.ability_labels.items():
            self.ability_counters[ability] = AbilityCounter(150, y, ability, label, self.font)
            y += _sc(50, s)
            
    def _create_spells_ui(self):
        """Create spells step UI"""
        s = self._scale
        # Start lists below label (y=160 + label height ~30 + gap)
        list_start_y = _sc(200, s)
        self.cantrip_list = SelectionList(100, list_start_y, 350, 300, self.font)
        self.cantrip_list.set_items(self.cantrips)
        
        self.spell_list = SelectionList(100, list_start_y, 350, 400, self.font)
        self.spell_list.set_items(self.available_spells)
        
    def _create_proficiency_ui(self):
        """Create proficiency step UI"""
        s = self._scale
        # Start list below label (y=160 + label height ~30 + gap)
        list_start_y = _sc(200, s)
        self.proficiency_list = SelectionList(100, list_start_y, 350, 450, self.font)
        self.proficiency_list.set_items(self.proficiency_options)
        
    def _get_visible_steps(self) -> List[str]:
        """Get list of visible steps based on level data"""
        steps = []
        
        # Features (if any)
        if self.features_list:
            steps.append("features")
        
        # Ability score improvements (if any)
        if self.build.ability_score_bonuses > 0:
            steps.append("abilities")
        
        # Spells (if spellcaster)
        if self.player.sc:
            spellcasting_info = self.level_data.get("spellcasting", {})
            if spellcasting_info:
                cantrips = spellcasting_info.get("cantrips_known", 0)
                if cantrips and cantrips > len([s for s in self.player.sc.learned_spells if s.level == 0]):
                    steps.append("cantrips")
                
                # Check for new spells to learn (spells_known)
                spells_known = spellcasting_info.get("spells_known", 0)
                if spells_known > 0:
                    # Count current known spells (excluding cantrips)
                    current_spells = len([s for s in self.player.sc.learned_spells if s.level > 0])
                    # Get previous level data to see how many spells were known before
                    class_index = self.player.class_type.index if hasattr(self.player.class_type, 'index') else str(self.player.class_type)
                    try:
                        prev_level_data = get_level_data(class_index, self.player.level)
                        prev_spells_known = prev_level_data.get("spellcasting", {}).get("spells_known", 0) if prev_level_data else 0
                        new_spells_count = spells_known - prev_spells_known
                        if new_spells_count > 0:
                            steps.append("spells")
                            self.new_spells_count = new_spells_count
                        else:
                            self.new_spells_count = 0
                    except:
                        # Fallback: calculate from current spells
                        if spells_known > current_spells:
                            steps.append("spells")
                            self.new_spells_count = spells_known - current_spells
                        else:
                            self.new_spells_count = 0
                else:
                    self.new_spells_count = 0
        
        # Proficiency choices (if any)
        if self.proficiency_options:
            steps.append("proficiency_choices")
        
        # Always end with confirmation (even if no other steps)
        if not steps:
            # If no steps, just show confirmation
            steps.append("confirmation")
        else:
            steps.append("confirmation")
        
        return steps
