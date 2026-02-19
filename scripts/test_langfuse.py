"""
Проверка инициализации Langfuse и ручная отправка тестового трейса.

Запуск из корня проекта (обязательно через venv):
  venv\\Scripts\\python scripts/test_langfuse.py
  или: python scripts/test_langfuse.py  (если python уже из venv)
"""
import os
import sys
from pathlib import Path

# корень проекта
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# загружаем .env до любых импортов из game
from dotenv import load_dotenv
load_dotenv(ROOT / ".env")

def main():
    pk = os.getenv("LANGFUSE_PUBLIC_KEY")
    sk = os.getenv("LANGFUSE_SECRET_KEY")
    host = os.getenv("LANGFUSE_HOST", "https://cloud.langfuse.com")

    print("LANGFUSE_PUBLIC_KEY:", "SET" if pk else "NOT SET")
    print("LANGFUSE_SECRET_KEY:", "SET" if sk else "NOT SET")
    print("LANGFUSE_HOST:", host)

    if not pk or not sk:
        print("\nЗадайте LANGFUSE_PUBLIC_KEY и LANGFUSE_SECRET_KEY в .env")
        return 1

    try:
        from langfuse import Langfuse, get_client
    except ImportError as e:
        print("\nLangfuse не установлен:", e)
        return 1

    # инициализация так же, как в api_manager
    Langfuse(public_key=pk, secret_key=sk, host=host)
    client = get_client(public_key=pk)

    if getattr(client, "_tracing_enabled", True) is False:
        print("\nВнимание: клиент Langfuse отключён (tracing_enabled=False)")

    # тестовый трейс вручную
    print("\nОтправка тестового трейса...")
    with client.start_as_current_span(name="test-exploration-trace") as span:
        span.update_trace(
            name="test-exploration-session",
            session_id="test-session-001",
            tags=["exploration", "test"],
            metadata={"source": "scripts/test_langfuse.py"},
        )
        span.update(input="test input", output="test output")
        trace_id = client.get_current_trace_id()

    client.flush()
    print("Готово.")
    if trace_id:
        url = client.get_trace_url(trace_id=trace_id)
        if url:
            print("Трейс в UI:", url)
    else:
        print("Проверь трейс в Langfuse UI (Traces).")
    return 0

if __name__ == "__main__":
    sys.exit(main())
