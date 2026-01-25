"""
Title screen - main menu of the game
"""

import pygame
from typing import Union
from .base_screen import BaseScreen
from ..colors import *
from ..components import Button, InputModal, SaveSlotsModal
from core.api_manager import APIManager
from core import data as game_data
from localization import loc


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


class TitleScreen(BaseScreen):
    """Title screen with main menu"""
    
    def __init__(self, screen: pygame.Surface, api_manager: APIManager):
        super().__init__(screen)
        self.api_manager = api_manager
        s = self._scale
        
        # Fonts (scaled)
        self.title_font = pygame.font.Font(None, _sc(96, s))
        self.button_font = pygame.font.Font(None, _sc(48, s))
        self.subtitle_font = pygame.font.Font(None, _sc(36, s))
        
        bw, bh, sp = _sc(300, s), _sc(60, s), _sc(80, s)
        bx = self._w // 2 - bw // 2
        start_y = int(0.36 * self._h)
        
        self.continue_btn = Button(bx, start_y, bw, bh, loc["continue"], self.button_font)
        self.new_game_btn = Button(bx, start_y + sp, bw, bh, loc["new_game"], self.button_font)
        self.save_btn = Button(bx, start_y + sp * 2, bw, bh, loc["save_game"], self.button_font)
        self.load_btn = Button(bx, start_y + sp * 3, bw, bh, loc["load_game"], self.button_font)
        self.settings_btn = Button(bx, start_y + sp * 4, bw, bh, loc["settings"], self.button_font)
        self.llm_btn = Button(bx, start_y + sp * 5, bw, bh, "LLM", self.button_font)
        self.exit_btn = Button(bx, start_y + sp * 6, bw, bh, loc["exit"], self.button_font)
        
        self.api_key_modal = InputModal(
            screen, 
            loc["api_key_title"],
            loc["api_key_placeholder"]
        )
        self.save_slots_modal = SaveSlotsModal(screen)
        
        self._update_llm_button()
        
    def _update_llm_button(self):
        """Update LLM button state based on API status"""
        btn = self.llm_btn
        if self.api_manager.is_valid:
            btn.text = loc["llm_active"]
            btn.custom_color = DARK_GREEN
        else:
            btn.text = loc["llm_enable"]
            btn.custom_color = DARK_RED

    def _has_player(self) -> bool:
        gs = game_data.game_state
        return gs is not None and gs.player is not None

    def _layout_buttons(self):
        """Gap between buttons = 1/4 of button height (sp = bh + gap). Shrink bh only when needed."""
        s = self._scale
        bw = _sc(300, s)
        bx = self._w // 2 - bw // 2
        start_y = int(0.36 * self._h)
        bottom = self._h - _sc(90, s)
        available = max(1, bottom - start_y)
        n_slots = 7
        bh = _sc(60, s)
        # 7*bh + 6*(bh + bh/4) = 14.5*bh <= available => bh <= available/14.5
        bh_max_fit = (2 * available) // 29  # ~ available/14.5
        if bh > bh_max_fit:
            bh = max(24, bh_max_fit)
        gap = max(1, bh // 4)
        sp = bh + gap
        for b in (self.continue_btn, self.new_game_btn, self.save_btn, self.load_btn,
                  self.settings_btn, self.llm_btn, self.exit_btn):
            b.rect.w, b.rect.h = bw, bh
            b.rect.x = bx
        has = self._has_player()
        if has:
            self.continue_btn.rect.y = start_y
            self.new_game_btn.rect.y = start_y + sp
            self.save_btn.rect.y = start_y + sp * 2
            self.load_btn.rect.y = start_y + sp * 3
            self.settings_btn.rect.y = start_y + sp * 4
            self.llm_btn.rect.y = start_y + sp * 5
            self.exit_btn.rect.y = start_y + sp * 6
        else:
            self.new_game_btn.rect.y = start_y
            self.load_btn.rect.y = start_y + sp
            self.settings_btn.rect.y = start_y + sp * 2
            self.llm_btn.rect.y = start_y + sp * 3
            self.exit_btn.rect.y = start_y + sp * 4
            self.continue_btn.rect.y = -200
            self.save_btn.rect.y = -200

    def handle_event(self, event: pygame.event.Event) -> Union[str, None]:
        if self.api_key_modal.active:
            result = self.api_key_modal.handle_event(event)
            if result == "confirm" and self.api_key_modal.input_text:
                api_key = self.api_key_modal.input_text
                print(loc["api_checking"])
                if self.api_manager.validate_key(api_key):
                    self.api_manager.save_key_to_env(api_key)
                    print(loc["api_saved"])
                    self.api_manager.print_status()
                else:
                    print(f"{loc['api_error']}: {self.api_manager.error_message}")
                self._update_llm_button()
            return None

        if self.save_slots_modal.active:
            result = self.save_slots_modal.handle_event(event)
            if result is not None:
                kind, slot_i = result
                gs = game_data.game_state
                if kind == "save" and gs is not None and gs.player is not None:
                    try:
                        gs.save(slot_i)
                        print(loc.get("save", "Save") + f" → slot {slot_i}: OK")
                    except Exception as e:
                        print(f"{loc.get('api_save_error', 'Save error')}: {e}")
                elif kind == "load" and gs is not None:
                    try:
                        loaded = gs.load(slot_i)
                        game_data.game_state = loaded
                        print(loc.get("load", "Load") + f" → slot {slot_i}: OK")
                        return "load_game"
                    except Exception as e:
                        print(f"{loc.get('api_save_error', 'Load error')}: {e}")
            return None

        self._layout_buttons()
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            mouse_pos = pygame.mouse.get_pos()
            if self._has_player() and self.continue_btn.is_clicked(mouse_pos):
                return "continue"
            if self.new_game_btn.is_clicked(mouse_pos):
                return "new_game"
            if self._has_player() and self.save_btn.is_clicked(mouse_pos):
                self.save_slots_modal.show("save")
                return None
            if self.load_btn.is_clicked(mouse_pos):
                self.save_slots_modal.show("load")
                return None
            if self.settings_btn.is_clicked(mouse_pos):
                return "settings"
            if self.llm_btn.is_clicked(mouse_pos):
                self.api_key_modal.show()
                return None
            if self.exit_btn.is_clicked(mouse_pos):
                return "exit"
        return None
    
    def update(self):
        mouse_pos = pygame.mouse.get_pos()
        if not self.api_key_modal.active and not self.save_slots_modal.active:
            self._layout_buttons()
            for b in (self.continue_btn, self.new_game_btn, self.save_btn, self.load_btn, self.settings_btn, self.llm_btn, self.exit_btn):
                b.update(mouse_pos)
        self.api_key_modal.update()
        self.save_slots_modal.update()

    def draw(self):
        self.screen.fill(BLACK)
        title_text = self.title_font.render(loc["game_title"], True, GOLD)
        title_rect = title_text.get_rect(center=(self._w // 2, int(0.21 * self._h)))
        self.screen.blit(title_text, title_rect)
        subtitle_text = self.subtitle_font.render(loc["game_subtitle"], True, LIGHT_GRAY)
        subtitle_rect = subtitle_text.get_rect(center=(self._w // 2, int(0.31 * self._h)))
        self.screen.blit(subtitle_text, subtitle_rect)

        self._layout_buttons()
        for b in (self.continue_btn, self.new_game_btn, self.save_btn, self.load_btn, self.settings_btn, self.llm_btn, self.exit_btn):
            if b.rect.y >= 0:
                b.draw(self.screen)

        status_text = self.api_manager.get_status_text()
        status_color = DARK_GREEN if self.api_manager.is_valid else DARK_RED
        status_surface = self.subtitle_font.render(status_text, True, status_color)
        status_rect = status_surface.get_rect(bottomright=(self._w - _sc(20, self._scale), self._h - _sc(20, self._scale)))
        self.screen.blit(status_surface, status_rect)
        self.api_key_modal.draw()
        self.save_slots_modal.draw()
