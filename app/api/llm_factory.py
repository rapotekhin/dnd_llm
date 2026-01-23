import os
from typing import Dict, Any, Optional, List
from abc import ABC, abstractmethod
from dotenv import load_dotenv
import time
import traceback

# Импорт OpenAI клиента
from openai import OpenAI

# Проверяем доступность Langfuse
try:
    from langfuse.openai import OpenAI as LangfuseOpenAI
    LANGFUSE_AVAILABLE = True
except ImportError:
    LANGFUSE_AVAILABLE = False
    
# Load environment variables
load_dotenv()


class LLMClient(ABC):
    """Abstract base class for LLM clients"""
    
    def __init__(self):
        """Initialize the LLM client"""
        pass
    
    @abstractmethod
    def generate_response(self, messages: List[Dict[str, str]], 
                         system_prompt: Optional[str] = None,
                         temperature: float = 0.7,
                         max_tokens: int = 3000) -> str:
        """Generate a response from the LLM"""
        pass
    
    @abstractmethod
    def generate_with_tools(self, messages: List[Dict[str, str]], 
                           tools: List[Dict[str, Any]],
                           system_prompt: Optional[str] = None,
                           temperature: float = 0.7,
                           max_tokens: int = 3000) -> Dict[str, Any]:
        """Generate a response with function calling capabilities"""
        pass


class OpenRouterClient(LLMClient):
    """Client for OpenRouter API (Gemini Flash)"""
    
    def __init__(self, model: str = "google/gemini-2.5-flash-lite-preview-09-2025"):
        super().__init__()
        self.api_key = os.getenv("OPENROUTER_API_KEY")
        if not self.api_key:
            raise ValueError("OpenRouter API key not found in environment variables")
        
        self.base_url = os.getenv("OPENROUTER_API_BASE", "https://openrouter.ai/api/v1")
        
        # Проверяем наличие учетных данных Langfuse
        self.langfuse_enabled = LANGFUSE_AVAILABLE and bool(os.getenv("LANGFUSE_PUBLIC_KEY") and os.getenv("LANGFUSE_SECRET_KEY"))
        
        # Используем Langfuse OpenAI клиент, если доступен
        if self.langfuse_enabled:
            self.client = LangfuseOpenAI(
                api_key=self.api_key,
                base_url=self.base_url,
                default_headers={
                    "HTTP-Referer": "https://github.com/yourusername/dnd_llm",
                    "X-Title": "D&D LLM Assistant"
                }
            )
            print("Using Langfuse OpenAI client for OpenRouter with automatic tracing")
        else:
            self.client = OpenAI(
                api_key=self.api_key,
                base_url=self.base_url,
                default_headers={
                    "HTTP-Referer": "https://github.com/yourusername/dnd_llm",
                    "X-Title": "D&D LLM Assistant"
                }
            )
            print("Using standard OpenAI client for OpenRouter")
            
        self.model = model
        self.max_retries = 3
        self.retry_delay = 2
        self.last_trace_id = None
        self.name = "openrouter"
        
        # Проверяем доступность API
        try:
            self.client.models.list(timeout=10)
            print(f"OpenRouter API is available at {self.base_url}")
        except Exception as e:
            print(f"Warning: OpenRouter API may not be available: {e}")
        
        print(f"Using OpenRouter API client with model {model}")
    
    def generate_response(self, messages: List[Dict[str, str]], 
                         system_prompt: Optional[str] = None,
                         temperature: float = 0.7,
                         max_tokens: int = 3000) -> str:
        """
        Generate a response from the LLM
        
        Args:
            messages: List of message dictionaries with 'role' and 'content' keys
            system_prompt: Optional system prompt to override the default
            temperature: Temperature for generation
            max_tokens: Maximum tokens to generate
            
        Returns:
            Generated text response
        """
        # Prepare messages with system prompt if provided
        all_messages = []
        if system_prompt:
            all_messages.append({"role": "system", "content": system_prompt})
        all_messages.extend(messages)
        
        # Попытки с увеличивающимся таймаутом
        timeouts = [10, 20, 30]
        last_error = None
        
        for i, timeout in enumerate(timeouts):
            try:
                response = self.client.chat.completions.create(
                    model=self.model,
                    messages=all_messages,
                    temperature=temperature,
                    max_tokens=max_tokens,
                    timeout=timeout,
                    name=self.name
                )
                
                return response.choices[0].message.content
            except Exception as e:
                last_error = e
                print(f"Error in API call (attempt {i+1}/{len(timeouts)}, timeout={timeout}s): {str(e)}")
                if i < len(timeouts) - 1:
                    print(f"Retrying with longer timeout...")
        
        print(f"All attempts failed: {str(last_error)}")
        traceback.print_exc()
        return f"Извините, произошла ошибка при обращении к API: {str(last_error)}. Пожалуйста, попробуйте еще раз позже."
    
    def generate_with_tools(self, messages: List[Dict[str, str]], 
                           tools: List[Dict[str, Any]],
                           system_prompt: Optional[str] = None,
                           temperature: float = 0.7,
                           max_tokens: int = 3000) -> Dict[str, Any]:
        """
        Generate a response from the LLM with tool use
        
        Args:
            messages: List of message dictionaries with 'role' and 'content' keys
            tools: List of tool definitions
            system_prompt: Optional system prompt to override the default
            temperature: Temperature for generation
            max_tokens: Maximum tokens to generate
            
        Returns:
            Dictionary with 'content' and 'tool_calls' keys
        """
        # Prepare messages with system prompt if provided
        all_messages = []
        if system_prompt:
            all_messages.append({"role": "system", "content": system_prompt})
        all_messages.extend(messages)
        
        # Попытки с увеличивающимся таймаутом
        timeouts = [10, 20, 30]
        last_error = None
        
        for i, timeout in enumerate(timeouts):
            try:
                response = self.client.chat.completions.create(
                    model=self.model,
                    messages=all_messages,
                    tools=tools,
                    temperature=temperature,
                    max_tokens=max_tokens,
                    timeout=timeout
                )
                
                # Extract tool calls if any
                tool_calls = None
                if response.choices[0].message.tool_calls:
                    tool_calls = []
                    for tool_call in response.choices[0].message.tool_calls:
                        tool_calls.append({
                            "id": tool_call.id,
                            "type": tool_call.type,
                            "function": {
                                "name": tool_call.function.name,
                                "arguments": tool_call.function.arguments
                            }
                        })
                
                return {
                    "content": response.choices[0].message.content,
                    "tool_calls": tool_calls
                }
            except Exception as e:
                last_error = e
                print(f"Error in API call (attempt {i+1}/{len(timeouts)}, timeout={timeout}s): {str(e)}")
                if i < len(timeouts) - 1:
                    print(f"Retrying with longer timeout...")
        
        print(f"All attempts failed: {str(last_error)}")
        traceback.print_exc()
        return {
            "content": f"Извините, произошла ошибка при обращении к API: {str(last_error)}. Пожалуйста, попробуйте еще раз позже.",
            "tool_calls": None
        }


def get_llm_client(provider: str = "openrouter", **kwargs) -> LLMClient:
    """
    Factory function to get an LLM client
        
        Args:
        provider: Provider name (only 'openrouter' is supported)
        **kwargs: Additional arguments to pass to the client constructor
        
    Returns:
        LLM client instance
    """
    if provider.lower() == "openrouter":
        model = kwargs.get("model", "google/gemini-2.5-flash-lite-preview-09-2025")
        return OpenRouterClient(model=model)
    else:
        # Для обратной совместимости перенаправляем все запросы на OpenRouter
        print(f"Warning: Provider '{provider}' is not supported. Using OpenRouter instead.")
        model = kwargs.get("model", "google/gemini-2.5-flash-lite-preview-09-2025")
        return OpenRouterClient(model=model)
