"""
Settings screen - game configuration
"""

import pygame
from typing import Union
from .base_screen import BaseScreen
from ..colors import *
from ..components import Button
from ..controls import Slider, Dropdown
from core.settings_manager import SettingsManager, RESOLUTION_NAMES
from localization import loc


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


class SettingsScreen(BaseScreen):
    """Settings configuration screen"""
    
    def __init__(self, screen: pygame.Surface, settings_manager: SettingsManager, 
                 on_apply_callback=None):
        super().__init__(screen)
        self.settings_manager = settings_manager
        self.on_apply_callback = on_apply_callback
        s = self._scale
        w, h = self._w, self._h
        
        # Fonts (scaled)
        self.title_font = pygame.font.Font(None, _sc(72, s))
        self.section_font = pygame.font.Font(None, _sc(42, s))
        self.button_font = pygame.font.Font(None, _sc(36, s))
        
        # Layout (adaptive)
        self.left_column = _sc(150, s)
        self.right_column = w // 2 + _sc(50, s)
        
        self._create_controls()
        self._create_buttons()
        
    def _create_controls(self):
        """Create all settings controls"""
        settings = self.settings_manager.settings
        s = self._scale
        w, h = self._w, self._h
        
        y_display = int(0.25 * h)
        dd_w, dd_h = _sc(280, s), _sc(40, s)
        
        self.resolution_dropdown = Dropdown(
            self.left_column, y_display, dd_w, dd_h,
            RESOLUTION_NAMES,
            self.settings_manager.get_resolution_index(),
            loc["settings_resolution"]
        )
        
        self._fullscreen = settings.fullscreen
        fsw, fsh = _sc(200, s), _sc(40, s)
        self.fullscreen_btn = Button(
            self.left_column, y_display + _sc(55, s), fsw, fsh,
            loc["settings_windowed"] if self._fullscreen else loc["settings_fullscreen"],
            self.section_font
        )
        
        y_audio = int(0.25 * h)
        sw, sh = _sc(250, s), _sc(30, s)
        self.master_slider = Slider(
            self.right_column, y_audio, sw, sh,
            0.0, 1.0, settings.master_volume,
            loc["settings_master_volume"]
        )
        self.music_slider = Slider(
            self.right_column, y_audio + _sc(70, s), sw, sh,
            0.0, 1.0, settings.music_volume,
            loc["settings_music_volume"]
        )
        self.sfx_slider = Slider(
            self.right_column, y_audio + _sc(140, s), sw, sh,
            0.0, 1.0, settings.sfx_volume,
            loc["settings_sfx_volume"]
        )
        
        y_lang = int(0.58 * h)
        self.language_names = [name for code, name in loc.get_language_list()]
        self.language_codes = [code for code, name in loc.get_language_list()]
        current_lang_index = 0
        if settings.language in self.language_codes:
            current_lang_index = self.language_codes.index(settings.language)
        self.language_dropdown = Dropdown(
            self.left_column, y_lang, dd_w, dd_h,
            self.language_names,
            current_lang_index,
            loc["settings_language"]
        )
        
        self.sliders = [self.master_slider, self.music_slider, self.sfx_slider]
        self.dropdowns = [self.resolution_dropdown, self.language_dropdown]
        
    def _create_buttons(self):
        """Create action buttons"""
        s = self._scale
        bw, bh = _sc(300, s), _sc(60, s)
        btn_spacing = _sc(20, s)
        btn_y = self._h - _sc(100, s)
        cx = self._w // 2
        
        self.apply_btn = Button(
            cx - bw - btn_spacing, btn_y, bw, bh,
            loc["apply"], self.button_font
        )
        self.back_btn = Button(
            cx + btn_spacing, btn_y, bw, bh,
            loc["back"], self.button_font
        )
        self.buttons = [self.fullscreen_btn, self.apply_btn, self.back_btn]
        
    def _apply_settings(self):
        """Apply current control values to settings"""
        settings = self.settings_manager.settings
        
        # Display
        self.settings_manager.set_resolution_by_index(self.resolution_dropdown.selected_index)
        settings.fullscreen = self._fullscreen
        
        # Audio
        settings.master_volume = self.master_slider.value
        settings.music_volume = self.music_slider.value
        settings.sfx_volume = self.sfx_slider.value
        
        # Language
        lang_index = self.language_dropdown.selected_index
        if 0 <= lang_index < len(self.language_codes):
            new_lang = self.language_codes[lang_index]
            if new_lang != settings.language:
                settings.language = new_lang
                loc.set_language(new_lang)
        
        # Save to file
        self.settings_manager.save()
        print(loc["settings_title"] + " - OK!")
        
        # Callback to apply display changes
        if self.on_apply_callback:
            self.on_apply_callback()
            
    def handle_event(self, event: pygame.event.Event) -> Union[str, None]:
        """Handle events"""
        # Dropdowns first (they overlay other elements)
        for dropdown in self.dropdowns:
            if dropdown.expanded:
                dropdown.handle_event(event)
                if event.type == pygame.MOUSEBUTTONDOWN:
                    return None
                    
        # Then dropdowns click to open
        for dropdown in self.dropdowns:
            dropdown.handle_event(event)
            
        # Sliders
        for slider in self.sliders:
            slider.handle_event(event)
            
        # Buttons
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mouse_pos = pygame.mouse.get_pos()
            
            if self.fullscreen_btn.is_clicked(mouse_pos):
                self._fullscreen = not self._fullscreen
                self.fullscreen_btn.text = loc["settings_windowed"] if self._fullscreen else loc["settings_fullscreen"]
            elif self.apply_btn.is_clicked(mouse_pos):
                self._apply_settings()
            elif self.back_btn.is_clicked(mouse_pos):
                return "title"
                
        # ESC to go back
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            return "title"
            
        return None
    
    def update(self):
        """Update screen state"""
        mouse_pos = pygame.mouse.get_pos()
        self.fullscreen_btn.text = loc["settings_windowed"] if self._fullscreen else loc["settings_fullscreen"]
        for button in self.buttons:
            button.update(mouse_pos)
            
    def draw(self):
        """Draw the settings screen"""
        self.screen.fill(BLACK)
        s = self._scale
        w, h = self._w, self._h
        
        title_text = self.title_font.render(loc["settings_title"], True, GOLD)
        title_rect = title_text.get_rect(center=(w // 2, _sc(70, s)))
        self.screen.blit(title_text, title_rect)
        
        y_sec = _sc(130, s)
        display_text = self.section_font.render(loc["settings_display"], True, WHITE)
        self.screen.blit(display_text, (self.left_column, y_sec))
        audio_text = self.section_font.render(loc["settings_audio"], True, WHITE)
        self.screen.blit(audio_text, (self.right_column, y_sec))
        
        y_lang_label = int(0.51 * h)
        game_text = self.section_font.render(loc["settings_language"], True, WHITE)
        self.screen.blit(game_text, (self.left_column, y_lang_label))
        
        sep_x = w // 2 - _sc(20, s)
        sep_top, sep_bot = y_sec, _sc(340, s)
        pygame.draw.line(self.screen, DARK_GRAY, (sep_x, sep_top), (sep_x, sep_bot), 2)
        horiz_y = int(0.49 * h)
        pygame.draw.line(self.screen, DARK_GRAY, (_sc(100, s), horiz_y), (w - _sc(100, s), horiz_y), 2)
        
        for slider in self.sliders:
            slider.draw(self.screen)
        for button in self.buttons:
            button.draw(self.screen)
        for dropdown in self.dropdowns:
            dropdown.draw(self.screen)
