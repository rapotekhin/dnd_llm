"""
Main Game class - handles the game loop and screen management
"""

import pygame
import sys
from typing import TYPE_CHECKING, Union
from .settings import FPS, GAME_TITLE

if TYPE_CHECKING:
    from core.entities.character import Character
from .api_manager import APIManager
from .settings_manager import SettingsManager
from . import data as game_data
from ui.screens import TitleScreen, SettingsScreen, CharacterCreationScreen, MainScreen, InventoryScreen, CharacterScreen, AbilitiesScreen, JournalScreen
from localization import loc


class Game:
    """Main game class"""
    
    def __init__(self):
        pygame.init()
        pygame.display.set_caption(GAME_TITLE)
        
        # Initialize settings manager first
        self.settings_manager = SettingsManager()
        settings = self.settings_manager.settings
        
        # Initialize localization with saved language
        loc.set_language(settings.language)
        
        # Create display with settings
        self._create_display(settings.resolution, settings.fullscreen)
        pygame.scrap.init()  # For clipboard (must be after display init)
        
        self.clock = pygame.time.Clock()
        self.running = True
        
        # Initialize API manager
        print(f"Инициализация {GAME_TITLE}...")
        self.api_manager = APIManager()
        self.api_manager.print_status()
        
        # Global game state (session + world). Created at startup; use game_data.game_state elsewhere.
        from .data import MainGameState
        game_data.game_state = MainGameState()

        # Screen management
        self.screens = {}
        self.current_screen_name = "title"
        self._init_screens()
        
    def _create_display(self, resolution: tuple, fullscreen: bool):
        """Create or recreate the display.
        In windowed mode, uses RESIZABLE so the maximize button works."""
        if fullscreen:
            flags = pygame.FULLSCREEN
        else:
            flags = pygame.RESIZABLE
        self.screen = pygame.display.set_mode(resolution, flags)
        self.screen_width, self.screen_height = self.screen.get_size()
        
    def _init_screens(self):
        """Initialize all game screens"""
        self.screens["title"] = TitleScreen(self.screen, self.api_manager)
        self.screens["settings"] = SettingsScreen(
            self.screen, 
            self.settings_manager,
            on_apply_callback=self._on_settings_applied
        )
        self.screens["character_creation"] = CharacterCreationScreen(self.screen)
        self.screens["main"] = MainScreen(self.screen)
        self.screens["inventory"] = InventoryScreen(self.screen)
        self.screens["character"] = CharacterScreen(self.screen)
        self.screens["abilities"] = AbilitiesScreen(self.screen)
        self.screens["journal"] = JournalScreen(self.screen)
        
    def _on_settings_applied(self):
        """Called when settings are applied - recreate display/screens if needed"""
        settings = self.settings_manager.settings
        current_size = self.screen.get_size()
        current_fullscreen = bool(self.screen.get_flags() & pygame.FULLSCREEN)
        
        needs_reinit = False
        
        if current_size != settings.resolution or current_fullscreen != settings.fullscreen:
            print(f"Applying display settings: {settings.resolution}, fullscreen={settings.fullscreen}")
            if current_fullscreen and not settings.fullscreen:
                # Workaround: fullscreen->windowed often fails with a single set_mode on some systems
                pygame.display.quit()
                pygame.display.init()
                pygame.display.set_caption(GAME_TITLE)
            self._create_display(settings.resolution, settings.fullscreen)
            needs_reinit = True
            
        if needs_reinit or True:  # Always reinit for now to catch language changes
            self._init_screens()
            self.current_screen_name = "settings"
        
    @property
    def current_screen(self):
        """Get current active screen"""
        return self.screens.get(self.current_screen_name)
        
    def switch_screen(self, screen_name: str):
        """Switch to a different screen"""
        if screen_name in self.screens:
            self.current_screen_name = screen_name
        else:
            print(f"Screen not found: {screen_name}")
        
    def run(self):
        """Main game loop"""
        while self.running:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False
                    continue
                if event.type == pygame.VIDEORESIZE:
                    # Window resized or maximized; keep windowed mode
                    if not (self.screen.get_flags() & pygame.FULLSCREEN):
                        self._create_display((event.w, event.h), False)
                        self._init_screens()
                    continue

                if self.current_screen:
                    result = self.current_screen.handle_event(event)
                    self._handle_screen_result(result)
                    
            # Update
            if self.current_screen:
                self.current_screen.update()
            
            # Draw
            if self.current_screen:
                self.current_screen.draw()
            pygame.display.flip()
            
            # FPS limit
            self.clock.tick(FPS)
            
        pygame.quit()
        sys.exit()
        
    def _handle_screen_result(self, result: Union[str, None, "Character"]):
        """Handle commands returned from screens"""
        if result is None:
            return
        
        from core.entities.character import Character
        if isinstance(result, Character):
            gs = game_data.game_state
            if gs is not None:
                gs.player = result
            print(f"Character '{result.name}' created and ready to play!")
            self.switch_screen("main")
            return
            
        if result == "exit":
            self.running = False
        elif result == "new_game":
            self.switch_screen("character_creation")
        elif result == "continue":
            self.switch_screen("main")
        elif result == "save_game":
            pass  # Handled by TitleScreen save modal
        elif result == "load_game":
            self.switch_screen("main")  # Load done in TitleScreen modal
        elif result in self.screens:
            self.switch_screen(result)

