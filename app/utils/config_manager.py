import os
import json
from typing import Dict, Any, List, Optional

class ConfigManager:
    """Manager for application configuration and system prompts"""
    
    def __init__(self, config_path: str = "app/config/config.json", prompts_dir: str = "app/config/prompts"):
        """
        Initialize the configuration manager
        
        Args:
            config_path: Path to the configuration file
            prompts_dir: Directory containing prompt files
        """
        self.config_path = config_path
        self.prompts_dir = prompts_dir
        self.config = self._load_config()
    
    def _load_config(self) -> Dict[str, Any]:
        """Load configuration from file"""
        try:
            if os.path.exists(self.config_path):
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            else:
                # Create default config if it doesn't exist
                default_config = {
                    "system_prompt": {
                        "active": "default",
                        "available": ["default"]
                    },
                    "app_settings": {
                        "default_provider": "openrouter",
                        "default_model": "google/gemini-2.5-flash-lite-preview-09-2025",
                        "default_temperature": 0.7,
                        "max_tokens": 3000,
                        "show_dice_results": True,
                        "show_code_execution": True
                    }
                }
                with open(self.config_path, 'w', encoding='utf-8') as f:
                    json.dump(default_config, f, indent=4)
                return default_config
        except Exception as e:
            print(f"Error loading configuration: {e}")
            # Return default configuration on error
            return {
                "system_prompt": {
                    "active": "default",
                    "available": ["default"]
                },
                "app_settings": {
                    "default_provider": "openrouter",
                    "default_model": "google/gemini-2.5-flash-lite-preview-09-2025",
                    "default_temperature": 0.7,
                    "max_tokens": 3000,
                    "show_dice_results": True,
                    "show_code_execution": True
                }
            }
    
    def save_config(self) -> bool:
        """Save configuration to file"""
        try:
            # Ensure directory exists
            os.makedirs(os.path.dirname(self.config_path), exist_ok=True)
            
            with open(self.config_path, 'w', encoding='utf-8') as f:
                json.dump(self.config, f, indent=4)
            return True
        except Exception as e:
            print(f"Error saving configuration: {e}")
            return False
    
    def get_active_prompt_name(self) -> str:
        """Get the name of the active system prompt"""
        return self.config.get("system_prompt", {}).get("active", "default")
    
    def set_active_prompt(self, prompt_name: str) -> bool:
        """
        Set the active system prompt
        
        Args:
            prompt_name: Name of the prompt to set as active
            
        Returns:
            True if successful, False otherwise
        """
        if prompt_name in self.get_available_prompts():
            self.config["system_prompt"]["active"] = prompt_name
            return self.save_config()
        return False
    
    def get_available_prompts(self) -> List[str]:
        """Get list of available system prompts"""
        # Get from config
        available_from_config = self.config.get("system_prompt", {}).get("available", [])
        
        # Get from files
        try:
            available_from_files = []
            if os.path.exists(self.prompts_dir):
                for filename in os.listdir(self.prompts_dir):
                    if filename.endswith(".txt"):
                        prompt_name = filename[:-4]  # Remove .txt extension
                        available_from_files.append(prompt_name)
            
            # Combine and deduplicate
            all_prompts = list(set(available_from_config + available_from_files))
            
            # Update config if needed
            if set(all_prompts) != set(available_from_config):
                self.config["system_prompt"]["available"] = all_prompts
                self.save_config()
            
            return all_prompts
        except Exception as e:
            print(f"Error getting available prompts: {e}")
            return available_from_config
    
    def get_system_prompt(self, prompt_name: Optional[str] = None) -> str:
        """
        Get the content of a system prompt
        
        Args:
            prompt_name: Name of the prompt to get, or None for active prompt
            
        Returns:
            The prompt content as a string
        """
        if prompt_name is None:
            prompt_name = self.get_active_prompt_name()
        
        prompt_path = os.path.join(self.prompts_dir, f"{prompt_name}.txt")
        
        try:
            if os.path.exists(prompt_path):
                with open(prompt_path, 'r', encoding='utf-8') as f:
                    return f.read()
            else:
                # Return default prompt if file doesn't exist
                return "You are an AI Dungeon Master for a Dungeons & Dragons game."
        except Exception as e:
            print(f"Error loading system prompt: {e}")
            return "You are an AI Dungeon Master for a Dungeons & Dragons game."
    
    def save_system_prompt(self, prompt_name: str, content: str) -> bool:
        """
        Save a system prompt to file
        
        Args:
            prompt_name: Name of the prompt to save
            content: Prompt content
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Ensure directory exists
            os.makedirs(self.prompts_dir, exist_ok=True)
            
            prompt_path = os.path.join(self.prompts_dir, f"{prompt_name}.txt")
            
            with open(prompt_path, 'w', encoding='utf-8') as f:
                f.write(content)
            
            # Update available prompts
            available = self.get_available_prompts()
            if prompt_name not in available:
                available.append(prompt_name)
                self.config["system_prompt"]["available"] = available
                self.save_config()
            
            return True
        except Exception as e:
            print(f"Error saving system prompt: {e}")
            return False
    
    def get_app_setting(self, setting_name: str, default_value: Any = None) -> Any:
        """
        Get an application setting
        
        Args:
            setting_name: Name of the setting to get
            default_value: Default value if setting doesn't exist
            
        Returns:
            The setting value
        """
        return self.config.get("app_settings", {}).get(setting_name, default_value)
    
    def set_app_setting(self, setting_name: str, value: Any) -> bool:
        """
        Set an application setting
        
        Args:
            setting_name: Name of the setting to set
            value: Value to set
            
        Returns:
            True if successful, False otherwise
        """
        if "app_settings" not in self.config:
            self.config["app_settings"] = {}
        
        self.config["app_settings"][setting_name] = value
        return self.save_config() 