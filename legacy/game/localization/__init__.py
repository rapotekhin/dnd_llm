"""
Localization module for DnD LLM Game
"""

import os
import xml.etree.ElementTree as ET
from typing import Dict, List, Optional
from pathlib import Path


class Localization:
    """
    Singleton class for managing game localization.
    
    Usage:
        from localization import loc
        
        # Get localized string
        text = loc.get("new_game")  # Returns "Новая игра" or "New Game"
        
        # Change language
        loc.set_language("en")
    """
    
    _instance: Optional["Localization"] = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        if self._initialized:
            return
            
        self._initialized = True
        self._strings: Dict[str, str] = {}
        self._current_lang: str = "ru"
        self._available_languages: Dict[str, str] = {}  # code -> name
        self._localization_dir = Path(__file__).parent
        
        # Discover available languages
        self._discover_languages()
        
        # Load default language
        self.set_language(self._current_lang)
        
    def _discover_languages(self):
        """Find all available localization files"""
        self._available_languages = {}
        
        for file in self._localization_dir.glob("*.xml"):
            try:
                tree = ET.parse(file)
                root = tree.getroot()
                lang_code = root.get("lang", file.stem)
                lang_name = root.get("name", lang_code)
                self._available_languages[lang_code] = lang_name
            except Exception as e:
                print(f"Error parsing localization file {file}: {e}")
                
    def get_available_languages(self) -> Dict[str, str]:
        """Get dict of available languages {code: name}"""
        return self._available_languages.copy()
        
    def get_language_list(self) -> List[tuple]:
        """Get list of (code, name) tuples for UI"""
        return [(code, name) for code, name in self._available_languages.items()]
        
    def get_current_language(self) -> str:
        """Get current language code"""
        return self._current_lang
        
    def get_current_language_name(self) -> str:
        """Get current language display name"""
        return self._available_languages.get(self._current_lang, self._current_lang)
        
    def set_language(self, lang_code: str) -> bool:
        """
        Set current language.
        
        Args:
            lang_code: Language code (e.g., "ru", "en")
            
        Returns:
            True if language was loaded successfully
        """
        file_path = self._localization_dir / f"{lang_code}.xml"
        
        if not file_path.exists():
            print(f"Localization file not found: {file_path}")
            return False
            
        try:
            tree = ET.parse(file_path)
            root = tree.getroot()
            
            self._strings = {}
            for string_elem in root.findall("string"):
                string_id = string_elem.get("id")
                if string_id:
                    self._strings[string_id] = string_elem.text or ""
                    
            self._current_lang = lang_code
            print(f"Loaded localization: {lang_code} ({len(self._strings)} strings)")
            return True
            
        except Exception as e:
            print(f"Error loading localization {lang_code}: {e}")
            return False
            
    def get(self, string_id: str, default: Optional[str] = None) -> str:
        """
        Get localized string by ID.
        
        Args:
            string_id: String identifier
            default: Default value if string not found (uses string_id if None)
            
        Returns:
            Localized string or default/string_id if not found
        """
        if string_id in self._strings:
            return self._strings[string_id]
            
        if default is not None:
            return default
            
        # Return the ID itself as fallback (useful for debugging)
        return f"[{string_id}]"
        
    def __getitem__(self, string_id: str) -> str:
        """Allow dict-like access: loc["new_game"]"""
        return self.get(string_id)
        
    def format(self, string_id: str, *args, **kwargs) -> str:
        """
        Get localized string and format it with arguments.
        
        Args:
            string_id: String identifier
            *args, **kwargs: Format arguments
            
        Returns:
            Formatted localized string
        """
        template = self.get(string_id)
        try:
            return template.format(*args, **kwargs)
        except (KeyError, IndexError):
            return template


# Global instance for easy access
loc = Localization()


# Convenience function
def get_text(string_id: str, default: Optional[str] = None) -> str:
    """Get localized text (shortcut for loc.get())"""
    return loc.get(string_id, default)
