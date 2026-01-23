import streamlit as st
import os
from typing import Dict, Any, List, Optional

from api.llm_factory import get_llm_client
from utils.config_manager import ConfigManager

def render_sidebar():
    """Render the sidebar with settings and character selection"""
    
    # Helper function for localized text
    def _(key, default=""):
        """Get localized text for a key"""
        return st.session_state.localization_manager.get_text(key, default=default)
    
    st.sidebar.title(_("app_title", "D&D LLM Game Assistant"))
    
    # Initialize config manager if not in session state
    if "config_manager" not in st.session_state:
        st.session_state.config_manager = ConfigManager()
    
    # LLM Settings
    st.sidebar.header(_("llm_settings", "LLM Settings"))
    
    # Единственный провайдер - OpenRouter
    provider = "OpenRouter"
    st.sidebar.info("🌐 OpenRouter (Gemini Flash)")
    
    # Model selection for OpenRouter
    model = st.selectbox(
        _("model", "Model"),
        ["google/gemini-2.5-flash-lite-preview-09-2025"],
        index=0,
        key="model_select"
    )
    st.caption(_("gemini_flash_lite_desc", "💰 Google's ultra-fast lightweight reasoning model (1M context, $0.10/$0.40 per 1M tokens) ⚙️"))
    
    # Temperature setting
    default_temp = st.session_state.config_manager.get_app_setting("default_temperature", 0.7)
    temperature = st.sidebar.slider(
        _("temperature", "Temperature"),
        min_value=0.0,
        max_value=1.0,
        value=default_temp,
        step=0.1,
        key="temperature_slider"
    )
    
    # System Prompt selection
    st.sidebar.subheader(_("system_prompt", "System Prompt"))
    
    # Get available prompts
    available_prompts = st.session_state.config_manager.get_available_prompts()
    active_prompt = st.session_state.config_manager.get_active_prompt_name()
    
    # Create display names for prompts
    prompt_display_names = {
        "default_en": _("default_en", "Default_EN"),
        "default_ru": _("default_ru", "Default_RU"),
        "custom": _("custom", "Custom")
    }
    
    # Create options list with display names
    prompt_options = []
    for prompt in available_prompts:
        display_name = prompt_display_names.get(prompt, prompt.capitalize())
        prompt_options.append({"name": prompt, "display": display_name})
    
    # Find index of active prompt
    active_index = 0
    for i, prompt in enumerate(prompt_options):
        if prompt["name"] == active_prompt:
            active_index = i
            break
    
    # Prompt selection dropdown
    selected_prompt = st.sidebar.selectbox(
        _("dm_style", "DM Style"),
        options=range(len(prompt_options)),
        format_func=lambda i: prompt_options[i]["display"],
        index=active_index,
        key="selected_prompt_index"
    )
    
    # Show current prompt content
    with st.sidebar.expander(_("edit_prompt", "View/Edit Prompt")):
        selected_prompt_name = prompt_options[selected_prompt]["name"]
        prompt_content = st.session_state.config_manager.get_system_prompt(selected_prompt_name)
        
        edited_prompt = st.text_area(
            _("edit_prompt", "Edit Prompt"),
            value=prompt_content,
            height=300,
            key=f"prompt_content_{selected_prompt_name}"
        )
        
        # Save button for prompt
        if st.button(_("save_prompt", "Save Prompt"), key="save_prompt_btn"):
            if st.session_state.config_manager.save_system_prompt(selected_prompt_name, edited_prompt):
                st.success(_("prompt_saved", "Prompt saved!"))
            else:
                st.error(_("prompt_save_failed", "Failed to save prompt"))
    
    # Set as active button
    if st.sidebar.button(_("set_active_style", "Set as Active DM Style"), key="set_active_prompt_btn"):
        if st.session_state.config_manager.set_active_prompt(prompt_options[selected_prompt]["name"]):
            st.sidebar.success(f"{prompt_options[selected_prompt]['display']} {_('style_activated', 'set as active DM style!')}")
        else:
            st.sidebar.error(_("style_activate_failed", "Failed to set active prompt"))
    
    # Apply LLM settings button
    if st.button(_("apply_settings", "Apply LLM Settings"), key="apply_settings"):
        # Update session state
        st.session_state.llm_provider = provider.lower()
        st.session_state.llm_model = model
        st.session_state.llm_temperature = temperature
        
        # Initialize new LLM client
        try:
            st.session_state.llm_client = get_llm_client(
                provider=st.session_state.llm_provider,
                model=st.session_state.llm_model
            )
            st.success(_("settings_applied", "Settings applied successfully!"))
            
            # Save settings to config
            st.session_state.config_manager.set_app_setting("default_provider", st.session_state.llm_provider)
            st.session_state.config_manager.set_app_setting("default_model", model)
            st.session_state.config_manager.set_app_setting("default_temperature", temperature)
            
            # Принудительно обновляем страницу для применения изменений
            st.rerun()
        except Exception as e:
            st.error(f"Error: {str(e)}")
    
    # Character Selection
    st.sidebar.header(_("select_character", "Character Selection"))
    
    # Get all characters from the database
    characters = st.session_state.sql_manager.get_all_characters()
    
    if characters:
        # Create a list of character names with IDs
        character_options = [f"{char['name']} (Level {char['level']} {char['race']} {char['class']})" for char in characters]
        character_ids = [char['id'] for char in characters]
        
        # Add a "None" option
        character_options.insert(0, _("none", "None"))
        character_ids.insert(0, None)
        
        # Get the index of the current character
        current_index = 0
        if st.session_state.current_character:
            try:
                current_id = st.session_state.current_character.get('id')
                if current_id in character_ids:
                    current_index = character_ids.index(current_id)
            except:
                pass
        
        # Character selection dropdown
        selected_index = st.sidebar.selectbox(
            _("select_character", "Select Character"),
            options=range(len(character_options)),
            format_func=lambda i: character_options[i],
            index=current_index,
            key="selected_character_index"
        )
        
        # Load the selected character
        if st.sidebar.button(_("load_character", "Load Character"), key="load_character_btn"):
            selected_id = character_ids[selected_index]
            if selected_id:
                st.session_state.current_character = st.session_state.sql_manager.get_character(selected_id)
                st.sidebar.success(f"{_('loaded_character', 'Loaded character')}: {st.session_state.current_character['name']}")
            else:
                st.session_state.current_character = None
                st.sidebar.info(_("no_character_selected", "No character selected"))
    else:
        st.sidebar.info(_("no_characters", "No characters found. Create a new character in the Character Sheet tab."))
    
    # Create New Character button
    create_character_clicked = st.sidebar.button(_("create_character", "Create New Character"), key="create_character_btn_sidebar")
    if create_character_clicked:
        st.session_state.current_character = None
        # Set a flag to show the character creation form
        st.session_state.show_character_creation = True
        # Force a rerun to show the character creation form immediately
        st.rerun()
    
    # Vector Database Management
    st.sidebar.header(_("knowledge_base", "Knowledge Base"))
    
    # Search the vector database
    search_query = st.sidebar.text_input(_("search_kb", "Search Knowledge Base"), key="kb_search")
    if st.sidebar.button(_("search_btn", "Search"), key="kb_search_btn") and search_query:
        # Используем улучшенный алгоритм поиска с параметром diversity_threshold
        results = st.session_state.vector_manager.search(search_query, k=5, diversity_threshold=0.7)
        
        if results:
            st.sidebar.subheader(_("search_results", "Search Results"))
            for i, result in enumerate(results):
                with st.sidebar.expander(f"{_('result', 'Result')} {i+1} - {result['metadata'].get('source', _('unknown', 'Unknown'))}"):
                    st.write(result['content'])
                    st.write(f"{_('relevance', 'Relevance')}: {result['relevance_score']:.2f}")
        else:
            st.sidebar.info(_("no_results", "No results found"))
    
    # About section
    st.sidebar.header(_("about", "About"))
    st.sidebar.info(
        _("about_text", "D&D LLM Game Assistant helps you play Dungeons & Dragons with AI. Upload campaign documents, manage characters, and interact with an AI Dungeon Master.")
    )
    
    # Version info
    st.sidebar.text(f"{_('version', 'Version')} 0.1.0")
