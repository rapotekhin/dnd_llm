"""Character creation: rendering and layout helpers."""
import pygame
from typing import Any, Dict, List

from ..colors import *
from localization import loc

from .widgets import AbilityCounter, SelectionList, _sc


class CharacterCreationDrawingMixin:
    def _confirmation_scrollbar_rects(self) -> tuple:
        """(track_rect, thumb_rect) for confirmation panel. Uses panel rect and content height."""
        pr = self._confirmation_panel_rect
        ch = getattr(self, "_confirmation_content_height", 0)
        if not pr or ch <= pr.height:
            return (None, None)
        sbw = SelectionList.SCROLLBAR_WIDTH
        pad = SelectionList.SCROLLBAR_PAD
        rx = pr.right - sbw - pad
        track = pygame.Rect(rx, pr.y + pad, sbw, pr.height - 2 * pad)
        visible = pr.height / max(1, ch)
        thumb_h = max(24, int(track.height * visible))
        mx = ch - pr.height
        thumb_y = track.y + int((self.confirmation_scroll_offset / mx) * (track.height - thumb_h))
        thumb = pygame.Rect(rx, thumb_y, sbw, thumb_h)
        return (track, thumb)
    def _draw_step_indicators(self, visible_steps: List[str]):
        """Draw step progress indicators"""
        x = 50
        y = 90
        for i, step in enumerate(visible_steps):
            color = DARK_GREEN if i < self.current_step else (GOLD if i == self.current_step else DARK_GRAY)
            pygame.draw.circle(self.screen, color, (x, y), 12)
            
            step_name = self._get_step_names().get(step, step)[:3]
            text = self.small_font.render(step_name, True, WHITE)
            self.screen.blit(text, (x - 10, y + 18))
            
            if i < len(visible_steps) - 1:
                pygame.draw.line(self.screen, DARK_GRAY, (x + 15, y), (x + 55, y), 2)
            x += 70
            
    def _draw_biography(self):
        """Draw biography step"""
        s = self._scale
        w, h = self._w, self._h
        
        # Limit area to avoid overlapping with navigation buttons
        btn_y = h - _sc(70, s)
        content_area_bottom = btn_y - _sc(20, s)  # Leave gap before buttons
        
        # Name input
        name_label = self.font.render(f"{loc['char_name']}:", True, WHITE)
        self.screen.blit(name_label, (100, 148))
        
        pygame.draw.rect(self.screen, INPUT_BG, self.name_input_rect, border_radius=6)
        border_color = GOLD if self.name_input_active else LIGHT_GRAY
        pygame.draw.rect(self.screen, border_color, self.name_input_rect, width=2, border_radius=6)
        
        name_text = self.font.render(self.build.name or loc["char_name_placeholder"], True, 
                                      WHITE if self.build.name else LIGHT_GRAY)
        self.screen.blit(name_text, (self.name_input_rect.x + 10, self.name_input_rect.centery - 10))
        
        self.random_name_btn.draw(self.screen)
        
        # Gender - position label above buttons to avoid overlap
        gender_label = self.font.render(f"{loc['gender']}:", True, WHITE)
        gender_label_y = self.gender_male_btn.rect.y - _sc(25, s)  # Above buttons
        self.screen.blit(gender_label, (100, gender_label_y))
        for btn in (self.gender_male_btn, self.gender_female_btn):
            btn.draw(self.screen)
        male_sel = (self.build.gender or "").lower() == "male"
        female_sel = (self.build.gender or "").lower() == "female"
        if male_sel:
            pygame.draw.rect(self.screen, GOLD, self.gender_male_btn.rect, width=3, border_radius=8)
        if female_sel:
            pygame.draw.rect(self.screen, GOLD, self.gender_female_btn.rect, width=3, border_radius=8)
        
        # Age - position label above input to avoid overlap
        age_label = self.font.render(f"{loc['age']}:", True, WHITE)
        age_label_y = self.age_input_rect.y - _sc(25, s)  # Above input
        self.screen.blit(age_label, (100, age_label_y))
        pygame.draw.rect(self.screen, INPUT_BG, self.age_input_rect, border_radius=6)
        bc = GOLD if self.age_input_active else LIGHT_GRAY
        pygame.draw.rect(self.screen, bc, self.age_input_rect, width=2, border_radius=6)
        age_val = self.bio_age_buffer if self.age_input_active else (str(self.build.age) if self.build.age is not None else "")
        age_text = self.font.render(age_val or "—", True, WHITE if age_val else LIGHT_GRAY)
        self.screen.blit(age_text, (self.age_input_rect.x + 10, self.age_input_rect.centery - 10))
        
        # Weight - position label above input to avoid overlap
        weight_label = self.font.render(f"{loc['weight']} ({loc['weight_unit']}):", True, WHITE)
        weight_label_y = self.weight_input_rect.y - _sc(25, s)  # Above input
        self.screen.blit(weight_label, (200, weight_label_y))
        pygame.draw.rect(self.screen, INPUT_BG, self.weight_input_rect, border_radius=6)
        bc = GOLD if self.weight_input_active else LIGHT_GRAY
        pygame.draw.rect(self.screen, bc, self.weight_input_rect, width=2, border_radius=6)
        weight_val = self.bio_weight_buffer if self.weight_input_active else (str(self.build.weight) if self.build.weight is not None else "")
        weight_text = self.font.render(weight_val or "—", True, WHITE if weight_val else LIGHT_GRAY)
        self.screen.blit(weight_text, (self.weight_input_rect.x + 10, self.weight_input_rect.centery - 10))
        
        # Alignment - position label above list
        align_label = self.font.render(f"{loc['alignment']}:", True, WHITE)
        # Calculate safe area for alignment list
        alignment_list_y = _sc(360, s)  # Start below age/weight inputs
        alignment_label_y = alignment_list_y - _sc(25, s)  # Label above list
        self.screen.blit(align_label, (100, alignment_label_y))
        
        # Limit alignment list height to avoid overlapping with buttons and stay within screen
        alignment_list_max_height = content_area_bottom - alignment_list_y
        alignment_list_height = max(_sc(100, s), min(320, alignment_list_max_height))  # At least 100px, max 320px
        
        # Update alignment list rect if needed
        if hasattr(self.alignment_list, 'rect'):
            self.alignment_list.rect.y = alignment_list_y
            self.alignment_list.rect.height = alignment_list_height
        
        # Draw alignment list with clipping
        clip_save = self.screen.get_clip()
        alignment_list_rect = pygame.Rect(100, alignment_list_y, 350, alignment_list_height)
        self.screen.set_clip(alignment_list_rect)
        self.alignment_list.draw(self.screen)
        self.screen.set_clip(clip_save)
        
        # Alignment description panel (right side, same vertical as alignment list)
        if self.alignment_data:
            # Limit panel height to avoid overlapping with buttons
            panel_max_height = content_area_bottom - alignment_list_y
            panel_height = min(320, panel_max_height)
            self._draw_info_panel(500, alignment_list_y, self.alignment_data, height=panel_height)
        
    def _draw_race(self):
        """Draw race step"""
        self.race_list.draw(self.screen)
        
        # Race info panel (description) and stats panel
        if self.build.race_data:
            self._draw_info_panel(470, 150, self.build.race_data)
            self._draw_race_stats_panel(850, 150, self.build.race_data)
            
    def _draw_subrace(self):
        """Draw subrace step"""
        self.subrace_list.draw(self.screen)
        
        if self.build.subrace_data:
            self._draw_info_panel(470, 150, self.build.subrace_data)
            self._draw_subrace_stats_panel(850, 150, self.build.subrace_data)
            
    def _draw_class(self):
        """Draw class step"""
        self.class_list.draw(self.screen)
        
        if self.build.class_data:
            self._draw_info_panel(470, 150, self.build.class_data)
            self._draw_class_stats_panel(850, 150, self.build.class_data)
    
    def _draw_features(self):
        """Draw features step - list of level 1 features with tooltip support"""
        s = self._scale
        w, h = self._w, self._h
        label = self.font.render("Классовые особенности (уровень 1):", True, WHITE)
        self.screen.blit(label, (_sc(100, s), _sc(130, s)))
        
        # Limit features list area to avoid overlapping with navigation buttons
        btn_y = h - _sc(70, s)
        btn_h = _sc(50, s)
        features_area_bottom = btn_y - _sc(20, s)  # Leave gap before buttons
        
        self.feature_rects = []
        y = _sc(180, s)
        item_h = _sc(40, s)
        x = _sc(100, s)
        w_list = _sc(600, s)
        item_spacing = _sc(8, s)
        
        # Clip area for features list
        features_area = pygame.Rect(x, y, w_list, features_area_bottom - y)
        clip_save = self.screen.get_clip()
        self.screen.set_clip(features_area)
        
        # Show all features from level 1, mark which need choice
        for feat in self.features_list:
            feat_index = feat.get("index", "")
            feat_name = feat.get("name", feat_index)
            
            # Load feature data for checking subfeature options
            if feat_index not in self.features_cache:
                try:
                    self.features_cache[feat_index] = self.db.get(f"/features/{feat_index}.json")
                except:
                    self.features_cache[feat_index] = {}
            
            # Check if subfeature was chosen
            chosen_sub = self.build.feature_choices.get(feat_index)
            if chosen_sub:
                try:
                    subfeat_data = self.db.get(f"/features/{chosen_sub}.json")
                    feat_name = f"{feat_name} → {subfeat_data.get('name', chosen_sub)}"
                except:
                    pass
            else:
                # Check if feature needs subfeature choice
                feat_data = self.features_cache.get(feat_index, {})
                feature_specific = feat_data.get("feature_specific", {})
                if feature_specific.get("subfeature_options"):
                    feat_name = f"{feat_name} [выберите]"
            
            rect = pygame.Rect(x, y, w_list, item_h)
            
            # Only draw if visible and not overlapping buttons
            if rect.bottom <= features_area_bottom:
                self.feature_rects.append((rect, feat_index))
                
                # Draw feature item
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
                    # Save choice
                    if self._subfeature_modal_feature:
                        # Store first selected (or all if choose > 1)
                        chosen = self._subfeature_modal_selected[0] if self._subfeature_modal_selected else None
                        if chosen:
                            self.build.feature_choices[self._subfeature_modal_feature] = chosen
                            # Replace parent feature with chosen subfeature in features list
                            if self._subfeature_modal_feature in self.build.features:
                                idx = self.build.features.index(self._subfeature_modal_feature)
                                self.build.features[idx] = chosen
                            elif chosen not in self.build.features:
                                self.build.features.append(chosen)
                    self._subfeature_modal_active = False
            
    def _draw_cantrips(self):
        """Draw cantrips selection"""
        s = self._scale
        w, h = self._w, self._h
        label = self.font.render(f"{loc['select_cantrips']} ({len(self.build.cantrips)}/{self.build.cantrips_known}):", True, WHITE)
        self.screen.blit(label, (100, 130))
        
        self.spell_list.set_items(self.cantrips if hasattr(self, 'cantrips') else [])
        self.spell_list.selected_indices = set(self.build.cantrips)
        self.spell_list.draw(self.screen)
        
        # Selected cantrips - start below the available list
        list_bottom = self.spell_list.rect.bottom
        selected_start_y = list_bottom + _sc(20, s)  # Gap after list
        
        # Limit selected list area to avoid overlapping with navigation buttons
        btn_y = h - _sc(70, s)
        selected_area_bottom = btn_y - _sc(20, s)  # Leave gap before buttons
        
        selected_label = self.font.render(f"{loc['selected']}:", True, GOLD)
        self.screen.blit(selected_label, (100, selected_start_y))
        
        # Clip area for selected list
        selected_area = pygame.Rect(100, selected_start_y + _sc(30, s), _sc(600, s), selected_area_bottom - (selected_start_y + _sc(30, s)))
        clip_save = self.screen.get_clip()
        self.screen.set_clip(selected_area)
        
        y = selected_start_y + _sc(30, s)
        for cantrip in self.build.cantrips:
            if y >= selected_area_bottom:
                break
            text = self.small_font.render(f"• {cantrip}", True, WHITE)
            self.screen.blit(text, (110, y))
            y += _sc(25, s)
        
        self.screen.set_clip(clip_save)
            
    def _draw_spells(self):
        """Draw spells selection"""
        s = self._scale
        w, h = self._w, self._h
        label = self.font.render(f"{loc['select_spells']} ({len(self.build.spells)}/{self.build.spells_known}):", True, WHITE)
        self.screen.blit(label, (100, 130))
        
        self.spell_list.set_items(self.level_1_spells if hasattr(self, 'level_1_spells') else [])
        self.spell_list.selected_indices = set(self.build.spells)
        self.spell_list.draw(self.screen)
        
        # Selected spells - start below the available list
        list_bottom = self.spell_list.rect.bottom
        selected_start_y = list_bottom + _sc(20, s)  # Gap after list
        
        # Limit selected list area to avoid overlapping with navigation buttons
        btn_y = h - _sc(70, s)
        selected_area_bottom = btn_y - _sc(20, s)  # Leave gap before buttons
        
        selected_label = self.font.render(f"{loc['selected']}:", True, GOLD)
        self.screen.blit(selected_label, (100, selected_start_y))
        
        # Clip area for selected list
        selected_area = pygame.Rect(100, selected_start_y + _sc(30, s), _sc(600, s), selected_area_bottom - (selected_start_y + _sc(30, s)))
        clip_save = self.screen.get_clip()
        self.screen.set_clip(selected_area)
        
        y = selected_start_y + _sc(30, s)
        for spell in self.build.spells:
            if y >= selected_area_bottom:
                break
            text = self.small_font.render(f"• {spell}", True, WHITE)
            self.screen.blit(text, (110, y))
            y += _sc(25, s)
        
        self.screen.set_clip(clip_save)
            
    def _draw_proficiency_choices(self):
        """Draw proficiency choices (class skills, etc.)."""
        s = self._scale
        w, h = self._w, self._h
        opts = getattr(self, "proficiency_options", [])
        n = self.build.proficiency_choose
        label = self.font.render(
            f"{loc['select_proficiencies']} ({len(self.build.proficiency_choices_selected)}/{n}):",
            True, WHITE
        )
        self.screen.blit(label, (100, 130))
        self.spell_list.set_items(opts)
        self.spell_list.selected_indices = set(self.build.proficiency_choices_selected)
        self.spell_list.draw(self.screen)
        
        # Selected proficiencies - start below the available list
        list_bottom = self.spell_list.rect.bottom
        selected_start_y = list_bottom + _sc(20, s)  # Gap after list
        
        # Limit selected list area to avoid overlapping with navigation buttons
        btn_y = h - _sc(70, s)
        selected_area_bottom = btn_y - _sc(20, s)  # Leave gap before buttons
        
        selected_label = self.font.render(f"{loc['selected']}:", True, GOLD)
        self.screen.blit(selected_label, (100, selected_start_y))
        
        # Clip area for selected list
        selected_area = pygame.Rect(100, selected_start_y + _sc(30, s), _sc(600, s), selected_area_bottom - (selected_start_y + _sc(30, s)))
        clip_save = self.screen.get_clip()
        self.screen.set_clip(selected_area)
        
        y = selected_start_y + _sc(30, s)
        idx_to_name = {it.get("index"): it.get("name", "") for it in opts}
        for pid in self.build.proficiency_choices_selected:
            if y >= selected_area_bottom:
                break
            name = idx_to_name.get(pid, pid)
            text = self.small_font.render(f"• {name}", True, WHITE)
            self.screen.blit(text, (110, y))
            y += _sc(25, s)
        
        self.screen.set_clip(clip_save)
            
    def _draw_background(self):
        """Draw background step"""
        self.background_list.draw(self.screen)
        
        if self.build.background_data:
            self._draw_info_panel(500, 150, self.build.background_data)
            
    def _draw_abilities(self):
        """Draw abilities step"""
        s = self._scale
        w, h = self._w, self._h
        
        # Limit area to avoid overlapping with navigation buttons
        btn_y = h - _sc(70, s)
        content_area_bottom = btn_y - _sc(20, s)
        
        # Points remaining - position below step indicators if any, or at safe position
        points_text = self.font.render(f"{loc['points']}: {self.build.points_remaining}/27", True, GOLD)
        points_y = _sc(160, s)  # Below step indicators area
        self.screen.blit(points_text, (150, points_y))
        
        # Ability counters - start below points text
        ability_start_y = points_y + _sc(40, s)
        ability_spacing = _sc(50, s)
        
        # Ability counters
        for i, (ability, counter) in enumerate(self.ability_counters.items()):
            # Update counter y position
            counter.y = ability_start_y + i * ability_spacing
            
            # Check if counter would go beyond safe area
            if counter.y + _sc(40, s) > content_area_bottom:
                break
                
            value = self.build.abilities[ability]
            modifier = self.build.get_ability_modifier(ability)
            can_inc = self.build.can_increase_ability(ability)
            can_dec = self.build.can_decrease_ability(ability)
            counter.draw(self.screen, value, modifier, can_inc, can_dec)
            
        # Racial bonuses info
        if self.build.race_data:
            y = 500
            bonuses_label = self.font.render(f"{loc['racial_bonuses']}:", True, GOLD)
            self.screen.blit(bonuses_label, (150, y))
            y += 30
            for bonus in self.build.race_data.get("ability_bonuses", []):
                ab_name = bonus.get("ability_score", {}).get("name", "")
                ab_bonus = bonus.get("bonus", 0)
                text = self.small_font.render(f"+{ab_bonus} {ab_name}", True, DARK_GREEN)
                self.screen.blit(text, (160, y))
                y += 25
                
    def _draw_info_panel(self, x: int, y: int, data: Dict[str, Any], width: int = 350, height: int = 450):
        """Draw info panel for selected item"""
        panel_rect = pygame.Rect(x, y, width, height)
        pygame.draw.rect(self.screen, MODAL_BG, panel_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, panel_rect, width=2, border_radius=8)
        
        # Name
        name = data.get("name", "")
        name_surface = self.header_font.render(name, True, GOLD)
        self.screen.blit(name_surface, (x + 15, y + 15))
        
        # Description or other info
        desc = data.get("desc", data.get("alignment", ""))
        if isinstance(desc, list):
            desc = " ".join(desc) if desc else ""
            
        # Word wrap description
        words = str(desc)[:800].split()
        lines = []
        current_line = ""
        for word in words:
            test_line = current_line + " " + word if current_line else word
            if self.small_font.size(test_line)[0] < panel_rect.width - 30:
                current_line = test_line
            else:
                if current_line:
                    lines.append(current_line)
                current_line = word
        if current_line:
            lines.append(current_line)
        
        # Clip text area to prevent overflow
        text_area = pygame.Rect(x + 15, y + 60, width - 30, height - 60)
        clip_save = self.screen.get_clip()
        self.screen.set_clip(text_area)
            
        text_y = y + 60
        max_lines = max(1, (height - 60) // 22)
        for line in lines[:max_lines]:
            if text_y + 22 > panel_rect.bottom:
                break
            line_surface = self.small_font.render(line, True, LIGHT_GRAY)
            self.screen.blit(line_surface, (x + 15, text_y))
            text_y += 22
        
        self.screen.set_clip(clip_save)
            
    def _draw_race_stats_panel(self, x: int, y: int, data: Dict[str, Any]):
        """Draw race statistics panel"""
        panel_width = min(_sc(380, self._scale), self._w - x - _sc(20, self._scale))
        panel_rect = pygame.Rect(x, y, panel_width, _sc(450, self._scale))
        pygame.draw.rect(self.screen, MODAL_BG, panel_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, panel_rect, width=2, border_radius=8)
        
        # Header
        header = self.header_font.render(loc["race_stats"], True, GOLD)
        self.screen.blit(header, (x + 15, y + 15))
        
        text_y = y + 55
        
        # Speed
        speed = data.get("speed", 30)
        speed_text = self.font.render(f"{loc['race_speed']}: {speed} {loc['race_speed_unit']}", True, WHITE)
        self.screen.blit(speed_text, (x + 15, text_y))
        text_y += 35
        
        # Size
        size = data.get("size", "Medium")
        size_text = self.font.render(f"{loc['race_size']}: {size}", True, WHITE)
        self.screen.blit(size_text, (x + 15, text_y))
        text_y += 35
        
        # Ability Bonuses
        bonuses = data.get("ability_bonuses", [])
        if bonuses:
            bonus_label = self.font.render(f"{loc['race_ability_bonuses']}:", True, WHITE)
            self.screen.blit(bonus_label, (x + 15, text_y))
            text_y += 28
            for bonus in bonuses:
                ab_name = bonus.get("ability_score", {}).get("name", "")
                ab_bonus = bonus.get("bonus", 0)
                bonus_text = self.small_font.render(f"  +{ab_bonus} {ab_name}", True, DARK_GREEN)
                self.screen.blit(bonus_text, (x + 20, text_y))
                text_y += 22
            text_y += 10
            
        # Languages
        languages = data.get("languages", [])
        if languages:
            lang_label = self.font.render(f"{loc['race_languages']}:", True, WHITE)
            self.screen.blit(lang_label, (x + 15, text_y))
            text_y += 28
            lang_names = [l.get("name", "") for l in languages]
            lang_text = self.small_font.render(f"  {', '.join(lang_names)}", True, LIGHT_GRAY)
            self.screen.blit(lang_text, (x + 20, text_y))
            text_y += 30
            
        # Traits (with hover)
        traits = data.get("traits", [])
        if traits:
            traits_label = self.font.render(f"{loc['race_traits']}:", True, WHITE)
            self.screen.blit(traits_label, (x + 15, text_y))
            text_y += 28
            
            # Clear old trait rects
            self.trait_rects = []
            
            for trait in traits:
                trait_name = trait.get("name", "")
                trait_index = trait.get("index", "")
                
                # Draw trait name with underline (hoverable)
                trait_surface = self.small_font.render(f"  • {trait_name}", True, GOLD)
                trait_rect = trait_surface.get_rect(topleft=(x + 20, text_y))
                
                # Store rect for hover detection
                self.trait_rects.append((trait_rect, trait_index))
                
                self.screen.blit(trait_surface, trait_rect)
                
                # Underline to indicate hoverable
                pygame.draw.line(self.screen, GOLD, 
                               (trait_rect.left + 20, trait_rect.bottom),
                               (trait_rect.right, trait_rect.bottom), 1)
                text_y += 24
                
    def _draw_subrace_stats_panel(self, x: int, y: int, data: Dict[str, Any]):
        """Draw subrace statistics panel"""
        panel_width = min(_sc(380, self._scale), self._w - x - _sc(20, self._scale))
        panel_rect = pygame.Rect(x, y, panel_width, _sc(300, self._scale))
        pygame.draw.rect(self.screen, MODAL_BG, panel_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, panel_rect, width=2, border_radius=8)
        
        # Header
        header = self.header_font.render(loc["subrace_bonuses"], True, GOLD)
        self.screen.blit(header, (x + 15, y + 15))
        
        text_y = y + 55
        
        # Ability Bonuses
        bonuses = data.get("ability_bonuses", [])
        if bonuses:
            bonus_label = self.font.render(f"{loc['race_ability_bonuses']}:", True, WHITE)
            self.screen.blit(bonus_label, (x + 15, text_y))
            text_y += 28
            for bonus in bonuses:
                ab_name = bonus.get("ability_score", {}).get("name", "")
                ab_bonus = bonus.get("bonus", 0)
                bonus_text = self.small_font.render(f"  +{ab_bonus} {ab_name}", True, DARK_GREEN)
                self.screen.blit(bonus_text, (x + 20, text_y))
                text_y += 22
            text_y += 10
            
        # Racial Traits (with hover) - note: subraces use "racial_traits" not "traits"
        traits = data.get("racial_traits", [])
        if traits:
            traits_label = self.font.render(f"{loc['subrace_traits']}:", True, WHITE)
            self.screen.blit(traits_label, (x + 15, text_y))
            text_y += 28
            
            # Clear old trait rects
            self.trait_rects = []
            
            for trait in traits:
                trait_name = trait.get("name", "")
                trait_index = trait.get("index", "")
                
                # Draw trait name with underline (hoverable)
                trait_surface = self.small_font.render(f"  • {trait_name}", True, GOLD)
                trait_rect = trait_surface.get_rect(topleft=(x + 20, text_y))
                
                # Store rect for hover detection
                self.trait_rects.append((trait_rect, trait_index))
                
                self.screen.blit(trait_surface, trait_rect)
                
                # Underline to indicate hoverable
                pygame.draw.line(self.screen, GOLD, 
                               (trait_rect.left + 20, trait_rect.bottom),
                               (trait_rect.right, trait_rect.bottom), 1)
                text_y += 24
                
    def _draw_class_stats_panel(self, x: int, y: int, data: Dict[str, Any]):
        """Draw class statistics panel"""
        panel_width = min(_sc(380, self._scale), self._w - x - _sc(20, self._scale))
        panel_rect = pygame.Rect(x, y, panel_width, _sc(500, self._scale))
        pygame.draw.rect(self.screen, MODAL_BG, panel_rect, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, panel_rect, width=2, border_radius=8)
        
        # Header
        header = self.header_font.render(loc["class_stats"], True, GOLD)
        self.screen.blit(header, (x + 15, y + 15))
        
        text_y = y + 55
        
        # Hit Die
        hit_die = data.get("hit_die", 8)
        hit_die_text = self.font.render(f"{loc['class_hit_die']}: d{hit_die}", True, WHITE)
        self.screen.blit(hit_die_text, (x + 15, text_y))
        text_y += 35
        
        # Saving Throws
        saving_throws = data.get("saving_throws", [])
        if saving_throws:
            st_label = self.font.render(f"{loc['class_saving_throws']}:", True, WHITE)
            self.screen.blit(st_label, (x + 15, text_y))
            text_y += 28
            st_names = [st.get("name", "") for st in saving_throws]
            st_text = self.small_font.render(f"  {', '.join(st_names)}", True, DARK_GREEN)
            self.screen.blit(st_text, (x + 20, text_y))
            text_y += 30
            
        # Proficiencies (grouped by type)
        proficiencies = data.get("proficiencies", [])
        if proficiencies:
            prof_label = self.font.render(f"{loc['class_proficiencies']}:", True, WHITE)
            self.screen.blit(prof_label, (x + 15, text_y))
            text_y += 28
            
            # Group proficiencies by type
            armor = []
            weapons = []
            other = []
            
            for prof in proficiencies:
                name = prof.get("name", "")
                index = prof.get("index", "")
                # Skip saving throws - already shown above
                if "saving-throw" in index:
                    continue
                elif "armor" in index.lower() or "shield" in index.lower():
                    armor.append(name)
                elif "weapon" in index.lower() or index in ["simple-weapons", "martial-weapons"]:
                    weapons.append(name)
                else:
                    other.append(name)
                    
            if armor:
                armor_text = self.small_font.render(f"  {loc['class_armor']}: {', '.join(armor)}", True, LIGHT_GRAY)
                self.screen.blit(armor_text, (x + 20, text_y))
                text_y += 24
            if weapons:
                weap_text = self.small_font.render(f"  {loc['class_weapons']}: {', '.join(weapons)}", True, LIGHT_GRAY)
                self.screen.blit(weap_text, (x + 20, text_y))
                text_y += 24
            if other:
                other_text = self.small_font.render(f"  {loc['class_tools']}: {', '.join(other)}", True, LIGHT_GRAY)
                self.screen.blit(other_text, (x + 20, text_y))
                text_y += 24
            text_y += 10
            
        # Proficiency Choices (skills)
        prof_choices = data.get("proficiency_choices", [])
        for choice in prof_choices:
            choose = choice.get("choose", 0)
            desc = choice.get("desc", "")
            if desc and choose > 0:
                choice_label = self.font.render(f"{loc['class_skill_choices']}:", True, WHITE)
                self.screen.blit(choice_label, (x + 15, text_y))
                text_y += 28
                
                # Wrap desc text if too long
                max_width = panel_width - 40
                words = desc.split()
                lines = []
                current_line = ""
                for word in words:
                    test = current_line + " " + word if current_line else word
                    if self.small_font.size(test)[0] < max_width:
                        current_line = test
                    else:
                        if current_line:
                            lines.append(current_line)
                        current_line = word
                if current_line:
                    lines.append(current_line)
                    
                for line in lines:
                    line_text = self.small_font.render(f"  {line}", True, LIGHT_GRAY)
                    self.screen.blit(line_text, (x + 20, text_y))
                    text_y += 22
                text_y += 10
                break  # Only show first choice
            
        # Spellcasting
        spellcasting = data.get("spellcasting")
        if spellcasting:
            spell_label = self.font.render(f"{loc['class_spellcasting']}:", True, WHITE)
            self.screen.blit(spell_label, (x + 15, text_y))
            text_y += 28
            
            spell_ability = spellcasting.get("spellcasting_ability", {}).get("name", "")
            if spell_ability:
                ability_text = self.small_font.render(f"  {loc['class_spell_ability']}: {spell_ability}", True, GOLD)
                self.screen.blit(ability_text, (x + 20, text_y))
                text_y += 24

    def _truncate_text(self, font: pygame.font.Font, text: str, max_width: int) -> str:
        """Truncate text with '...' if it exceeds max_width."""
        if not text:
            return ""
        if font.size(text)[0] <= max_width:
            return text
        suffix = "..."
        while len(text) > 1 and font.size(text + suffix)[0] > max_width:
            text = text[:-1]
        return text.rstrip() + suffix

    def _wrap_text_lines(self, font: pygame.font.Font, text: str, max_width: int) -> List[str]:
        """Word-wrap text into lines that fit max_width."""
        if not text or max_width <= 0:
            return []
        words = text.split()
        lines = []
        current = ""
        for w in words:
            trial = (current + " " + w).strip() if current else w
            if font.size(trial)[0] <= max_width:
                current = trial
            else:
                if current:
                    lines.append(current)
                current = w
        if current:
            lines.append(current)
        return lines

    def _draw_confirmation(self):
        """Draw confirmation screen: single scrollable panel, truncated/wrapped text."""
        s = self._scale
        panel_x, panel_y = _sc(50, s), _sc(120, s)
        panel_w = self._w - _sc(100, s)
        panel_h = self._h - panel_y - _sc(100, s)  # space for nav buttons
        padding = 20
        row_h = 32
        header_h = 44
        label_w = 220
        value_max_w = panel_w - padding * 2 - label_w - 20
        content_max_w = panel_w - padding * 2

        pr = pygame.Rect(panel_x, panel_y, panel_w, panel_h)
        self._confirmation_panel_rect = pr

        cx = panel_x + padding
        virtual_y = float(panel_y + padding)

        def meas_row(_label_key: str, _value: str, _font=None):
            nonlocal virtual_y
            virtual_y += row_h

        def meas_header(_txt: str):
            nonlocal virtual_y
            if virtual_y > panel_y + padding:
                virtual_y += 12
            virtual_y += header_h

        # Measure content height
        meas_header(loc.get("char_info", "Character Info"))
        meas_row("char_name", self.build.name or "")
        if self.build.alignment:
            try:
                ad = self.db.get(f"/alignments/{self.build.alignment}.json")
                meas_row("alignment", ad.get("name", self.build.alignment) if ad else self.build.alignment)
            except Exception:
                meas_row("alignment", self.build.alignment)
        if self.build.race_data:
            meas_row("step_race", self.build.race_data.get("name", "") or self.build.race or "")
        if self.build.subrace_data:
            meas_row("step_subrace", self.build.subrace_data.get("name", "") or self.build.subrace or "")
        if self.build.class_data:
            meas_row("step_class", self.build.class_data.get("name", "") or self.build.class_type or "")
        if self.build.background_data:
            meas_row("step_background", self.build.background_data.get("name", "") or self.build.background or "")
        meas_header(loc.get("step_abilities", "Abilities"))
        for _ in self.ability_labels:
            virtual_y += row_h
        meas_header(loc.get("proficiencies", "Proficiencies"))
        prof_names = []
        if self.build.class_data:
            for p in self.build.class_data.get("proficiencies", []) or []:
                if isinstance(p, dict):
                    prof_names.append(p.get("name", ""))
        for pid in self.build.proficiency_choices_selected:
            try:
                pd = self.db.get(f"/proficiencies/{pid}.json")
                prof_names.append(pd.get("name", pid))
            except Exception:
                prof_names.append(pid)
        if self.build.background_data:
            for bp in self.build.background_data.get("starting_proficiencies", []) or []:
                if isinstance(bp, dict):
                    prof_names.append(bp.get("name", ""))
        if prof_names:
            prof_text = ", ".join(prof_names)
            for _ in self._wrap_text_lines(self.small_font, prof_text, content_max_w - 20):
                virtual_y += 22
        else:
            virtual_y += 22
        if self.build.class_data and self.build.class_data.get("spellcasting"):
            meas_header(loc.get("spells", "Spells"))
            for _ in [self.build.cantrips, self.build.spells, self.build.prepared_spells]:
                if _:
                    virtual_y += 28
                    names = []
                    for idx in _:
                        try:
                            sd = self.db.get(f"/spells/{idx}.json")
                            names.append(sd.get("name", idx))
                        except Exception:
                            names.append(idx)
                    s = ", ".join(names)
                    for _ in self._wrap_text_lines(self.small_font, s, content_max_w - 20):
                        virtual_y += 22
        virtual_y += padding
        content_height = virtual_y - panel_y
        self._confirmation_content_height = content_height

        mx = max(0, content_height - panel_h)
        self.confirmation_scroll_offset = max(0, min(mx, self.confirmation_scroll_offset))

        # Draw panel background and border
        pygame.draw.rect(self.screen, DARK_GRAY, pr, border_radius=8)
        pygame.draw.rect(self.screen, GOLD, pr, width=2, border_radius=8)

        clip_save = self.screen.get_clip()
        self.screen.set_clip(pr)

        cy = panel_y + padding - self.confirmation_scroll_offset

        def draw_row(label_key: str, value: str, font_used=None):
            nonlocal cy
            f = font_used or self.font
            lbl = loc.get(label_key, label_key) + ":"
            val = self._truncate_text(f, value or loc.get("none", "None"), value_max_w)
            if cy + row_h > panel_y and cy < panel_y + panel_h:
                self.screen.blit(f.render(lbl, True, WHITE), (cx, cy))
                self.screen.blit(f.render(val, True, GOLD), (cx + label_w, cy))
            cy += row_h

        def draw_header(txt: str):
            nonlocal cy
            if cy > panel_y + padding:
                cy += 12
            if cy + header_h > panel_y and cy < panel_y + panel_h:
                self.screen.blit(self.header_font.render(txt, True, GOLD), (cx, cy))
            cy += header_h

        draw_header(loc.get("char_info", "Character Info"))
        draw_row("char_name", self.build.name or "")
        if self.build.alignment:
            try:
                ad = self.db.get(f"/alignments/{self.build.alignment}.json")
                draw_row("alignment", ad.get("name", self.build.alignment) if ad else self.build.alignment)
            except Exception:
                draw_row("alignment", self.build.alignment)
        if self.build.race_data:
            draw_row("step_race", self.build.race_data.get("name", "") or self.build.race or "")
        if self.build.subrace_data:
            draw_row("step_subrace", self.build.subrace_data.get("name", "") or self.build.subrace or "")
        if self.build.class_data:
            draw_row("step_class", self.build.class_data.get("name", "") or self.build.class_type or "")
        if self.build.background_data:
            draw_row("step_background", self.build.background_data.get("name", "") or self.build.background or "")

        draw_header(loc.get("step_abilities", "Abilities"))
        mod = lambda x: (x - 10) // 2
        for ability, label in self.ability_labels.items():
            score = self.build.abilities.get(ability, 10)
            if self.build.race_data:
                for b in self.build.race_data.get("ability_bonuses", []) or []:
                    ab = b.get("ability_score", {}) or {}
                    if ab.get("index") == ability:
                        score += b.get("bonus", 0)
            if self.build.subrace_data:
                for b in self.build.subrace_data.get("ability_bonuses", []) or []:
                    ab = b.get("ability_score", {}) or {}
                    if ab.get("index") == ability:
                        score += b.get("bonus", 0)
            mod_str = f"+{mod(score)}" if mod(score) >= 0 else str(mod(score))
            val = f"{score} ({mod_str})"
            if cy + row_h > panel_y and cy < panel_y + panel_h:
                self.screen.blit(self.font.render(f"{label}:", True, WHITE), (cx, cy))
                self.screen.blit(self.font.render(val, True, GOLD), (cx + label_w, cy))
            cy += row_h

        draw_header(loc.get("proficiencies", "Proficiencies"))
        if prof_names:
            prof_text = ", ".join(prof_names)
            for line in self._wrap_text_lines(self.small_font, prof_text, content_max_w - 20):
                if cy + 22 > panel_y and cy < panel_y + panel_h:
                    self.screen.blit(self.small_font.render("  " + line, True, LIGHT_GRAY), (cx, cy))
                cy += 22
        else:
            if cy + 22 > panel_y and cy < panel_y + panel_h:
                self.screen.blit(self.small_font.render("  " + loc.get("none", "None"), True, LIGHT_GRAY), (cx, cy))
            cy += 22

        if self.build.class_data and self.build.class_data.get("spellcasting"):
            draw_header(loc.get("spells", "Spells"))
            for title_key, lst in [
                ("step_cantrips", self.build.cantrips),
                ("step_spells", self.build.spells),
                ("step_prepared", self.build.prepared_spells),
            ]:
                if not lst:
                    continue
                if cy + 28 > panel_y and cy < panel_y + panel_h:
                    self.screen.blit(self.small_font.render(loc.get(title_key, title_key) + ":", True, GOLD), (cx, cy))
                cy += 28
                names = []
                for idx in lst:
                    try:
                        sd = self.db.get(f"/spells/{idx}.json")
                        names.append(sd.get("name", idx))
                    except Exception:
                        names.append(idx)
                s = ", ".join(names)
                for line in self._wrap_text_lines(self.small_font, s, content_max_w - 20):
                    if cy + 22 > panel_y and cy < panel_y + panel_h:
                        self.screen.blit(self.small_font.render("  " + line, True, LIGHT_GRAY), (cx, cy))
                    cy += 22

        self.screen.set_clip(clip_save)

        if mx > 0:
            track, thumb = self._confirmation_scrollbar_rects()
            if track and thumb:
                pygame.draw.rect(self.screen, DARK_GRAY, track, border_radius=4)
                pygame.draw.rect(self.screen, GOLD, thumb, border_radius=4)
