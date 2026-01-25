"""
Settings Manager - handles saving/loading game settings
"""

import json
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import Tuple


@dataclass
class GameSettings:
    """Game settings data class"""
    # Display
    resolution: Tuple[int, int] = (1280, 720)
    fullscreen: bool = False
    
    # Audio
    master_volume: float = 0.8
    music_volume: float = 0.7
    sfx_volume: float = 0.8
    
    # Game
    text_speed: float = 1.0  # 0.5 = slow, 1.0 = normal, 2.0 = fast
    auto_save: bool = True
    language: str = "ru"


# Available resolutions
RESOLUTIONS = [
    (1280, 720),
    (1366, 768),
    (1600, 900),
    (1920, 1080),
    (2560, 1440),
]

RESOLUTION_NAMES = [
    "1280x720 (HD)",
    "1366x768",
    "1600x900",
    "1920x1080 (Full HD)",
    "2560x1440 (2K)",
]


class SettingsManager:
    """Manages game settings persistence"""
    
    SETTINGS_FILE = Path(__file__).parent.parent.parent / "settings.json"
    
    def __init__(self):
        self.settings = GameSettings()
        self.load()
        
    def load(self) -> bool:
        """Load settings from file"""
        try:
            if self.SETTINGS_FILE.exists():
                with open(self.SETTINGS_FILE, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    # Convert resolution list to tuple
                    if 'resolution' in data:
                        data['resolution'] = tuple(data['resolution'])
                    # Update settings with loaded values
                    for key, value in data.items():
                        if hasattr(self.settings, key):
                            setattr(self.settings, key, value)
                return True
        except Exception as e:
            print(f"Error loading settings: {e}")
        return False
        
    def save(self) -> bool:
        """Save settings to file"""
        try:
            data = asdict(self.settings)
            # Convert tuple to list for JSON
            data['resolution'] = list(data['resolution'])
            with open(self.SETTINGS_FILE, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            return True
        except Exception as e:
            print(f"Error saving settings: {e}")
            return False
            
    def get_resolution_index(self) -> int:
        """Get index of current resolution in RESOLUTIONS list"""
        try:
            return RESOLUTIONS.index(self.settings.resolution)
        except ValueError:
            return 0
            
    def set_resolution_by_index(self, index: int):
        """Set resolution by index"""
        if 0 <= index < len(RESOLUTIONS):
            self.settings.resolution = RESOLUTIONS[index]
