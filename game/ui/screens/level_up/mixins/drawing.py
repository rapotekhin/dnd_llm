"""Level-up: rendering."""
import pygame
from typing import List

from ..colors import *
from localization import loc

from ..character_creation.widgets import SelectionList, _sc


class LevelUpDrawingMixin:
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
