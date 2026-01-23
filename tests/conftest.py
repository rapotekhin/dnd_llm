import os
import sys
import pytest
from dotenv import load_dotenv

# Загружаем переменные окружения из .env файла
load_dotenv()

# Добавляем корневую директорию проекта в путь для импорта
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Фикстура для проверки наличия API ключей
@pytest.fixture(scope="session")
def api_keys():
    """Проверяет наличие API ключей и возвращает словарь с результатами"""
    return {
        "openai": bool(os.getenv("OPENAI_API_KEY")),
        "grok": bool(os.getenv("GROK_API_KEY"))
    }

# Фикстура для пропуска тестов, если нет API ключа OpenAI
@pytest.fixture(scope="session")
def requires_openai_api(api_keys):
    """Пропускает тест, если нет API ключа OpenAI"""
    if not api_keys["openai"]:
        pytest.skip("Requires OPENAI_API_KEY environment variable")

# Фикстура для пропуска тестов, если нет API ключа Grok
@pytest.fixture(scope="session")
def requires_grok_api(api_keys):
    """Пропускает тест, если нет API ключа Grok"""
    if not api_keys["grok"]:
        pytest.skip("Requires GROK_API_KEY environment variable")

# Отключаем предупреждения SSL для тестов
@pytest.fixture(autouse=True)
def disable_ssl_warnings():
    """Отключает предупреждения SSL для всех тестов"""
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    yield