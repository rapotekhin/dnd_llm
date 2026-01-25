"""
API Manager for OpenRouter
"""

import os
import requests
from pathlib import Path
from typing import Optional
from dotenv import load_dotenv, set_key
from localization import loc


class APIManager:
    """Manages API keys and balance checking"""
    
    OPENROUTER_CREDITS_URL = "https://openrouter.ai/api/v1/credits"
    # .env is in project root (two levels up from core/)
    ENV_FILE = Path(__file__).parent.parent.parent / ".env"
    
    def __init__(self):
        self.api_key: Optional[str] = None
        self.balance: float = 0.0
        self.usage: float = 0.0
        self.is_valid: bool = False
        self.error_message: str = ""
        
        load_dotenv(self.ENV_FILE)
        self._load_key_from_env()
        
    def _load_key_from_env(self):
        """Load key from .env file"""
        self.api_key = os.getenv("OPENROUTER_API_KEY")
        if self.api_key:
            self.validate_key(self.api_key)
            
    def validate_key(self, api_key: str) -> bool:
        """Validate key and get balance"""
        self.api_key = api_key
        self.is_valid = False
        self.error_message = ""
        
        if not api_key or not api_key.strip():
            self.error_message = loc["api_key_empty"]
            return False
            
        try:
            headers = {"Authorization": f"Bearer {api_key.strip()}"}
            response = requests.get(
                self.OPENROUTER_CREDITS_URL, 
                headers=headers,
                timeout=10
            )
            
            if response.status_code == 401:
                self.error_message = loc["api_key_invalid"]
                return False
            elif response.status_code == 403:
                self.error_message = loc["api_access_denied"]
                return False
            elif response.status_code != 200:
                self.error_message = f"{loc['api_error_code']}: {response.status_code}"
                return False
                
            data = response.json().get("data", {})
            self.balance = data.get("total_credits", 0.0)
            self.usage = data.get("total_usage", 0.0)
            
            remaining = self.balance - self.usage
            
            if remaining <= 0:
                self.error_message = loc["api_balance_empty"]
                self.is_valid = False
            else:
                self.is_valid = True
                
            return self.is_valid
            
        except requests.exceptions.Timeout:
            self.error_message = loc["api_timeout"]
            return False
        except requests.exceptions.ConnectionError:
            self.error_message = loc["api_no_connection"]
            return False
        except Exception as e:
            self.error_message = f"{loc['api_error']}: {str(e)}"
            return False
            
    def save_key_to_env(self, api_key: str) -> bool:
        """Save key to .env file"""
        try:
            if not self.ENV_FILE.exists():
                self.ENV_FILE.touch()
                
            set_key(str(self.ENV_FILE), "OPENROUTER_API_KEY", api_key.strip())
            self.api_key = api_key.strip()
            return True
        except Exception as e:
            self.error_message = f"{loc['api_save_error']}: {str(e)}"
            return False
            
    def get_remaining_balance(self) -> float:
        """Get remaining balance"""
        return max(0, self.balance - self.usage)
        
    def get_status_text(self) -> str:
        """Get status text"""
        if self.is_valid:
            return f"{loc['api_status_active']} (${self.get_remaining_balance():.2f})"
        elif self.error_message:
            return f"LLM: {self.error_message}"
        else:
            return loc["api_status_inactive"]
            
    def print_status(self):
        """Print status to console"""
        print("=" * 50)
        print("OpenRouter API Status:")
        if self.api_key:
            masked_key = self.api_key[:8] + "..." + self.api_key[-4:] if len(self.api_key) > 12 else "***"
            print(f"  API Key: {masked_key}")
        else:
            print(f"  API Key: {loc['api_key_not_found']}")
            
        if self.is_valid:
            print(f"  {loc['api_balance']}: ${self.balance:.2f}")
            print(f"  {loc['api_usage']}: ${self.usage:.2f}")
            print(f"  {loc['api_remaining']}: ${self.get_remaining_balance():.2f}")
            print(f"  {loc['api_status']}: {loc['api_status_ok']}")
        else:
            print(f"  {loc['api_status']}: {loc['api_status_fail']} - {self.error_message}")
        print("=" * 50)
