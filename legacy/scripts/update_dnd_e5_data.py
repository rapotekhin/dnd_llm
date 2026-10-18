#!/usr/bin/env python3
"""
Скрипт для рекурсивного скачивания всех данных из D&D 5e API.
Скачивает все эндпоинты, включая вложенные ссылки, и сохраняет
в локальную папку для офлайн использования.

Использование:
    python update_dnd_e5_data.py           # Скачать только новые файлы
    python update_dnd_e5_data.py --force   # Перескачать всё
"""
import argparse
import json
import os
import time
import requests
from pathlib import Path

# Конфигурация
API_BASE_URL = "https://www.dnd5eapi.co"
API_VERSION = "/api/2014"
PATH_TO_DATA = Path("./dnd_5e_data/api/2014")
REQUEST_DELAY = 0.001  # Пауза между запросами (50ms)


def ensure_dir(path: Path) -> None:
    """Создаёт директорию, если она не существует."""
    path.parent.mkdir(parents=True, exist_ok=True)


def save_json(data: dict, local_path: Path) -> None:
    """Сохраняет JSON в файл с красивым форматированием."""
    ensure_dir(local_path)
    with open(local_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def load_json(local_path: Path) -> dict | None:
    """Загружает JSON из файла. Возвращает None если файл невалидный."""
    try:
        with open(local_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, FileNotFoundError, IOError):
        return None


def fetch_json(url: str) -> dict | None:
    """Скачивает JSON по URL."""
    try:
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"  [ERROR] Failed to download {url}: {e}")
        return None


def is_api_reference(obj) -> bool:
    """
    Проверяет, является ли объект ссылкой на другой ресурс API.
    Ссылки обычно имеют поля 'url' и 'index' или 'url' и 'name'.
    """
    if not isinstance(obj, dict):
        return False
    if "url" not in obj:
        return False
    url = obj.get("url", "")
    return isinstance(url, str) and url.startswith("/api/2014/")


def url_to_filepath(api_url: str) -> Path:
    """
    Преобразует URL API в локальный путь файла.
    /api/2014/spells/fireball -> ./dnd_5e_data/api/2014/spells/fireball.json
    """
    rel_path = api_url.replace("/api/2014/", "").replace("/api/2014", "")
    if not rel_path:
        return PATH_TO_DATA / "_root.json"
    return PATH_TO_DATA / f"{rel_path}.json"


def filepath_to_url(filepath: Path) -> str | None:
    """
    Преобразует локальный путь файла обратно в URL API.
    ./dnd_5e_data/api/2014/spells/fireball.json -> /api/2014/spells/fireball
    """
    try:
        rel_path = filepath.relative_to(PATH_TO_DATA)
        rel_str = str(rel_path).replace("\\", "/").replace(".json", "")
        if rel_str == "_root":
            return "/api/2014"
        return f"/api/2014/{rel_str}"
    except ValueError:
        return None


def is_api_url_string(value) -> bool:
    """Проверяет, является ли значение строкой-ссылкой на API."""
    return isinstance(value, str) and value.startswith("/api/2014/")


def extract_api_urls(obj) -> set[str]:
    """
    Рекурсивно извлекает все URL ссылок на API из объекта.
    Поддерживает два формата:
    1. Объекты с полем "url": {"url": "/api/2014/...", "index": "..."}
    2. Простые строки: "/api/2014/..."
    """
    urls = set()
    
    if isinstance(obj, dict):
        if is_api_reference(obj):
            urls.add(obj["url"])
        for value in obj.values():
            if is_api_url_string(value):
                urls.add(value)
            else:
                urls.update(extract_api_urls(value))
    elif isinstance(obj, list):
        for item in obj:
            urls.update(extract_api_urls(item))
    elif is_api_url_string(obj):
        urls.add(obj)
    
    return urls


def scan_existing_files() -> dict[str, Path]:
    """
    Сканирует папку с данными и возвращает словарь URL -> путь к файлу
    для всех уже скачанных файлов.
    """
    existing = {}
    if not PATH_TO_DATA.exists():
        return existing
    
    for json_file in PATH_TO_DATA.rglob("*.json"):
        url = filepath_to_url(json_file)
        if url:
            existing[url] = json_file
    
    return existing


def download_all_data(force: bool = False):
    """Основная функция для скачивания всех данных из API."""
    print("=" * 60)
    print("D&D 5e API Data Downloader")
    print("=" * 60)
    print(f"API: {API_BASE_URL}{API_VERSION}")
    print(f"Data folder: {PATH_TO_DATA}")
    print(f"Force redownload: {force}")
    print("=" * 60)
    
    # Создаём корневую директорию
    PATH_TO_DATA.mkdir(parents=True, exist_ok=True)
    
    # Сканируем существующие файлы
    print("Scanning existing files...")
    existing_files = scan_existing_files()
    print(f"Found {len(existing_files)} existing files")
    print("=" * 60)
    
    # Множество для отслеживания уже обработанных URL
    seen_urls: set[str] = set()
    # Очередь URL для обработки
    queue: list[str] = [API_VERSION]
    
    downloaded_count = 0
    skipped_count = 0
    
    while queue:
        current_url = queue.pop(0)
        
        # Пропускаем уже обработанные в этой сессии
        if current_url in seen_urls:
            continue
        seen_urls.add(current_url)
        
        # Путь для сохранения
        local_path = url_to_filepath(current_url)
        
        # Проверяем, есть ли уже файл и валидный ли он
        if not force and current_url in existing_files:
            # Пробуем загрузить и проверить валидность JSON
            data = load_json(local_path)
            if data is not None:
                # Файл существует и валидный - пропускаем скачивание
                skipped_count += 1
                # Но всё равно извлекаем ссылки для обхода
                new_urls = extract_api_urls(data)
                for url in new_urls:
                    if url not in seen_urls:
                        queue.append(url)
                continue
            else:
                # Файл повреждён - перескачаем
                print(f"  [INVALID] Corrupted file, redownloading: {current_url}")
        
        # Скачиваем данные
        print(f"  [GET] Downloading: {current_url}")
        full_url = f"{API_BASE_URL}{current_url}"
        data = fetch_json(full_url)
        
        if data is None:
            continue
        
        # Сохраняем
        save_json(data, local_path)
        downloaded_count += 1
        
        # Обновляем словарь существующих файлов
        existing_files[current_url] = local_path
        
        # Извлекаем все вложенные ссылки и добавляем в очередь
        new_urls = extract_api_urls(data)
        for url in new_urls:
            if url not in seen_urls:
                queue.append(url)
        
        # Небольшая пауза между запросами
        time.sleep(REQUEST_DELAY)
        
        # Показываем прогресс каждые 50 файлов
        if downloaded_count % 50 == 0:
            print(f"  [PROGRESS] Downloaded: {downloaded_count}, in queue: {len(queue)}")
    
    print("=" * 60)
    print("DONE!")
    print(f"   Downloaded: {downloaded_count} files")
    print(f"   Skipped (already existed): {skipped_count} files")
    print(f"   Total URLs processed: {len(seen_urls)}")
    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description="Download all D&D 5e API data for offline use"
    )
    parser.add_argument(
        "--force", "-f",
        action="store_true",
        help="Force redownload all files, even if they exist"
    )
    args = parser.parse_args()
    
    download_all_data(force=args.force)


if __name__ == "__main__":
    main()
