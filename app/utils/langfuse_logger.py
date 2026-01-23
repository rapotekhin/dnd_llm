import os
import time
import uuid
from typing import Dict, Any, List, Optional
from dotenv import load_dotenv

# Импортируем Langfuse SDK
try:
    from langfuse import Langfuse
    from langfuse.decorators import langfuse_context
    LANGFUSE_AVAILABLE = True
except ImportError:
    LANGFUSE_AVAILABLE = False
    print("Langfuse SDK not available. Install with 'pip install langfuse'")

# Загружаем переменные окружения
load_dotenv()

class LangfuseLogger:
    """Класс для логгирования запросов к LLM в Langfuse"""
    
    def __init__(self):
        """Инициализация логгера Langfuse"""
        self.enabled = LANGFUSE_AVAILABLE and self._check_credentials()
        self.client = None
        self.last_trace_id = None
        
        if self.enabled:
            try:
                self.client = Langfuse(
                    public_key=os.getenv("LANGFUSE_PUBLIC_KEY"),
                    secret_key=os.getenv("LANGFUSE_SECRET_KEY"),
                    host=os.getenv("LANGFUSE_HOST", "https://cloud.langfuse.com")
                )
                print("Langfuse logger initialized successfully")
            except Exception as e:
                print(f"Failed to initialize Langfuse: {e}")
                self.enabled = False
    
    def _check_credentials(self) -> bool:
        """Проверка наличия учетных данных Langfuse"""
        has_credentials = bool(os.getenv("LANGFUSE_PUBLIC_KEY") and os.getenv("LANGFUSE_SECRET_KEY"))
        if not has_credentials:
            print("Langfuse credentials not found in environment variables")
        return has_credentials
    
    def log_llm_request(self, 
                       model: str, 
                       messages: List[Dict[str, str]], 
                       system_prompt: Optional[str] = None,
                       temperature: float = 0.7,
                       tools: Optional[List[Dict[str, Any]]] = None,
                       response: Optional[Dict[str, Any]] = None,
                       user_id: Optional[str] = None,
                       session_id: Optional[str] = None) -> Optional[str]:
        """
        Логгирование запроса к LLM
        
        Args:
            model: Название модели
            messages: Список сообщений
            system_prompt: Системный промпт
            temperature: Температура
            tools: Список инструментов
            response: Ответ от LLM
            user_id: ID пользователя
            session_id: ID сессии
            
        Returns:
            ID трассировки или None, если логгирование отключено
        """
        if not self.enabled or not self.client:
            return None
        
        try:
            # Создаем уникальный ID для трассировки
            trace_id = str(uuid.uuid4())
            
            # Создаем трассировку
            trace = self.client.trace(
                id=trace_id,
                name="LLM Request",
                user_id=user_id,
                session_id=session_id or str(uuid.uuid4())
            )
            
            # Логгируем запрос
            span = trace.span(
                name=f"{model} request",
                start_time=time.time()
            )
            
            # Добавляем входные данные
            input_data = {
                "messages": messages,
                "temperature": temperature
            }
            
            if system_prompt:
                input_data["system_prompt"] = system_prompt
                
            if tools:
                input_data["tools"] = tools
            
            span.input = input_data
            
            # Если есть ответ, логгируем его
            if response:
                span.output = response
                
                # Добавляем метрики
                if "content" in response:
                    span.add_metric("response_length", len(response["content"]))
                
                if "tool_calls" in response and response["tool_calls"]:
                    span.add_metric("tool_calls_count", len(response["tool_calls"]))
            
            # Завершаем спан
            span.end()
            
            self.last_trace_id = trace_id
            
            return trace_id
        except Exception as e:
            print(f"Error logging to Langfuse: {e}")
            return None
    
    def log_user_feedback(self, trace_id: str, score: float, comment: Optional[str] = None) -> bool:
        """
        Логгирование обратной связи от пользователя
        
        Args:
            trace_id: ID трассировки
            score: Оценка (от 0 до 1)
            comment: Комментарий пользователя
            
        Returns:
            True, если логгирование успешно, иначе False
        """
        if not self.enabled or not self.client or not trace_id:
            return False
        
        try:
            self.client.score(
                trace_id=trace_id,
                name="user_feedback",
                value=score,
                comment=comment
            )
            return True
        except Exception as e:
            print(f"Error logging feedback to Langfuse: {e}")
            return False 