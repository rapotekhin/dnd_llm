import os
import json
from typing import Dict, Any, List, Optional
import streamlit as st

class LocalizationManager:
    """Manager for application localization"""
    
    def __init__(self, locales_dir: str = "app/locales"):
        """
        Initialize the localization manager
        
        Args:
            locales_dir: Directory containing locale files
        """
        self.locales_dir = locales_dir
        self.locales = self._load_locales()
        self.default_locale = "en"
        
        # Ensure locales directory exists
        os.makedirs(locales_dir, exist_ok=True)
        
        # Create default locale files if they don't exist
        self._ensure_default_locales()
    
    def _load_locales(self) -> Dict[str, Dict[str, str]]:
        """Load all available locales"""
        locales = {}
        
        if os.path.exists(self.locales_dir):
            for filename in os.listdir(self.locales_dir):
                if filename.endswith(".json"):
                    locale_code = filename.split(".")[0]
                    locale_path = os.path.join(self.locales_dir, filename)
                    
                    try:
                        with open(locale_path, 'r', encoding='utf-8') as f:
                            locales[locale_code] = json.load(f)
                    except Exception as e:
                        print(f"Error loading locale {locale_code}: {e}")
        
        return locales
    
    def _ensure_default_locales(self):
        """Ensure default locales exist"""
        # Create locales directory if it doesn't exist
        os.makedirs(self.locales_dir, exist_ok=True)
        
        # Define default English locale
        en_locale = {
            "app_title": "D&D LLM Game Assistant",
            "language": "Language",
            "game_tab": "Game",
            "character_tab": "Character Sheet",
            "campaign_tab": "Campaign",
            "save_btn": "Save",
            "delete_btn": "Delete",
            "load_btn": "Load",
            "create_btn": "Create",
            "cancel_btn": "Cancel",
            "success_save": "Saved successfully!",
            "error_save": "Failed to save",
            "campaign_info": "Campaign Information",
            "campaign_name": "Campaign Name",
            "dm_notes": "DM Notes",
            "current_location": "Current Location",
            "active_quest": "Active Quest",
            "save_campaign": "Save Campaign",
            "campaign_docs": "Campaign Documents",
            "upload_doc": "Upload campaign document",
            "doc_available": "Available in chat",
            "doc_unavailable": "Not available in chat",
            "load_to_chat": "Load to Chat",
            "doc_added": "Document added to the campaign and available in chat!",
            "doc_save_failed": "Document saved but failed to add to vector database. You can try to load it to chat later.",
            "doc_delete_success": "Document deleted",
            "doc_delete_failed": "Failed to delete document",
            "how_to_use_docs": "How to use documents in chat",
            "no_docs": "No documents uploaded for this campaign yet",
            "character_info": "Basic Information",
            "character_name": "Character Name",
            "character_race": "Race",
            "character_class": "Class",
            "character_level": "Level",
            "character_desc": "Character Description",
            "character_bg": "Background",
            "attributes": "Attributes",
            "strength": "Strength",
            "dexterity": "Dexterity",
            "constitution": "Constitution",
            "intelligence": "Intelligence",
            "wisdom": "Wisdom",
            "charisma": "Charisma",
            "modifier": "Modifier",
            "skills": "Skills",
            "inventory": "Inventory",
            "no_items": "No items in inventory",
            "add_item": "Add New Item",
            "item_name": "Item Name",
            "item_type": "Item Type",
            "quantity": "Quantity",
            "description": "Description",
            "properties": "Properties (JSON)",
            "add_item_btn": "Add Item",
            "item_added": "Item added to inventory!",
            "item_add_failed": "Failed to add item to inventory. Please try again.",
            "notes": "Notes",
            "character_notes": "Character Notes",
            "save_changes": "Save Changes",
            "changes_saved": "Character updated successfully!",
            "changes_failed": "Failed to update character. Please try again.",
            "create_character": "Create New Character",
            "character_created": "Character created successfully!",
            "character_create_failed": "Failed to create character. Please try again.",
            "no_character": "No character loaded. Select a character from the sidebar or create a new one.",
            "select_character": "Select Character",
            "load_character": "Load Character",
            "no_characters": "No characters found. Create a new character in the Character Sheet tab.",
            "llm_settings": "LLM Settings",
            "llm_provider": "LLM Provider",
            "model": "Model",
            "temperature": "Temperature",
            "apply_settings": "Apply LLM Settings",
            "settings_updated": "LLM settings updated to",
            "system_prompt": "System Prompt",
            "dm_style": "DM Style",
            "edit_prompt": "Edit Prompt",
            "save_prompt": "Save Prompt",
            "prompt_saved": "Prompt saved!",
            "prompt_save_failed": "Failed to save prompt",
            "set_active_style": "Set as Active DM Style",
            "style_activated": "set as active DM style!",
            "style_activate_failed": "Failed to set active prompt",
            "knowledge_base": "Knowledge Base",
            "search_kb": "Search Knowledge Base",
            "search_btn": "Search",
            "no_results": "No results found",
            "about": "About",
            "about_text": "D&D LLM Game Assistant helps you play Dungeons & Dragons with AI. Upload campaign documents, manage characters, and interact with an AI Dungeon Master.",
            "version": "Version",
            "game_session": "Game Session",
            "chat_placeholder": "What would you like to do?",
            "thinking": "Thinking...",
            "docs_usage_title": "Using Campaign Documents in Chat",
            "docs_usage_step1": "1. Upload your campaign documents (PDF, TXT, MD) using the uploader above",
            "docs_usage_step2": "2. Make sure they are loaded to chat (green checkmark)",
            "docs_usage_step3": "3. In the chat, you can ask questions about the documents",
            "docs_usage_examples": "Example questions:",
            "docs_usage_example1": "- \"What does the rulebook say about spellcasting?\"",
            "docs_usage_example2": "- \"Tell me about the main villain in the campaign document\"",
            "docs_usage_example3": "- \"Summarize the key locations in the uploaded documents\"",
            "docs_usage_footer": "The AI will search through your documents and provide relevant information.",
            "applying_settings": "Applying settings...",
            "settings_applied": "Settings applied successfully!",
            "default": "Default",
            "friendly_dm": "Friendly DM",
            "hardcore_dm": "Hardcore DM",
            "narrative_dm": "Narrative DM",
            "custom": "Custom",
            "roll_dice_desc": "Roll dice using standard D&D notation",
            "dice_notation_desc": "Dice notation (e.g., '2d6+3', '1d20', '3d8-2')",
            "advantage_desc": "Roll with advantage (true) or disadvantage (false)",
            "execute_code_desc": "Execute Python code",
            "code_desc": "Python code to execute",
            "query_db_desc": "Query the database for character or campaign information",
            "query_desc": "SQL query to execute",
            "search_kb_desc": "Search the vector database for relevant information",
            "search_query_desc": "Search query",
            "num_results_desc": "Number of results to return",
            "dice_roll": "Dice Roll",
            "rolls": "Rolls",
            "total": "Total",
            "code_executed": "Code executed",
            "db_queried": "Database queried",
            "kb_searched": "Knowledge base searched",
            "source": "Source",
            "relevance": "Relevance",
            "send_message": "Send",
            "clear_chat": "Clear Chat",
            "campaign_saved": "Campaign saved!",
            "campaign_save_failed": "Failed to save campaign",
            "document_name": "Document Name",
            "document_status": "Status",
            "document_actions": "Actions",
            "available_in_chat": "Available in Chat",
            "not_available_in_chat": "Not Available in Chat",
            "delete_document": "Delete",
            "document_deleted": "Document deleted!",
            "document_delete_failed": "Failed to delete document",
            "document_loaded": "Document loaded to chat!",
            "document_load_failed": "Failed to load document to chat",
            "docs_usage_instructions": "You can ask the AI about information in your uploaded documents. Try questions like:",
            "docs_usage_example1": "- \"What does the document say about the main villain?\"",
            "docs_usage_example2": "- \"Tell me about the main villain in the campaign document\"",
            "docs_usage_example3": "- \"Summarize the key locations in the uploaded documents\"",
            "docs_usage_footer": "The AI will search through your documents and provide relevant information."
        }
        
        # Define default Russian locale
        ru_locale = {
            "app_title": "D&D Игровой Ассистент с ИИ",
            "language": "Язык",
            "game_tab": "Игра",
            "character_tab": "Лист Персонажа",
            "campaign_tab": "Кампания",
            "save_btn": "Сохранить",
            "delete_btn": "Удалить",
            "load_btn": "Загрузить",
            "create_btn": "Создать",
            "cancel_btn": "Отмена",
            "success_save": "Успешно сохранено!",
            "error_save": "Ошибка сохранения",
            "campaign_info": "Информация о Кампании",
            "campaign_name": "Название Кампании",
            "dm_notes": "Заметки Мастера",
            "current_location": "Текущее Местоположение",
            "active_quest": "Активный Квест",
            "save_campaign": "Сохранить Кампанию",
            "campaign_docs": "Документы Кампании",
            "upload_doc": "Загрузить документ кампании",
            "doc_available": "Доступен в чате",
            "doc_unavailable": "Недоступен в чате",
            "load_to_chat": "Загрузить в Чат",
            "doc_added": "Документ добавлен в кампанию и доступен в чате!",
            "doc_save_failed": "Документ сохранен, но не удалось добавить его в векторную базу данных. Вы можете попробовать загрузить его в чат позже.",
            "doc_delete_success": "Документ удален",
            "doc_delete_failed": "Не удалось удалить документ",
            "how_to_use_docs": "Как использовать документы в чате",
            "no_docs": "Для этой кампании еще не загружено документов",
            "character_info": "Основная Информация",
            "character_name": "Имя Персонажа",
            "character_race": "Раса",
            "character_class": "Класс",
            "character_level": "Уровень",
            "character_desc": "Описание Персонажа",
            "character_bg": "Предыстория",
            "attributes": "Характеристики",
            "strength": "Сила",
            "dexterity": "Ловкость",
            "constitution": "Телосложение",
            "intelligence": "Интеллект",
            "wisdom": "Мудрость",
            "charisma": "Харизма",
            "modifier": "Модификатор",
            "skills": "Навыки",
            "inventory": "Инвентарь",
            "no_items": "В инвентаре нет предметов",
            "add_item": "Добавить Новый Предмет",
            "item_name": "Название Предмета",
            "item_type": "Тип Предмета",
            "quantity": "Количество",
            "description": "Описание",
            "properties": "Свойства (JSON)",
            "add_item_btn": "Добавить Предмет",
            "item_added": "Предмет добавлен в инвентарь!",
            "item_add_failed": "Не удалось добавить предмет в инвентарь. Пожалуйста, попробуйте снова.",
            "notes": "Заметки",
            "character_notes": "Заметки о Персонаже",
            "save_changes": "Сохранить Изменения",
            "changes_saved": "Персонаж успешно обновлен!",
            "changes_failed": "Не удалось обновить персонажа. Пожалуйста, попробуйте снова.",
            "create_character": "Создать Нового Персонажа",
            "character_created": "Персонаж успешно создан!",
            "character_create_failed": "Не удалось создать персонажа. Пожалуйста, попробуйте снова.",
            "no_character": "Персонаж не загружен. Выберите персонажа из боковой панели или создайте нового.",
            "select_character": "Выбор Персонажа",
            "load_character": "Загрузить Персонажа",
            "no_characters": "Персонажи не найдены. Создайте нового персонажа на вкладке Лист Персонажа.",
            "llm_settings": "Настройки ИИ",
            "llm_provider": "Провайдер ИИ",
            "model": "Модель",
            "temperature": "Температура",
            "apply_settings": "Применить Настройки ИИ",
            "settings_updated": "Настройки ИИ обновлены до",
            "system_prompt": "Системный Промпт",
            "dm_style": "Стиль Мастера",
            "edit_prompt": "Просмотр/Редактирование Промпта",
            "save_prompt": "Сохранить Промпт",
            "prompt_saved": "Промпт сохранен!",
            "prompt_save_failed": "Не удалось сохранить промпт",
            "set_active_style": "Установить как Активный Стиль",
            "style_activated": "установлен как активный стиль Мастера!",
            "style_activate_failed": "Не удалось установить активный промпт",
            "knowledge_base": "База Знаний",
            "search_kb": "Поиск в Базе Знаний",
            "search_btn": "Поиск",
            "no_results": "Результаты не найдены",
            "about": "О Программе",
            "about_text": "D&D Игровой Ассистент с ИИ помогает играть в Dungeons & Dragons с помощью искусственного интеллекта. Загружайте документы кампании, управляйте персонажами и взаимодействуйте с ИИ-Мастером Подземелий.",
            "version": "Версия",
            "game_session": "Игровая Сессия",
            "chat_placeholder": "Что вы хотите сделать?",
            "thinking": "Думаю...",
            "docs_usage_title": "Как Использовать Документы в Чате",
            "docs_usage_step1": "1. Загрузите документы кампании (PDF, TXT, MD) с помощью загрузчика выше",
            "docs_usage_step2": "2. Убедитесь, что они загружены в чат (зеленая галочка)",
            "docs_usage_step3": "3. В чате вы можете задавать вопросы о документах",
            "docs_usage_examples": "Примеры вопросов:",
            "docs_usage_example1": "- \"Что говорится в документе о главном злодее?\"",
            "docs_usage_example2": "- \"Расскажи о главном злодее из документа кампании\"",
            "docs_usage_example3": "- \"Опиши ключевые локации из загруженных документов\"",
            "docs_usage_footer": "ИИ будет искать информацию в ваших документах и предоставлять релевантные данные.",
            "applying_settings": "Применяем настройки...",
            "settings_applied": "Настройки успешно применены!",
            "default": "По умолчанию",
            "friendly_dm": "Дружелюбный Мастер",
            "hardcore_dm": "Хардкорный Мастер",
            "narrative_dm": "Повествовательный Мастер",
            "custom": "Пользовательский",
            "roll_dice_desc": "Бросок костей по стандартной нотации D&D",
            "dice_notation_desc": "Нотация костей (например, '2d6+3', '1d20', '3d8-2')",
            "advantage_desc": "Бросок с преимуществом (true) или помехой (false)",
            "execute_code_desc": "Выполнить код Python",
            "code_desc": "Код Python для выполнения",
            "query_db_desc": "Запрос к базе данных для получения информации о персонаже или кампании",
            "query_desc": "SQL-запрос для выполнения",
            "search_kb_desc": "Поиск в векторной базе данных для получения релевантной информации",
            "search_query_desc": "Поисковый запрос",
            "num_results_desc": "Количество результатов для возврата",
            "dice_roll": "Бросок Костей",
            "rolls": "Броски",
            "total": "Итого",
            "code_executed": "Код выполнен",
            "db_queried": "Запрос к базе данных выполнен",
            "kb_searched": "Поиск в базе знаний выполнен",
            "source": "Источник",
            "relevance": "Релевантность",
            "send_message": "Отправить",
            "clear_chat": "Очистить Чат",
            "campaign_saved": "Кампания сохранена!",
            "campaign_save_failed": "Не удалось сохранить кампанию",
            "document_name": "Название Документа",
            "document_status": "Статус",
            "document_actions": "Действия",
            "available_in_chat": "Доступен в Чате",
            "not_available_in_chat": "Недоступен в Чате",
            "delete_document": "Удалить",
            "document_deleted": "Документ удален!",
            "document_delete_failed": "Не удалось удалить документ",
            "document_loaded": "Документ загружен в чат!",
            "document_load_failed": "Не удалось загрузить документ в чат",
            "docs_usage_instructions": "Вы можете спрашивать ИИ о информации в загруженных документах. Попробуйте вопросы типа:",
            "docs_usage_example1": "- \"Что говорится в документе о главном злодее?\"",
            "docs_usage_example2": "- \"Расскажи о главном злодее из документа кампании\"",
            "docs_usage_example3": "- \"Опиши ключевые локации из загруженных документов\"",
            "docs_usage_footer": "ИИ будет искать информацию в ваших документах и предоставлять релевантные данные."
        }
        
        # Save default locales if they don't exist
        en_path = os.path.join(self.locales_dir, "en.json")
        if not os.path.exists(en_path):
            with open(en_path, 'w', encoding='utf-8') as f:
                json.dump(en_locale, f, indent=4, ensure_ascii=False)
            self.locales["en"] = en_locale
        
        ru_path = os.path.join(self.locales_dir, "ru.json")
        if not os.path.exists(ru_path):
            with open(ru_path, 'w', encoding='utf-8') as f:
                json.dump(ru_locale, f, indent=4, ensure_ascii=False)
            self.locales["ru"] = ru_locale
    
    def get_text(self, key: str, locale: str = None, default: str = "") -> str:
        """
        Get localized text for a key
        
        Args:
            key: Text key
            locale: Locale code (if None, use current locale)
            default: Default text if key not found
            
        Returns:
            Localized text
        """
        if locale is None:
            locale = self.get_current_locale()
        
        # Try to get text from specified locale
        if locale in self.locales and key in self.locales[locale]:
            return self.locales[locale][key]
        
        # Fall back to default locale
        if self.default_locale in self.locales and key in self.locales[self.default_locale]:
            return self.locales[self.default_locale][key]
        
        # Return default text if key not found
        return default
    
    def get_current_locale(self) -> str:
        """Get current locale code"""
        if "locale" in st.session_state:
            return st.session_state.locale
        return self.default_locale
    
    def set_locale(self, locale: str) -> None:
        """Set current locale"""
        if locale in self.locales:
            st.session_state.locale = locale
    
    def get_available_locales(self) -> Dict[str, str]:
        """
        Get available locales with their display names
        
        Returns:
            Dictionary of locale codes and display names
        """
        locale_names = {
            "en": "English",
            "ru": "Русский"
        }
        
        available = {}
        for locale in self.locales.keys():
            if locale in locale_names:
                available[locale] = locale_names[locale]
            else:
                available[locale] = locale.upper()
        
        return available 