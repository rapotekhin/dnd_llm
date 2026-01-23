import streamlit as st
import json
import re
from typing import Dict, Any, List, Optional
import time
import traceback

from utils.code_executor import CodeExecutor
from utils.dice_roller import DiceRoller

def render_chat_interface():
    """Render the chat interface for interacting with the LLM"""
    
    # Helper function for localized text
    def _(key, default=""):
        """Get localized text for a key"""
        return st.session_state.localization_manager.get_text(key, default=default)
    
    st.header(_("game_session", "Game Session"))
    
    # Initialize messages if not already in session state
    if "messages" not in st.session_state:
        st.session_state.messages = []
    
    # Инициализируем флаг для обработки сообщений
    if "processing_message" not in st.session_state:
        st.session_state.processing_message = False
    
    # Инициализируем словарь для хранения ID трассировок Langfuse
    if "langfuse_traces" not in st.session_state:
        st.session_state.langfuse_traces = {}
    
    # Функция для очистки истории чата
    def clear_chat_history():
        st.session_state.messages = []
        st.session_state.langfuse_traces = {}
        st.rerun()
    
    # Функция для отправки обратной связи в Langfuse
    def send_feedback(trace_id, score):
        """Send feedback to Langfuse"""
        # Проверяем, что у нас есть ID трассировки
        if not trace_id:
            return
        
        # Проверяем, что клиент поддерживает Langfuse
        if hasattr(st.session_state.llm_client, 'langfuse_enabled') and st.session_state.llm_client.langfuse_enabled:
            try:
                # Для OpenAI клиента
                if hasattr(st.session_state.llm_client, 'langfuse_client'):
                    st.session_state.llm_client.langfuse_client.score(
                        trace_id=trace_id,
                        name="user_feedback",
                        value=score
                    )
                    st.success(_("feedback_sent", "Thank you for your feedback!"))
                    time.sleep(1)
                    st.rerun()
            except Exception as e:
                st.error(f"Error sending feedback: {str(e)}")
    
    # Добавляем кнопку для очистки истории чата
    col1, col2 = st.columns([5, 1])
    with col2:
        if st.button(_("clear_chat", "Clear Chat"), key="clear_chat_btn"):
            clear_chat_history()
    
    # Функция для обработки отправки сообщения
    def send_message():
        if st.session_state.chat_input and not st.session_state.processing_message:
            # Устанавливаем флаг обработки
            st.session_state.processing_message = True
            
            # Получаем текст сообщения
            prompt = st.session_state.chat_input
            
            # Добавляем сообщение пользователя в историю
            user_message = {"role": "user", "content": prompt}
            st.session_state.messages.append(user_message)
            
            # Генерируем ответ ассистента
            # Prepare system prompt
            system_prompt = create_system_prompt()
            
            # Prepare tools for function calling
            tools = [
                {
                    "type": "function",
                    "function": {
                        "name": "roll_dice",
                        "description": _("roll_dice_desc", "Roll dice using standard D&D notation"),
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "dice_notation": {
                                    "type": "string",
                                    "description": _("dice_notation_desc", "Dice notation (e.g., '2d6+3', '1d20', '3d8-2')")
                                },
                                "advantage": {
                                    "type": "boolean",
                                    "description": _("advantage_desc", "Whether to roll with advantage (roll twice and take the higher result)")
                                },
                                "disadvantage": {
                                    "type": "boolean",
                                    "description": _("disadvantage_desc", "Whether to roll with disadvantage (roll twice and take the lower result)")
                                }
                            },
                            "required": ["dice_notation"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "execute_python_code",
                        "description": _("execute_code_desc", "Execute Python code for game mechanics"),
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "code": {
                                    "type": "string",
                                    "description": _("code_desc", "Python code to execute")
                                }
                            },
                            "required": ["code"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "query_database",
                        "description": _("query_db_desc", "Query the SQL database for character, inventory, or NPC information"),
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "query": {
                                    "type": "string",
                                    "description": _("query_desc", "SQL query to execute")
                                }
                            },
                            "required": ["query"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "search_knowledge_base",
                        "description": _("search_kb_desc", "Search the vector database for relevant information"),
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "query": {
                                    "type": "string",
                                    "description": _("search_query_desc", "Search query")
                                },
                                "num_results": {
                                    "type": "integer",
                                    "description": _("num_results_desc", "Number of results to return")
                                }
                            },
                            "required": ["query"]
                        }
                    }
                }
            ]
            
            # Get chat history for context (limit to last 10 messages)
            chat_history = [{"role": msg["role"], "content": msg["content"]} 
                           for msg in st.session_state.messages[-10:]]
            
            # Generate response with function calling
            response = st.session_state.llm_client.generate_with_tools(
                messages=chat_history,
                tools=tools,
                system_prompt=system_prompt,
                temperature=st.session_state.llm_temperature
            )
            
            # Process the response
            content = response.get("content", "")
            tool_calls = response.get("tool_calls", [])
            
            # Проверяем, не содержит ли ответ сообщение об ошибке
            if content is not None and ("ошибка при обращении к API" in content or "error" in content.lower()):
                # Если это сообщение об ошибке, не обрабатываем инструменты
                formatted_content = content
                dice_results = None
                code_results = None
                db_results = None
                kb_results = None
            else:
                # Handle tool calls
                dice_results = None
                code_results = None
                db_results = None
                kb_results = None
            
            if tool_calls:
                for tool_call in tool_calls:
                    # Проверяем формат tool_call (словарь или объект)
                    if isinstance(tool_call, dict):
                        # Формат словаря (как возвращает llm_factory.py)
                        function_name = tool_call["function"]["name"]
                        function_args = json.loads(tool_call["function"]["arguments"])
                    else:
                        # Формат объекта (как возвращает OpenAI API напрямую)
                        function_name = tool_call.function.name
                        function_args = json.loads(tool_call.function.arguments)
                    
                    if function_name == "roll_dice":
                        dice_results = process_dice_roll(function_args)
                        if content is None:
                            content = ""
                        content += f"\n\n**{_('dice_roll', 'Dice Roll')}: {function_args.get('dice_notation')}**"
                        if dice_results and dice_results.get("success", False):
                            rolls_str = ", ".join(str(r) for r in dice_results.get("rolls", []))
                            content += f"\n**{_('rolls', 'Rolls')}: [{rolls_str}], {_('total', 'Total')}: {dice_results.get('total')}**"
                    
                    elif function_name == "execute_python_code":
                        code_results = process_code_execution(function_args)
                        if content is None:
                            content = ""
                        content += f"\n\n**{_('code_executed', 'Code executed')}**"
                        if code_results and code_results.get("output"):
                            content += f"\n```\n{code_results.get('output')}\n```"
                    
                    elif function_name == "query_database":
                        db_results = process_db_query(function_args)
                        if content is None:
                            content = ""
                        content += f"\n\n**{_('db_queried', 'Database queried')}**"
                    
                    elif function_name == "search_knowledge_base":
                        kb_results = process_kb_search(function_args)
                        if content is None:
                            content = ""
                        content += f"\n\n**{_('kb_searched', 'Knowledge base searched')}**"
                        
                        # Добавляем результаты поиска в контент
                        if kb_results and kb_results.get("success", False) and kb_results.get("results"):
                            content += f"\n\n**{_('search_results', 'Search Results')}:**"
                            for i, result in enumerate(kb_results["results"]):
                                content += f"\n\n**{_('result', 'Result')} {i+1}** ({_('source', 'Source')}: {result.get('source', _('unknown', 'Unknown'))}, {_('relevance', 'Relevance')}: {result.get('relevance', '0.00')})\n"
                                content += f"```\n{result.get('content', '')}\n```"
            
            # Улучшаем форматирование Markdown для лучшей читаемости
            formatted_content = improve_markdown_formatting(content)
            
            # Add assistant message to chat history
            assistant_message = {
                "role": "assistant", 
                "content": formatted_content
            }
            
            # Add tool results if any
            if dice_results:
                assistant_message["dice_results"] = dice_results
            if code_results:
                assistant_message["code_results"] = code_results
            if db_results:
                assistant_message["db_results"] = db_results
            if kb_results:
                assistant_message["kb_results"] = kb_results
            
            # Добавляем сообщение в историю
            st.session_state.messages.append(assistant_message)
            
            # Сохраняем ID трассировки Langfuse, если он есть
            if hasattr(st.session_state.llm_client, 'last_trace_id') and st.session_state.llm_client.last_trace_id:
                st.session_state.langfuse_traces[len(st.session_state.messages) - 1] = st.session_state.llm_client.last_trace_id
            
            # Сбрасываем флаг обработки
            st.session_state.processing_message = False
            
            # Перезагружаем страницу, чтобы отобразить новые сообщения
            st.rerun()
    
    # Отображаем все существующие сообщения
    for i, message in enumerate(st.session_state.messages):
        with st.chat_message(message["role"]):
            st.markdown(message["content"])
            
            # Display dice roll results if any
            if "dice_results" in message:
                with st.expander(_("dice_results", "Dice Roll Results")):
                    st.json(message["dice_results"])
            
            # Display code execution results if any
            if "code_results" in message:
                with st.expander(_("code_results", "Code Execution Results")):
                    st.code(message["code_results"].get("output", ""))
                    if message["code_results"].get("result") is not None:
                        st.write(_("result", "Result:"), message["code_results"].get("result"))
                    if not message["code_results"].get("success", True):
                        st.error(message["code_results"].get("error", _("unknown_error", "Unknown error")))
            
            # Добавляем кнопки обратной связи для сообщений ассистента
            if message["role"] == "assistant" and i in st.session_state.langfuse_traces:
                trace_id = st.session_state.langfuse_traces[i]
                col1, col2, col3, col4 = st.columns([1, 1, 1, 3])
                with col1:
                    if st.button("👍", key=f"thumbs_up_{i}"):
                        send_feedback(trace_id, 1.0)
                with col2:
                    if st.button("👎", key=f"thumbs_down_{i}"):
                        send_feedback(trace_id, 0.0)
                with col3:
                    if st.button("😐", key=f"neutral_{i}"):
                        send_feedback(trace_id, 0.5)
    
    # Поле ввода для пользователя (используем st.chat_input)
    st.chat_input(
        _("chat_placeholder", "What would you like to do?"),
        key="chat_input",
        on_submit=send_message
    )

def improve_markdown_formatting(content: str) -> str:
    """
    Улучшает форматирование Markdown для лучшей читаемости
    
    Args:
        content: Исходный контент от LLM
        
    Returns:
        Улучшенный Markdown-контент
    """
    # Проверяем, что content не None
    if content is None:
        return ""
        
    # Helper function for localized text
    def _(key, default=""):
        """Get localized text for a key"""
        return st.session_state.localization_manager.get_text(key, default=default)
    
    # Форматируем заголовки для персонажа, заклинаний, инвентаря
    if "Ваш персонаж:" in content or "Персонаж:" in content or "Your character:" in content or "Character:" in content:
        content = content.replace("Ваш персонаж:", f"## {_('character', 'Character')}")
        content = content.replace("Персонаж:", f"## {_('character', 'Character')}")
        content = content.replace("Your character:", f"## {_('character', 'Character')}")
        content = content.replace("Character:", f"## {_('character', 'Character')}")
    
    if "Заклинания:" in content or "Spells:" in content:
        content = content.replace("Заклинания:", f"### {_('spells', 'Spells')}")
        content = content.replace("Spells:", f"### {_('spells', 'Spells')}")
    
    if "Инвентарь:" in content or "Inventory:" in content:
        content = content.replace("Инвентарь:", f"### {_('inventory', 'Inventory')}")
        content = content.replace("Inventory:", f"### {_('inventory', 'Inventory')}")
    
    # Форматируем описание локации
    location_match = re.search(r'(Вы находитесь|Местоположение:|Локация:|You are in|Location:)(.*?)(?=\n\n|$)', content, re.DOTALL)
    if location_match:
        location_text = location_match.group(2)
        content = content.replace(location_match.group(0), f"## {_('location', 'Location')}\n*{location_text.strip()}*")
    
    # Форматируем варианты действий
    if "{" in content and "}" in content:
        # Добавляем заголовок для вариантов действий
        content += f"\n\n### {_('action_options', 'Action Options')}"
        
        # Заменяем фигурные скобки на маркеры списка
        content = re.sub(r'{(\d+)\.\s*([^{}]*)}', r'\n* **\1.** \2', content)
    
    # Улучшаем форматирование списков
    content = re.sub(r'(?<!\n)\n- ', r'\n\n- ', content)
    
    # Выделяем диалоги NPC
    content = re.sub(r'"([^"]*)"', r'> "*\1*"', content)
    
    return content

def create_system_prompt() -> str:
    """Create a system prompt based on the current game state and character"""
    
    # Helper function for localized text
    def _(key, default=""):
        """Get localized text for a key"""
        return st.session_state.localization_manager.get_text(key, default=default)
    
    # Get the base system prompt from config manager
    base_prompt = st.session_state.config_manager.get_system_prompt()
    
    # Add game state information
    game_state_info = ""
    if st.session_state.game_state:
        game_state = st.session_state.game_state
        if game_state.get("campaign_name"):
            game_state_info += f"\n{_('campaign', 'Campaign')}: {game_state.get('campaign_name')}"
        if game_state.get("current_location"):
            game_state_info += f"\n{_('current_location', 'Current Location')}: {game_state.get('current_location')}"
        if game_state.get("active_quest"):
            game_state_info += f"\n{_('active_quest', 'Active Quest')}: {game_state.get('active_quest')}"
    
    # Add character information
    character_info = ""
    if st.session_state.current_character:
        char = st.session_state.current_character
        character_info += f"\n\n{_('active_character', 'Active Character')}: {char.get('name')}, {_('level', 'Level')} {char.get('level')} {char.get('race')} {char.get('class')}"
        
        # Add attributes
        if 'attributes' in char:
            attrs = char['attributes']
            character_info += f"\n{_('attributes', 'Attributes')}: {_('strength', 'STR')} {attrs.get('strength', 10)}, {_('dexterity', 'DEX')} {attrs.get('dexterity', 10)}, {_('constitution', 'CON')} {attrs.get('constitution', 10)}, {_('intelligence', 'INT')} {attrs.get('intelligence', 10)}, {_('wisdom', 'WIS')} {attrs.get('wisdom', 10)}, {_('charisma', 'CHA')} {attrs.get('charisma', 10)}"
        
        # Add inventory summary
        if 'inventory' in char and char['inventory']:
            inventory_items = [f"{item.get('quantity')}x {item.get('item_name')}" for item in char['inventory']]
            character_info += f"\n{_('inventory', 'Inventory')}: {', '.join(inventory_items)}"
    
    # Combine all parts
    full_prompt = base_prompt
    
    # if game_state_info:
    #     full_prompt += f"\n\n--- {_('game_state', 'GAME STATE')} ---" + game_state_info
    
    if character_info:
        full_prompt += f"\n\n--- {_('character_info', 'CHARACTER INFO')} ---" + character_info
    
    # # Добавляем инструкцию по форматированию
    # full_prompt += f"\n\n--- {_('formatting', 'FORMATTING')} ---\n{_('formatting_instructions', 'Please use Markdown formatting in your responses to make them more readable. Use headers (## for main headers, ### for subheaders), lists (- for bullet points), emphasis (*italic* or **bold**), and blockquotes (> for NPC dialogue). Format character stats, inventory, and location descriptions clearly.')}"
    
    # Добавляем инструкцию по языку
    current_locale = st.session_state.localization_manager.get_current_locale()
    if current_locale == "ru":
        full_prompt += "\n\nПожалуйста, отвечайте на русском языке."
    else:
        full_prompt += "\n\nPlease respond in English."
    
    return full_prompt

def process_dice_roll(args: Dict[str, Any]) -> Dict[str, Any]:
    """Process a dice roll function call"""
    
    dice_notation = args.get("dice_notation", "1d20")
    advantage = args.get("advantage", False)
    disadvantage = args.get("disadvantage", False)
    
    if advantage or disadvantage:
        return DiceRoller.roll_with_advantage(disadvantage)
    else:
        return DiceRoller.roll_dice(dice_notation)

def process_code_execution(args: Dict[str, Any]) -> Dict[str, Any]:
    """Process a code execution function call"""
    
    code = args.get("code", "")
    
    # Add imports and context
    code_with_context = f"""
# D&D Game Code
from utils.dice_roller import DiceRoller

{code}
"""
    
    return CodeExecutor.execute_code(code_with_context)

def process_db_query(args: Dict[str, Any]) -> Dict[str, Any]:
    """Process a database query function call"""
    
    query = args.get("query", "")
    
    # Sanitize the query to prevent SQL injection
    # This is a simple check, but the execute_query method should have more robust protection
    if re.search(r"(DROP|DELETE|UPDATE|INSERT|ALTER|CREATE)\s+", query, re.IGNORECASE):
        return {
            "success": False,
            "error": "Only SELECT queries are allowed",
            "results": []
        }
    
    try:
        results = st.session_state.sql_manager.execute_query(query)
        return {
            "success": True,
            "results": results
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e),
            "results": []
        }

def process_kb_search(args: Dict[str, Any]) -> Dict[str, Any]:
    """Process a knowledge base search function call"""
    
    query = args.get("query", "")
    num_results = args.get("num_results", 3)
    
    if not query:
        return {
            "success": False,
            "error": "Empty search query",
            "results": []
        }
    
    try:
        # Добавляем параметр diversity_threshold для обеспечения разнообразия результатов
        results = st.session_state.vector_manager.search(query, k=num_results, diversity_threshold=0.7)
        
        # Форматируем результаты для отображения в чате
        formatted_results = []
        for result in results:
            # Добавляем только уникальные результаты
            if not any(r.get("content") == result["content"] for r in formatted_results):
                formatted_results.append({
                    "content": result["content"],
                    "source": result["metadata"].get("source", "Unknown"),
                    "relevance": f"{result['relevance_score']:.2f}"
                })
        
        return {
            "success": True,
            "results": formatted_results
        }
    except Exception as e:
        print(f"Error in knowledge base search: {str(e)}")
        traceback.print_exc()
        return {
            "success": False,
            "error": str(e),
            "results": []
        } 