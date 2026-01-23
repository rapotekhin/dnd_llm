import os
import pytest
from unittest.mock import patch, MagicMock
import sys
import time

# Добавляем корневую директорию проекта в путь для импорта
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

# Импортируем наш клиент Grok
from app.api.llm_factory import GrokClient

class TestGrokClient:
    """Тесты для Grok клиента"""
    
    def setup_method(self):
        """Настройка перед каждым тестом"""
        # Создаем клиент, если есть API ключ
        if os.getenv("GROK_API_KEY"):
            self.client = GrokClient(model="grok-2-latest")
        else:
            self.client = None
    
    def test_initialization(self, requires_grok_api):
        """Тест инициализации клиента"""
        assert self.client is not None
        assert self.client.model == "grok-2-latest"
        assert self.client.api_key == os.getenv("GROK_API_KEY")
        assert "api.x.ai" in self.client.base_url or "api.groq.com" in self.client.base_url
    
    def test_api_connection(self, requires_grok_api):
        """Тест подключения к API"""
        # Проверяем, что хотя бы один из URL работает
        api_available = False
        for url in self.client.alternative_urls:
            try:
                # Временно меняем base_url для проверки
                self.client.client.base_url = url
                # Простой запрос для проверки соединения
                self.client.client.models.list(timeout=5)
                api_available = True
                print(f"Successfully connected to Grok API at {url}")
                break
            except Exception as e:
                print(f"Could not connect to Grok API at {url}: {str(e)}")
        
        assert api_available, "Could not connect to any Grok API endpoints"
    
    def test_generate_response(self, requires_grok_api):
        """Тест генерации ответа"""
        # Пропускаем тест, если API недоступен
        try:
            self.client.client.models.list(timeout=5)
        except Exception as e:
            pytest.skip(f"Skipping test because API is not available: {str(e)}")
        
        messages = [{"role": "user", "content": "Say 'Hello, Test!'"}]
        response = self.client.generate_response(messages, temperature=0.7, max_tokens=50)
        
        # Проверяем, что ответ не пустой
        assert response is not None
        assert len(response) > 0
        
        # Выводим ответ для отладки
        print(f"Grok response: {response}")
    
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
        with patch.object(GrokClient, '__init__', return_value=None):
            client = GrokClient()
            client.model = "grok-2-latest"
            client.client = mock_client
            
            # Вызываем метод
            messages = [{"role": "user", "content": "Say 'Hello, Test!'"}]
            response = client.generate_response(messages)
            
            # Проверяем результат
            assert response == "Hello, Test!"
            
            # Проверяем, что мок был вызван с правильными параметрами
            mock_client.chat.completions.create.assert_called_once()
            args, kwargs = mock_client.chat.completions.create.call_args
            assert kwargs["model"] == "grok-2-latest"
            assert len(kwargs["messages"]) == 1
            assert kwargs["messages"][0]["role"] == "user"
            assert kwargs["messages"][0]["content"] == "Say 'Hello, Test!'"

if __name__ == "__main__":
    pytest.main(["-v", __file__])
