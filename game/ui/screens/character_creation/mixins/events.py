"""Character creation: per-step input handling."""
import pygame
from typing import Any, Dict, List, Optional

from generators.fantasy_name_generator_base import fantasy_name_generator
from localization import loc


class CharacterCreationEventsMixin:
    def _handle_biography_event(self, event: pygame.event.Event):
        """Handle biography step events"""
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            if self.random_name_btn.is_clicked(event.pos):
                name = fantasy_name_generator.generate_random_name(self.build.race or "human", self.build.gender or "male")
                if name:
                    self.build.name = name
                return
            if self.gender_male_btn.is_clicked(event.pos):
                self.build.gender = "male"
                return
            if self.gender_female_btn.is_clicked(event.pos):
                self.build.gender = "female"
                return
            # Commit and blur age/weight when clicking elsewhere
            if self.age_input_active:
                self.age_input_active = False
                self.build.age = int(self.bio_age_buffer) if self.bio_age_buffer.isdigit() else None
            if self.weight_input_active:
                self.weight_input_active = False
                self.build.weight = int(self.bio_weight_buffer) if self.bio_weight_buffer.isdigit() else None
            if self.age_input_rect.collidepoint(event.pos):
                self.age_input_active = True
                self.bio_age_buffer = str(self.build.age) if self.build.age is not None else ""
                self.name_input_active = False
                return
            if self.weight_input_rect.collidepoint(event.pos):
                self.weight_input_active = True
                self.bio_weight_buffer = str(self.build.weight) if self.build.weight is not None else ""
                self.name_input_active = False
                return
            self.name_input_active = self.name_input_rect.collidepoint(event.pos)
            if self.name_input_active:
                return
                
        if event.type == pygame.KEYDOWN:
            if self.name_input_active:
                nm = self.build.name or ""
                if event.key == pygame.K_BACKSPACE:
                    self.build.name = nm[:-1]
                elif event.key == pygame.K_RETURN:
                    self.name_input_active = False
                elif event.unicode and len(nm) < 30:
                    self.build.name = nm + event.unicode
                return
            if self.age_input_active:
                if event.key == pygame.K_BACKSPACE:
                    self.bio_age_buffer = self.bio_age_buffer[:-1]
                elif event.key == pygame.K_RETURN:
                    self.age_input_active = False
                    self.build.age = int(self.bio_age_buffer) if self.bio_age_buffer.isdigit() else None
                elif event.unicode and event.unicode.isdigit() and len(self.bio_age_buffer) < 4:
                    self.bio_age_buffer += event.unicode
                return
            if self.weight_input_active:
                if event.key == pygame.K_BACKSPACE:
                    self.bio_weight_buffer = self.bio_weight_buffer[:-1]
                elif event.key == pygame.K_RETURN:
                    self.weight_input_active = False
                    self.build.weight = int(self.bio_weight_buffer) if self.bio_weight_buffer.isdigit() else None
                elif event.unicode and event.unicode.isdigit() and len(self.bio_weight_buffer) < 4:
                    self.bio_weight_buffer += event.unicode
                return
                
        if self.alignment_list.handle_event(event):
            selected = self.alignment_list.get_selected()
            if selected:
                self.build.alignment = selected.get("index")
                try:
                    self.alignment_data = self.db.get(f"/alignments/{selected.get('index')}.json")
                except Exception:
                    self.alignment_data = None
                
    def _handle_race_event(self, event: pygame.event.Event):
        """Handle race step events"""
        if self.race_list.handle_event(event):
            selected = self.race_list.get_selected()
            if selected:
                self._load_race_details(selected.get("index"))
                
        # Handle trait hover for tooltip
        if event.type == pygame.MOUSEMOTION:
            mouse_pos = event.pos
            tooltip_shown = False
            for rect, trait_index in self.trait_rects:
                if rect.collidepoint(mouse_pos):
                    # Load trait data if not cached
                    if trait_index not in self.traits_cache:
                        try:
                            self.traits_cache[trait_index] = self.db.get(f"/traits/{trait_index}.json")
                        except:
                            self.traits_cache[trait_index] = {"name": trait_index, "desc": ["No description"]}
                    
                    trait_data = self.traits_cache[trait_index]
                    desc = trait_data.get("desc", [""])
                    if isinstance(desc, list):
                        desc = " ".join(desc)
                    self.tooltip.show(trait_data.get("name", ""), desc, mouse_pos)
                    tooltip_shown = True
                    break
                    
            if not tooltip_shown:
                self.tooltip.hide()
                
    def _handle_subrace_event(self, event: pygame.event.Event):
        """Handle subrace step events"""
        if self.subrace_list.handle_event(event):
            selected = self.subrace_list.get_selected()
            if selected:
                self.build.subrace = selected.get("index")
                try:
                    self.build.subrace_data = self.db.get(f"/subraces/{selected.get('index')}.json")
                except:
                    pass
                    
        # Handle trait hover for tooltip (racial_traits for subraces)
        if event.type == pygame.MOUSEMOTION:
            mouse_pos = event.pos
            tooltip_shown = False
            for rect, trait_index in self.trait_rects:
                if rect.collidepoint(mouse_pos):
                    # Load trait data if not cached
                    if trait_index not in self.traits_cache:
                        try:
                            self.traits_cache[trait_index] = self.db.get(f"/traits/{trait_index}.json")
                        except:
                            self.traits_cache[trait_index] = {"name": trait_index, "desc": ["No description"]}
                    
                    trait_data = self.traits_cache[trait_index]
                    desc = trait_data.get("desc", [""])
                    if isinstance(desc, list):
                        desc = " ".join(desc)
                    self.tooltip.show(trait_data.get("name", ""), desc, mouse_pos)
                    tooltip_shown = True
                    break
                    
            if not tooltip_shown:
                self.tooltip.hide()
                    
    def _handle_class_event(self, event: pygame.event.Event):
        """Handle class step events"""
        if self.class_list.handle_event(event):
            selected = self.class_list.get_selected()
            if selected:
                self._load_class_details(selected.get("index"))
    
    def _handle_features_event(self, event: pygame.event.Event):
        """Handle features step: tooltip on hover, click to choose subfeature if needed."""
        # Don't handle events if modal is active
        if self._subfeature_modal_active:
            return
        
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mouse_pos = event.pos
            for rect, feat_index in self.feature_rects:
                if rect.collidepoint(mouse_pos):
                    # Load feature data
                    if feat_index not in self.features_cache:
                        try:
                            self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                        except:
                            self.features_cache[feat_index] = {"name": feat_index, "desc": ["No description"]}
                    
                    feat_data = self.features_cache[feat_index]
                    # Check if feature has subfeature_options
                    feature_specific = feat_data.get("feature_specific", {})
                    subfeature_opts = feature_specific.get("subfeature_options", {})
                    if subfeature_opts:
                        # Always allow selection (including re-selection)
                        # Show modal to choose subfeature
                        self._show_subfeature_choice_modal(feat_index, feat_data, subfeature_opts)
                    break
        
        # Tooltip on hover (only if modal is not active)
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
                    # Show chosen subfeature if selected
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
        elif event.type == pygame.MOUSEMOTION and self._subfeature_modal_active:
            # Hide tooltip when modal is active
            self.tooltip.hide()
                
    def _show_subfeature_choice_modal(self, feature_index: str, feature_data: Dict, subfeature_opts: Dict):
        """Show modal to choose subfeature. Stores choice in self._pending_subfeature_choice."""
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
        # Pre-select already chosen subfeature if exists
        already_chosen = self.build.feature_choices.get(feature_index)
        self._subfeature_modal_selected = [already_chosen] if already_chosen and already_chosen in [opt.get("index") for opt in subfeatures] else []
                
    def _handle_cantrips_event(self, event: pygame.event.Event):
        """Handle cantrips selection: scroll, tooltip on hover, click-to-toggle."""
        clicked = self.spell_list.handle_event(event)
        if clicked and event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            item = self.spell_list.get_selected()
            if item:
                idx = item.get("index")
                if idx is not None:
                    if idx in self.build.cantrips:
                        self.build.cantrips.remove(idx)
                    elif len(self.build.cantrips) < self.build.cantrips_known:
                        self.build.cantrips.append(idx)
        if event.type == pygame.MOUSEMOTION:
            in_list = (self.spell_list.rect.collidepoint(event.pos) and not self.spell_list._is_in_scrollbar(event.pos)
                       and 0 <= self.spell_list.hovered_index < len(self.spell_list.items))
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
                    self.tooltip.show(d.get("name", ""), self._format_spell_tooltip(d), event.pos)
                else:
                    self.tooltip.hide()
            else:
                self.tooltip.hide()
                
    def _handle_spells_event(self, event: pygame.event.Event):
        """Handle spells selection: scroll, tooltip on hover, click-to-toggle."""
        clicked = self.spell_list.handle_event(event)
        if clicked and event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            item = self.spell_list.get_selected()
            if item:
                idx = item.get("index")
                if idx is not None:
                    if idx in self.build.spells:
                        self.build.spells.remove(idx)
                    elif len(self.build.spells) < self.build.spells_known:
                        self.build.spells.append(idx)
        if event.type == pygame.MOUSEMOTION:
            in_list = (self.spell_list.rect.collidepoint(event.pos) and not self.spell_list._is_in_scrollbar(event.pos)
                       and 0 <= self.spell_list.hovered_index < len(self.spell_list.items))
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
                    self.tooltip.show(d.get("name", ""), self._format_spell_tooltip(d), event.pos)
                else:
                    self.tooltip.hide()
            else:
                self.tooltip.hide()
                
    def _handle_proficiency_choices_event(self, event: pygame.event.Event):
        """Handle proficiency choices: scroll, tooltip on hover, click-to-toggle."""
        clicked = self.spell_list.handle_event(event)
        if clicked and event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            item = self.spell_list.get_selected()
            if item and (idx := item.get("index")) is not None:
                if idx in self.build.proficiency_choices_selected:
                    self.build.proficiency_choices_selected.remove(idx)
                elif len(self.build.proficiency_choices_selected) < self.build.proficiency_choose:
                    self.build.proficiency_choices_selected.append(idx)
        if event.type == pygame.MOUSEMOTION:
            in_list = (self.spell_list.rect.collidepoint(event.pos) and not self.spell_list._is_in_scrollbar(event.pos)
                       and 0 <= self.spell_list.hovered_index < len(self.spell_list.items))
            if in_list:
                it = self.spell_list.items[self.spell_list.hovered_index]
                pid = it.get("index")
                if pid is not None:
                    txt = self._get_proficiency_tooltip_text(pid)
                    self.tooltip.show(it.get("name", ""), txt, event.pos)
                else:
                    self.tooltip.hide()
            else:
                self.tooltip.hide()
                
    def _handle_background_event(self, event: pygame.event.Event):
        """Handle background step events"""
        if self.background_list.handle_event(event):
            selected = self.background_list.get_selected()
            if selected:
                self._load_background_details(selected.get("index"))
                
    def _handle_abilities_event(self, event: pygame.event.Event):
        """Handle abilities step events"""
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            for ability, counter in self.ability_counters.items():
                action = counter.handle_click(event.pos)
                if action == "increase":
                    self.build.increase_ability(ability)
                elif action == "decrease":
                    self.build.decrease_ability(ability)

    def _handle_confirmation_event(self, event: pygame.event.Event):
        """Handle confirmation step: scroll (wheel, scrollbar drag)."""
        pr = self._confirmation_panel_rect
        ch = getattr(self, "_confirmation_content_height", 0)
        if not pr:
            return
        mx = max(0, ch - pr.height)
        sb_left = pr.right - SelectionList.SCROLLBAR_WIDTH - SelectionList.SCROLLBAR_PAD

        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            if pr.collidepoint(event.pos) and event.pos[0] >= sb_left and mx > 0:
                track, thumb = self._confirmation_scrollbar_rects()
                if thumb and thumb.collidepoint(event.pos):
                    self._confirmation_scroll_dragging = True
                    self._confirmation_scroll_start_y = event.pos[1]
        elif event.type == pygame.MOUSEBUTTONUP and event.button == 1:
            self._confirmation_scroll_dragging = False
        elif event.type == pygame.MOUSEMOTION and self._confirmation_scroll_dragging and mx > 0:
            track, thumb = self._confirmation_scrollbar_rects()
            if track and thumb:
                rel = event.pos[1] - track.y
                t = max(0, min(1, rel / (track.height - thumb.height))) if track.height > thumb.height else 0
                self.confirmation_scroll_offset = int(t * mx)
        elif event.type == pygame.MOUSEWHEEL and pr.collidepoint(pygame.mouse.get_pos()) and mx > 0:
            step = 40
            if event.y > 0:
                self.confirmation_scroll_offset = max(0, self.confirmation_scroll_offset - step)
            else:
                self.confirmation_scroll_offset = min(mx, self.confirmation_scroll_offset + step)

