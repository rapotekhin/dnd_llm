"""
Level Up Screen - handles level up choices
"""

import pygame
from typing import List, Dict, Any, Optional, Union
from .base_screen import BaseScreen
from ..colors import *
from ..components import Button, Tooltip
from .character_creation_screen import SelectionList, AbilityCounter
from core.entities.character import Character
from core.database.json_database import JsonDatabase
from core.builders.level_up_builder import LevelUpBuild
from core.utils.level_up_utils import get_level_data
from core import data as game_data
from localization import loc


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


class LevelUpScreen(BaseScreen):
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
        
    def _validate_step(self, step_name: str) -> bool:
        """Validate current step before proceeding"""
        if step_name == "features":
            # Check if all features with subfeature_options have been chosen
            for feat in self.features_list:
                feat_index = feat.get("index", "")
                if feat_index:
                    # Load feature data to check for subfeature options
                    if feat_index not in self.features_cache:
                        try:
                            self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                        except:
                            self.features_cache[feat_index] = {}
                    
                    feat_data = self.features_cache.get(feat_index, {})
                    feature_specific = feat_data.get("feature_specific", {})
                    subfeature_opts = feature_specific.get("subfeature_options", {})
                    if subfeature_opts:
                        # This feature requires a choice
                        choose_count = subfeature_opts.get("choose", 1)
                        # Check if choice was made
                        if feat_index in self.build.feature_choices:
                            chosen = self.build.feature_choices[feat_index]
                            if choose_count > 1:
                                # Multiple choices needed
                                if isinstance(chosen, list):
                                    if len(chosen) != choose_count:
                                        return False
                                else:
                                    # Single value stored but multiple needed
                                    return False
                            else:
                                # Single choice needed
                                if isinstance(chosen, list):
                                    # List stored but single needed
                                    return False
                                elif not chosen:
                                    return False
                        else:
                            # No choice made for this feature
                            return False
            return True
        elif step_name == "abilities":
            # Check if all ability score bonuses are used
            # Can be +2 to one ability or +1 to two abilities
            total_used = sum(self.build.abilities.values())
            if self.build.ability_score_bonuses == 2:
                # Can be +2 to one or +1 to two
                return total_used == 2
            return total_used == self.build.ability_score_bonuses
        elif step_name == "cantrips":
            # Check if required cantrips are selected
            spellcasting_info = self.level_data.get("spellcasting", {})
            cantrips_known = spellcasting_info.get("cantrips_known", 0)
            current_cantrips = len([s for s in self.player.sc.learned_spells if s.level == 0])
            needed = cantrips_known - current_cantrips
            return len(self.build.new_cantrips) >= needed
        elif step_name == "spells":
            # Check if required number of spells are selected
            return len(self.build.new_spells) == self.new_spells_count
        elif step_name == "proficiency_choices":
            # Check if required number of proficiencies are selected
            return len(self.build.proficiency_choices_selected) == self.proficiency_choose_count
        return True
        
    def _handle_features_event(self, event: pygame.event.Event):
        """Handle features step events"""
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mouse_pos = event.pos
            for rect, feat_index in self.feature_rects:
                if rect.collidepoint(mouse_pos):
                    if feat_index not in self.features_cache:
                        try:
                            self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                        except:
                            self.features_cache[feat_index] = {"name": feat_index, "desc": ["No description"]}
                    
                    feat_data = self.features_cache[feat_index]
                    feature_specific = feat_data.get("feature_specific", {})
                    subfeature_opts = feature_specific.get("subfeature_options", {})
                    if subfeature_opts:
                        self._show_subfeature_choice_modal(feat_index, feat_data, subfeature_opts)
                    break
        
        # Tooltip on hover
        if event.type == pygame.MOUSEMOTION and not self._subfeature_modal_active:
            mouse_pos = event.pos
            tooltip_shown = False
            for rect, feat_index in self.feature_rects:
                if rect.collidepoint(mouse_pos):
                    if feat_index not in self.features_cache:
                        try:
                            self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                        except:
                            self.features_cache[feat_index] = {"name": feat_index, "desc": ["No description"]}
                    
                    feat_data = self.features_cache[feat_index]
                    desc = feat_data.get("desc", [""])
                    if isinstance(desc, list):
                        desc = " ".join(desc)
                    chosen = self.build.feature_choices.get(feat_index)
                    if chosen:
                        try:
                            subfeat_data = self.db.get(f"/features/{chosen}.json")
                            subfeat_name = subfeat_data.get("name", chosen)
                            desc = f"{desc}\n\nВыбрано: {subfeat_name}"
                        except:
                            pass
                    self.tooltip.show(feat_data.get("name", ""), desc, mouse_pos)
                    tooltip_shown = True
                    break
            
            if not tooltip_shown:
                self.tooltip.hide()
                
    def _show_subfeature_choice_modal(self, feature_index: str, feature_data: Dict, subfeature_opts: Dict):
        """Show modal to choose subfeature"""
        from_data = subfeature_opts.get("from", {})
        options = from_data.get("options", [])
        choose_count = subfeature_opts.get("choose", 1)
        
        if not options:
            return
        
        # Extract subfeature options
        subfeatures: List[Dict[str, Any]] = []
        for opt in options:
            if opt.get("option_type") == "reference":
                item = opt.get("item", {})
                if item:
                    subfeatures.append({
                        "index": item.get("index", ""),
                        "name": item.get("name", ""),
                        "url": item.get("url", "")
                    })
        
        if not subfeatures:
            return
        
        # Hide tooltip when opening modal
        self.tooltip.hide()
        
        # Store modal state
        self._subfeature_modal_active = True
        self._subfeature_modal_feature = feature_index
        self._subfeature_modal_options = subfeatures
        self._subfeature_modal_choose = choose_count
        # Pre-select already chosen subfeatures if exists (support multiple choices)
        # Check if we already have choices for this feature
        existing_choices = []
        if feature_index in self.build.feature_choices:
            # If it's a single choice stored as string
            existing_choice = self.build.feature_choices[feature_index]
            if isinstance(existing_choice, str):
                if existing_choice in [opt.get("index") for opt in subfeatures]:
                    existing_choices = [existing_choice]
            elif isinstance(existing_choice, list):
                existing_choices = [c for c in existing_choice if c in [opt.get("index") for opt in subfeatures]]
        self._subfeature_modal_selected = existing_choices
        
    def _handle_subfeature_modal_event(self, event: pygame.event.Event):
        """Handle events in subfeature choice modal"""
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            self._subfeature_modal_active = False
            self.tooltip.hide()
            return
        
        s = self._scale
        w, h = self._w, self._h
        mw, mh = _sc(500, s), _sc(450, s)
        mr = pygame.Rect(w // 2 - mw // 2, h // 2 - mh // 2, mw, mh)
        
        # Calculate list area (same as in draw)
        btn_h = _sc(40, s)
        btn_padding = _sc(20, s)
        btn_y = mr.bottom - btn_h - btn_padding
        list_top = mr.y + _sc(80, s)
        list_bottom = btn_y - _sc(10, s)
        list_area = pygame.Rect(mr.x + _sc(20, s), list_top, mr.w - _sc(40, s), list_bottom - list_top)
        
        item_h = _sc(36, s)
        item_spacing = _sc(6, s)
        total_item_h = item_h + item_spacing
        
        # Handle scroll wheel
        if event.type == pygame.MOUSEWHEEL:
            if list_area.collidepoint(pygame.mouse.get_pos()):
                total_height = len(self._subfeature_modal_options) * total_item_h
                max_scroll = max(0, total_height - list_area.height)
                self._subfeature_modal_scroll = max(0, min(
                    self._subfeature_modal_scroll - event.y * _sc(20, s),
                    max_scroll
                ))
                return
        
        # Tooltip on hover for options
        if event.type == pygame.MOUSEMOTION:
            pos = event.pos
            tooltip_shown = False
            
            # Check if hovering over an option (with scroll offset)
            y = list_area.y - self._subfeature_modal_scroll
            for opt in self._subfeature_modal_options:
                opt_index = opt.get("index", "")
                rr = pygame.Rect(list_area.x, y, list_area.w, item_h)
                
                # Only check if visible and in list area
                if rr.collidepoint(pos) and list_area.collidepoint(pos):
                    # Load subfeature data
                    if opt_index not in self.features_cache:
                        try:
                            self.features_cache[opt_index] = self.db.get(f"/features/{opt_index}.json")
                        except:
                            self.features_cache[opt_index] = {"name": opt_index, "desc": ["No description"]}
                    
                    subfeat_data = self.features_cache[opt_index]
                    desc = subfeat_data.get("desc", [""])
                    if isinstance(desc, list):
                        desc = " ".join(desc)
                    self.tooltip.show(subfeat_data.get("name", opt_index), desc, pos)
                    tooltip_shown = True
                    break
                y += total_item_h
            
            if not tooltip_shown:
                self.tooltip.hide()
        
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            
            # Check option clicks (with scroll offset)
            y = list_area.y - self._subfeature_modal_scroll
            option_clicked = False
            for opt in self._subfeature_modal_options:
                opt_index = opt.get("index", "")
                rr = pygame.Rect(list_area.x, y, list_area.w, item_h)
                
                # Only check if visible and in list area
                if rr.collidepoint(pos) and list_area.collidepoint(pos):
                    option_clicked = True
                    if opt_index in self._subfeature_modal_selected:
                        self._subfeature_modal_selected.remove(opt_index)
                    elif len(self._subfeature_modal_selected) < self._subfeature_modal_choose:
                        self._subfeature_modal_selected.append(opt_index)
                    break
                y += total_item_h
            
            # Check confirm button (only if option wasn't clicked)
            if not option_clicked:
                btn_w = _sc(120, s)
                confirm_rect = pygame.Rect(mr.centerx - btn_w // 2, btn_y, btn_w, btn_h)
                if confirm_rect.collidepoint(pos) and len(self._subfeature_modal_selected) == self._subfeature_modal_choose:
                    # Save choice(s)
                    if self._subfeature_modal_feature:
                        # Store all selected subfeatures
                        if len(self._subfeature_modal_selected) == 1:
                            # Single choice - store as string
                            chosen = self._subfeature_modal_selected[0]
                            self.build.feature_choices[self._subfeature_modal_feature] = chosen
                            # Replace parent feature with chosen subfeature in features list
                            if self._subfeature_modal_feature in self.build.features:
                                idx = self.build.features.index(self._subfeature_modal_feature)
                                self.build.features[idx] = chosen
                            elif chosen not in self.build.features:
                                self.build.features.append(chosen)
                        else:
                            # Multiple choices - store all and add them to features
                            self.build.feature_choices[self._subfeature_modal_feature] = self._subfeature_modal_selected.copy()
                            # Remove parent feature and add all chosen subfeatures
                            if self._subfeature_modal_feature in self.build.features:
                                idx = self.build.features.index(self._subfeature_modal_feature)
                                self.build.features.pop(idx)
                            for chosen in self._subfeature_modal_selected:
                                if chosen not in self.build.features:
                                    self.build.features.append(chosen)
                    self._subfeature_modal_active = False
            
    def _handle_abilities_event(self, event: pygame.event.Event):
        """Handle abilities step events"""
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            for ability, counter in self.ability_counters.items():
                action = counter.handle_click(event.pos)
                if action == "increase":
                    total_used = sum(self.build.abilities.values())
                    current_ability = getattr(self.player.abilities, ability)
                    if total_used < self.build.ability_score_bonuses and current_ability < 20:
                        self.build.abilities[ability] += 1
                elif action == "decrease":
                    if self.build.abilities[ability] > 0:
                        self.build.abilities[ability] -= 1
                    
    def _handle_cantrips_event(self, event: pygame.event.Event):
        """Handle cantrips selection"""
        clicked = self.cantrip_list.handle_event(event)
        if clicked and event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            item = self.cantrip_list.get_selected()
            if item:
                idx = item.get("index")
                if idx is not None:
                    if idx in self.build.new_cantrips:
                        self.build.new_cantrips.remove(idx)
                    else:
                        spellcasting_info = self.level_data.get("spellcasting", {})
                        cantrips_known = spellcasting_info.get("cantrips_known", 0)
                        current_cantrips = len([s for s in self.player.sc.learned_spells if s.level == 0])
                        needed = cantrips_known - current_cantrips
                        if len(self.build.new_cantrips) < needed:
                            self.build.new_cantrips.append(idx)
        
        # Update selected indices for highlighting
        self.cantrip_list.selected_indices = set(self.build.new_cantrips)
        
        # Tooltip on hover
        if event.type == pygame.MOUSEMOTION:
            in_list = (self.cantrip_list.rect.collidepoint(event.pos) and 
                      not self.cantrip_list._is_in_scrollbar(event.pos) and
                      0 <= self.cantrip_list.hovered_index < len(self.cantrip_list.items))
            if in_list:
                it = self.cantrip_list.items[self.cantrip_list.hovered_index]
                sid = it.get("index")
                if sid is not None:
                    if sid not in self.spell_cache:
                        try:
                            self.spell_cache[sid] = self.db.get(f"/spells/{sid}.json")
                        except Exception:
                            self.spell_cache[sid] = {"name": it.get("name", ""), "desc": ["No description"]}
                    d = self.spell_cache[sid]
                    desc = self._format_spell_tooltip(d)
                    self.tooltip.show(d.get("name", ""), desc, event.pos)
            else:
                self.tooltip.hide()
                
    def _handle_spells_event(self, event: pygame.event.Event):
        """Handle spells selection"""
        clicked = self.spell_list.handle_event(event)
        if clicked and event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            item = self.spell_list.get_selected()
            if item:
                idx = item.get("index")
                if idx is not None:
                    if idx in self.build.new_spells:
                        self.build.new_spells.remove(idx)
                    else:
                        # Check limit - can only select up to new_spells_count
                        if len(self.build.new_spells) < self.new_spells_count:
                            self.build.new_spells.append(idx)
        
        # Update selected indices
        self.spell_list.selected_indices = set(self.build.new_spells)
        
        # Tooltip on hover
        if event.type == pygame.MOUSEMOTION:
            in_list = (self.spell_list.rect.collidepoint(event.pos) and 
                      not self.spell_list._is_in_scrollbar(event.pos) and
                      0 <= self.spell_list.hovered_index < len(self.spell_list.items))
            if in_list:
                it = self.spell_list.items[self.spell_list.hovered_index]
                sid = it.get("index")
                if sid is not None:
                    if sid not in self.spell_cache:
                        try:
                            self.spell_cache[sid] = self.db.get(f"/spells/{sid}.json")
                        except Exception:
                            self.spell_cache[sid] = {"name": it.get("name", ""), "desc": ["No description"]}
                    d = self.spell_cache[sid]
                    desc = self._format_spell_tooltip(d)
                    self.tooltip.show(d.get("name", ""), desc, event.pos)
            else:
                self.tooltip.hide()
                
    def _handle_proficiency_choices_event(self, event: pygame.event.Event):
        """Handle proficiency choices"""
        clicked = self.proficiency_list.handle_event(event)
        if clicked and event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            item = self.proficiency_list.get_selected()
            if item:
                idx = item.get("index")
                if idx is not None:
                    if idx in self.build.proficiency_choices_selected:
                        self.build.proficiency_choices_selected.remove(idx)
                    else:
                        # Check limit - can only select up to proficiency_choose_count
                        if len(self.build.proficiency_choices_selected) < self.proficiency_choose_count:
                            self.build.proficiency_choices_selected.append(idx)
        
        # Update selected indices
        self.proficiency_list.selected_indices = set(self.build.proficiency_choices_selected)
        
    def _handle_confirmation_event(self, event: pygame.event.Event):
        """Handle confirmation step events"""
        pass  # Just shows summary
        
    def _format_spell_tooltip(self, data: Dict[str, Any]) -> str:
        """Build tooltip text from spell JSON"""
        parts: List[str] = []
        desc = data.get("desc", [])
        if isinstance(desc, list):
            desc = " ".join(desc)
        if desc:
            parts.append(desc)
        range_val = data.get("range", "")
        if range_val:
            parts.append(f"Range: {range_val}")
        level = data.get("level", 0)
        parts.append(f"Level: {level}")
        return "\n".join(parts)
        
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
        
    def _draw_step_indicators(self, visible_steps: List[str]):
        """Draw step progress indicators"""
        x = 50
        y = 130
        for i, step in enumerate(visible_steps):
            color = DARK_GREEN if i < self.current_step else (GOLD if i == self.current_step else DARK_GRAY)
            pygame.draw.circle(self.screen, color, (x, y), 12)
            
            step_name = self._get_step_names().get(step, step)[:3]
            text = self.small_font.render(step_name, True, WHITE)
            self.screen.blit(text, (x - 10, y + 18))
            
            if i < len(visible_steps) - 1:
                pygame.draw.line(self.screen, DARK_GRAY, (x + 15, y), (x + 55, y), 2)
            x += 70
            
    def _draw_features(self):
        """Draw features step"""
        s = self._scale
        w, h = self._w, self._h
        # Start below step indicators (y=130 + text height ~18 + gap)
        label = self.font.render("Новые особенности:", True, WHITE)
        self.screen.blit(label, (_sc(100, s), _sc(160, s)))
        
        # Limit features list area to avoid overlapping with navigation buttons
        btn_y = h - _sc(70, s)
        btn_h = _sc(50, s)
        features_area_bottom = btn_y - _sc(20, s)  # Leave gap before buttons
        
        self.feature_rects = []
        # Start features list below label (y=160 + label height ~30 + gap)
        y = _sc(200, s)
        item_h = _sc(40, s)
        x = _sc(100, s)
        w_list = _sc(600, s)
        item_spacing = _sc(8, s)
        
        # Clip area for features list
        features_area = pygame.Rect(x, y, w_list, features_area_bottom - y)
        clip_save = self.screen.get_clip()
        self.screen.set_clip(features_area)
        
        for feat in self.features_list:
            feat_index = feat.get("index", "")
            feat_name = feat.get("name", feat_index)
            
            if feat_index not in self.features_cache:
                try:
                    self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                except:
                    self.features_cache[feat_index] = {}
            
            chosen_sub = self.build.feature_choices.get(feat_index)
            if chosen_sub:
                try:
                    subfeat_data = self.db.get(f"/features/{chosen_sub}.json")
                    feat_name = f"{feat_name} → {subfeat_data.get('name', chosen_sub)}"
                except:
                    pass
            else:
                feat_data = self.features_cache.get(feat_index, {})
                feature_specific = feat_data.get("feature_specific", {})
                if feature_specific.get("subfeature_options"):
                    feat_name = f"{feat_name} [выберите]"
            
            rect = pygame.Rect(x, y, w_list, item_h)
            
            # Only draw if visible and not overlapping buttons
            if rect.bottom <= features_area_bottom:
                self.feature_rects.append((rect, feat_index))
                
                bg = HOVER_COLOR if rect.collidepoint(pygame.mouse.get_pos()) else DARK_GRAY
                pygame.draw.rect(self.screen, bg, rect, border_radius=6)
                pygame.draw.rect(self.screen, GOLD, rect, width=1, border_radius=6)
                
                txt = self.small_font.render(feat_name[:60], True, WHITE)
                self.screen.blit(txt, (rect.x + 10, rect.centery - txt.get_height() // 2))
            
            y += item_h + item_spacing
            
            # Stop if we've reached the button area
            if y >= features_area_bottom:
                break
        
        self.screen.set_clip(clip_save)
            
    def _draw_subfeature_modal(self):
        """Draw modal for choosing subfeature"""
        s = self._scale
        w, h = self._w, self._h
        mw, mh = _sc(500, s), _sc(450, s)  # Increased height to accommodate button
        mr = pygame.Rect(w // 2 - mw // 2, h // 2 - mh // 2, mw, mh)
        
        # Overlay
        overlay = pygame.Surface((w, h))
        overlay.set_alpha(180)
        overlay.fill(BLACK)
        self.screen.blit(overlay, (0, 0))
        
        # Modal
        pygame.draw.rect(self.screen, MODAL_BG, mr, border_radius=12)
        pygame.draw.rect(self.screen, GOLD, mr, width=2, border_radius=12)
        
        # Title
        feat_name = "Выберите подособенность"
        if self._subfeature_modal_feature:
            try:
                feat_data = self.db.get(f"/features/{self._subfeature_modal_feature}.json")
                feat_name = feat_data.get("name", self._subfeature_modal_feature)
            except:
                pass
        title = self.header_font.render(feat_name, True, GOLD)
        self.screen.blit(title, (mr.centerx - title.get_width() // 2, mr.y + _sc(20, s)))
        
        # Selection info
        info_text = f"Выберите {self._subfeature_modal_choose} ({len(self._subfeature_modal_selected)}/{self._subfeature_modal_choose}):"
        info_surf = self.small_font.render(info_text, True, LIGHT_GRAY)
        self.screen.blit(info_surf, (mr.x + _sc(20, s), mr.y + _sc(50, s)))
        
        # Confirm button area (reserve space at bottom)
        btn_h = _sc(40, s)
        btn_padding = _sc(20, s)
        btn_y = mr.bottom - btn_h - btn_padding
        
        # Options list area (between info and button)
        list_top = mr.y + _sc(80, s)
        list_bottom = btn_y - _sc(10, s)  # Leave gap before button
        list_area = pygame.Rect(mr.x + _sc(20, s), list_top, mr.w - _sc(40, s), list_bottom - list_top)
        
        # Options list with clipping
        item_h = _sc(36, s)
        item_spacing = _sc(6, s)
        total_item_h = item_h + item_spacing
        
        # Calculate scroll limits
        total_height = len(self._subfeature_modal_options) * total_item_h
        max_scroll = max(0, total_height - list_area.height)
        self._subfeature_modal_scroll = max(0, min(self._subfeature_modal_scroll, max_scroll))
        
        # Draw options with clipping
        clip_save = self.screen.get_clip()
        self.screen.set_clip(list_area)
        
        y = list_area.y - self._subfeature_modal_scroll
        for opt in self._subfeature_modal_options:
            opt_index = opt.get("index", "")
            opt_name = opt.get("name", opt_index)
            selected = opt_index in self._subfeature_modal_selected
            
            rr = pygame.Rect(list_area.x, y, list_area.w, item_h)
            
            # Only draw if visible
            if rr.bottom >= list_area.y and rr.y <= list_area.bottom:
                bg = DARK_GREEN if selected else (HOVER_COLOR if rr.collidepoint(pygame.mouse.get_pos()) else DARK_GRAY)
                pygame.draw.rect(self.screen, bg, rr, border_radius=6)
                pygame.draw.rect(self.screen, GOLD, rr, width=1, border_radius=6)
                
                txt = self.small_font.render(opt_name[:50], True, WHITE)
                self.screen.blit(txt, (rr.x + 10, rr.centery - txt.get_height() // 2))
            
            y += total_item_h
        
        self.screen.set_clip(clip_save)
        
        # Scrollbar if needed
        if max_scroll > 0:
            scrollbar_w = _sc(8, s)
            scrollbar_x = list_area.right + _sc(4, s)
            scrollbar_track = pygame.Rect(scrollbar_x, list_area.y, scrollbar_w, list_area.height)
            scrollbar_thumb_h = max(_sc(20, s), int(list_area.height * (list_area.height / total_height)))
            scrollbar_thumb_y = list_area.y + int((self._subfeature_modal_scroll / max_scroll) * (list_area.height - scrollbar_thumb_h))
            scrollbar_thumb = pygame.Rect(scrollbar_x, scrollbar_thumb_y, scrollbar_w, scrollbar_thumb_h)
            
            pygame.draw.rect(self.screen, DARK_GRAY, scrollbar_track, border_radius=4)
            pygame.draw.rect(self.screen, GOLD, scrollbar_thumb, border_radius=4)
        
        # Confirm button (draw after list, outside clipping)
        btn_w = _sc(120, s)
        confirm_rect = pygame.Rect(mr.centerx - btn_w // 2, btn_y, btn_w, btn_h)
        can_confirm = len(self._subfeature_modal_selected) == self._subfeature_modal_choose
        bg = GOLD if can_confirm else DARK_GRAY
        pygame.draw.rect(self.screen, bg, confirm_rect, border_radius=6)
        pygame.draw.rect(self.screen, GOLD, confirm_rect, width=2, border_radius=6)
        confirm_text_str = loc.get("confirm", "Готово")
        confirm_txt = self.font.render(confirm_text_str, True, WHITE if can_confirm else LIGHT_GRAY)
        self.screen.blit(confirm_txt, confirm_txt.get_rect(center=confirm_rect.center))
        
    def _draw_abilities(self):
        """Draw abilities step"""
        s = self._scale
        total_used = sum(self.build.abilities.values())
        remaining = self.build.ability_score_bonuses - total_used
        
        info_text = f"Очки улучшения: {total_used} / {self.build.ability_score_bonuses}"
        if remaining > 0:
            info_text += f" (осталось: {remaining})"
        if self.build.ability_score_bonuses == 2:
            info_text += " (можно +2 к одной или +1 к двум)"
        info_surface = self.font.render(info_text, True, WHITE)
        # Start below step indicators (y=130 + text height ~18 + gap)
        self.screen.blit(info_surface, (100, _sc(160, s)))
        
        for ability, counter in self.ability_counters.items():
            value = self.build.abilities[ability]
            current_ability = getattr(self.player.abilities, ability)
            # Calculate new modifier with improvement
            new_score = current_ability + value
            new_modifier = (new_score - 10) // 2
            can_increase = total_used < self.build.ability_score_bonuses and current_ability < 20
            can_decrease = value > 0
            counter.draw(self.screen, new_score, new_modifier, can_increase, can_decrease)
            
    def _draw_cantrips(self):
        """Draw cantrips step"""
        s = self._scale
        w, h = self._w, self._h
        spellcasting_info = self.level_data.get("spellcasting", {})
        cantrips_known = spellcasting_info.get("cantrips_known", 0)
        current_cantrips = len([s for s in self.player.sc.learned_spells if s.level == 0])
        needed = cantrips_known - current_cantrips
        
        # Label with counter like in character creation
        # Start below step indicators (y=130 + text height ~18 + gap)
        label_text = f"Выберите новые заговоры ({len(self.build.new_cantrips)}/{needed}):"
        label = self.font.render(label_text, True, WHITE)
        self.screen.blit(label, (100, _sc(160, s)))
        
        self.cantrip_list.draw(self.screen)
        
        # Selected cantrips list - start below the available list
        list_bottom = self.cantrip_list.rect.bottom
        selected_start_y = list_bottom + _sc(20, s)  # Gap after list
        
        # Limit selected list area to avoid overlapping with navigation buttons
        btn_y = h - _sc(70, s)
        selected_area_bottom = btn_y - _sc(20, s)  # Leave gap before buttons
        
        selected_label = self.font.render("Выбрано:", True, GOLD)
        self.screen.blit(selected_label, (100, selected_start_y))
        
        # Clip area for selected list
        selected_area = pygame.Rect(100, selected_start_y + _sc(30, s), _sc(600, s), selected_area_bottom - (selected_start_y + _sc(30, s)))
        clip_save = self.screen.get_clip()
        self.screen.set_clip(selected_area)
        
        y = selected_start_y + _sc(30, s)
        for cantrip_index in self.build.new_cantrips:
            if y >= selected_area_bottom:
                break
            try:
                spell_data = self.db.get(f"/spells/{cantrip_index}.json")
                spell_name = spell_data.get("name", cantrip_index)
            except:
                spell_name = cantrip_index
            text = self.small_font.render(f"• {spell_name}", True, WHITE)
            self.screen.blit(text, (110, y))
            y += _sc(25, s)
        
        self.screen.set_clip(clip_save)
        
    def _draw_spells(self):
        """Draw spells step"""
        s = self._scale
        w, h = self._w, self._h
        # Label with counter like in character creation
        # Start below step indicators (y=130 + text height ~18 + gap)
        label_text = f"Выберите новые заклинания ({len(self.build.new_spells)}/{self.new_spells_count}):"
        label = self.font.render(label_text, True, WHITE)
        self.screen.blit(label, (100, _sc(160, s)))
        
        self.spell_list.draw(self.screen)
        
        # Selected spells list - start below the available list
        list_bottom = self.spell_list.rect.bottom
        selected_start_y = list_bottom + _sc(20, s)  # Gap after list
        
        # Limit selected list area to avoid overlapping with navigation buttons
        btn_y = h - _sc(70, s)
        selected_area_bottom = btn_y - _sc(20, s)  # Leave gap before buttons
        
        selected_label = self.font.render("Выбрано:", True, GOLD)
        self.screen.blit(selected_label, (100, selected_start_y))
        
        # Clip area for selected list
        selected_area = pygame.Rect(100, selected_start_y + _sc(30, s), _sc(600, s), selected_area_bottom - (selected_start_y + _sc(30, s)))
        clip_save = self.screen.get_clip()
        self.screen.set_clip(selected_area)
        
        y = selected_start_y + _sc(30, s)
        for spell_index in self.build.new_spells:
            if y >= selected_area_bottom:
                break
            try:
                spell_data = self.db.get(f"/spells/{spell_index}.json")
                spell_name = spell_data.get("name", spell_index)
            except:
                spell_name = spell_index
            text = self.small_font.render(f"• {spell_name}", True, WHITE)
            self.screen.blit(text, (110, y))
            y += _sc(25, s)
        
        self.screen.set_clip(clip_save)
        
    def _draw_proficiency_choices(self):
        """Draw proficiency choices step"""
        s = self._scale
        w, h = self._w, self._h
        # Label with counter like in character creation
        # Start below step indicators (y=130 + text height ~18 + gap)
        label_text = f"Выберите навыки ({len(self.build.proficiency_choices_selected)}/{self.proficiency_choose_count}):"
        label = self.font.render(label_text, True, WHITE)
        self.screen.blit(label, (100, _sc(160, s)))
        
        self.proficiency_list.draw(self.screen)
        
        # Selected proficiencies list - start below the available list
        list_bottom = self.proficiency_list.rect.bottom
        selected_start_y = list_bottom + _sc(20, s)  # Gap after list
        
        # Limit selected list area to avoid overlapping with navigation buttons
        btn_y = h - _sc(70, s)
        selected_area_bottom = btn_y - _sc(20, s)  # Leave gap before buttons
        
        selected_label = self.font.render("Выбрано:", True, GOLD)
        self.screen.blit(selected_label, (100, selected_start_y))
        
        # Clip area for selected list
        selected_area = pygame.Rect(100, selected_start_y + _sc(30, s), _sc(600, s), selected_area_bottom - (selected_start_y + _sc(30, s)))
        clip_save = self.screen.get_clip()
        self.screen.set_clip(selected_area)
        
        y = selected_start_y + _sc(30, s)
        for prof_index in self.build.proficiency_choices_selected:
            if y >= selected_area_bottom:
                break
            prof_name = self.proficiency_cache.get(prof_index, prof_index)
            text = self.small_font.render(f"• {prof_name}", True, WHITE)
            self.screen.blit(text, (110, y))
            y += _sc(25, s)
        
        self.screen.set_clip(clip_save)
        
    def _draw_confirmation(self):
        """Draw confirmation/summary step"""
        s = self._scale
        y = _sc(180, s)
        line_h = _sc(30, s)
        
        # Summary of choices
        summary_lines = [
            f"Новый уровень: {self.build.new_level}",
            "",
        ]
        
        if self.build.ability_score_bonuses > 0:
            summary_lines.append("Улучшения характеристик:")
            for ability, bonus in self.build.abilities.items():
                if bonus > 0:
                    ability_name = self.ability_labels.get(ability, ability)
                    summary_lines.append(f"  {ability_name}: +{bonus}")
            summary_lines.append("")
        
        if self.build.features:
            summary_lines.append("Новые особенности:")
            for feat_index in self.build.features:
                try:
                    feat_data = self.db.get(f"/features/{feat_index}.json")
                    feat_name = feat_data.get("name", feat_index)
                    summary_lines.append(f"  • {feat_name}")
                except:
                    summary_lines.append(f"  • {feat_index}")
            summary_lines.append("")
        
        if self.build.new_cantrips:
            summary_lines.append("Новые заговоры:")
            for cantrip_index in self.build.new_cantrips:
                try:
                    spell_data = self.db.get(f"/spells/{cantrip_index}.json")
                    spell_name = spell_data.get("name", cantrip_index)
                    summary_lines.append(f"  • {spell_name}")
                except:
                    summary_lines.append(f"  • {cantrip_index}")
            summary_lines.append("")
        
        if self.build.new_spells:
            summary_lines.append("Новые заклинания:")
            for spell_index in self.build.new_spells:
                try:
                    spell_data = self.db.get(f"/spells/{spell_index}.json")
                    spell_name = spell_data.get("name", spell_index)
                    summary_lines.append(f"  • {spell_name}")
                except:
                    summary_lines.append(f"  • {spell_index}")
            summary_lines.append("")
        
        if self.build.proficiency_choices_selected:
            summary_lines.append("Новые навыки:")
            for prof_index in self.build.proficiency_choices_selected:
                try:
                    prof_data = self.db.get(f"/proficiencies/{prof_index}.json")
                    prof_name = prof_data.get("name", prof_index)
                    summary_lines.append(f"  • {prof_name}")
                except:
                    summary_lines.append(f"  • {prof_index}")
        
        # Draw summary
        for line in summary_lines:
            if line:
                text_surface = self.small_font.render(line, True, WHITE)
                self.screen.blit(text_surface, (100, y))
            y += line_h
