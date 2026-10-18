"""Level-up: per-step pygame handlers."""
import pygame
from typing import Any, Dict, List

from localization import loc


class LevelUpEventsMixin:
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
        
