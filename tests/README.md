# Тесты для D&D LLM Game Assistant

В этой директории находятся тесты для проверки работы различных компонентов приложения.

## Структура тестов

- `api_tests/` - тесты для API клиентов (OpenAI, Grok)
  - `openai_test.py` - тесты для OpenAI клиента
  - `xai_test.py` - тесты для Grok (X.AI) клиента
  - `test_combined.py` - комбинированные тесты для сравнения API

## Запуск тестов

### Подготовка

1. Убедитесь, что у вас установлены все зависимости:
   ```
   pip install -r requirements.txt
   ```

2. Создайте файл `.env` с необходимыми API ключами:
   ```
   OPENAI_API_KEY=your_openai_api_key_here
   GROK_API_KEY=your_grok_api_key_here
   GROK_API_BASE=https://api.x.ai/v1
   ```

### Запуск всех тестов

```
pytest tests/
```

### Запуск конкретных тестов

```
# Тесты для OpenAI
pytest tests/api_tests/openai_test.py

# Тесты для Grok
pytest tests/api_tests/xai_test.py

# Комбинированные тесты
pytest tests/api_tests/test_combined.py
```

### Запуск тестов с подробным выводом

```
pytest -v tests/
```

## Особенности тестов

- Тесты, требующие API ключей, будут пропущены, если соответствующие ключи не найдены в переменных окружения
- Для тестов с моками не требуются реальные API ключи
- Тесты для Grok API проверяют доступность API перед выполнением и пропускаются, если API недоступен 