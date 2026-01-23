import os
import pytest
from unittest.mock import patch, MagicMock
import sys
import time

# Добавляем корневую директорию проекта в путь для импорта
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

# Импортируем наш клиент OpenAI
from app.api.llm_factory import OpenAIClient

class TestOpenAIClient:
    """Тесты для OpenAI клиента"""
    
    def setup_method(self):
        """Настройка перед каждым тестом"""
        # Создаем клиент, если есть API ключ
        if os.getenv("OPENAI_API_KEY"):
            self.client = OpenAIClient(model="gpt-4o-mini")
        else:
            self.client = None
    
    def test_initialization(self, requires_openai_api):
        """Тест инициализации клиента"""
        assert self.client is not None
        assert self.client.model == "gpt-4o-mini"
        assert self.client.api_key == os.getenv("OPENAI_API_KEY")
    
    def test_generate_response(self, requires_openai_api):
        """Тест генерации ответа"""
        messages = [{"role": "user", "content": "Say 'Hello, Test!'"}]
        response = self.client.generate_response(messages, temperature=0.7, max_tokens=50)
        
        # Проверяем, что ответ не пустой
        assert response is not None
        assert len(response) > 0
        
        # Выводим ответ для отладки
        print(f"OpenAI response: {response}")
    
    def test_mock_generate_response(self):
        """Тест с моком для генерации ответа"""
        # Создаем мок для ответа
        mock_completion = MagicMock()
        mock_choice = MagicMock()
        mock_message = MagicMock()
        
        mock_message.content = "Hello, Test!"
        mock_choice.message = mock_message
        mock_completion.choices = [mock_choice]
        
        # Создаем мок для клиента
        mock_client = MagicMock()
        mock_client.chat.completions.create.return_value = mock_completion
        
        # Создаем клиент и заменяем его client на мок
        with patch.object(OpenAIClient, '__init__', return_value=None):
            client = OpenAIClient()
            client.model = "gpt-4o-mini"
            client.client = mock_client
            
            # Вызываем метод
            messages = [{"role": "user", "content": "Say 'Hello, Test!'"}]
            response = client.generate_response(messages)
            
            # Проверяем результат
            assert response == "Hello, Test!"
            
            # Проверяем, что мок был вызван с правильными параметрами
            mock_client.chat.completions.create.assert_called_once()
            args, kwargs = mock_client.chat.completions.create.call_args
            assert kwargs["model"] == "gpt-4o-mini"
            assert len(kwargs["messages"]) == 1
            assert kwargs["messages"][0]["role"] == "user"
            assert kwargs["messages"][0]["content"] == "Say 'Hello, Test!'"

if __name__ == "__main__":
    pytest.main(["-v", __file__])
