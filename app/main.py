import streamlit as st
import os
import uuid
import time
import traceback
import gzip
import json
from dotenv import load_dotenv

# Import our custom modules
from components.sidebar import render_sidebar
from components.chat_interface import render_chat_interface
from components.character_sheet import render_character_sheet
from api.llm_factory import get_llm_client, OpenRouterClient
from database.sql_manager import SQLDatabaseManager
from database.vector_manager import VectorDatabaseManager
from utils.config_manager import ConfigManager
from utils.campaign_manager import CampaignManager
from utils.localization import LocalizationManager

# Load environment variables
load_dotenv()

# Set page configuration
st.set_page_config(
    page_title="D&D LLM Game Assistant",
    page_icon="🐉",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Initialize localization manager
if "localization_manager" not in st.session_state:
    st.session_state.localization_manager = LocalizationManager()

# Helper function for localized text
def _(key, default="", **kwargs):
    """Get localized text for a key"""
    return st.session_state.localization_manager.get_text(key, default=default)

# Определение функции load_campaign_documents перед её использованием
def load_campaign_documents():
    """Load campaign documents from storage into vector database"""
    try:
        # Get all documents
        documents = st.session_state.campaign_manager.load_documents()
        
        # Check if documents need to be loaded into vector database
        for doc_id, doc_info in documents.items():
            # Check if document is already in vector database by checking metadata
            # This is a simple check and might need to be improved
            if not doc_info.get("loaded_in_vector_db", False):
                # Document path should be stored in the document info
                doc_path = doc_info.get("file_path")
                if doc_path and os.path.exists(doc_path):
                    try:
                        # Load the document
                        with open(doc_path, 'rb') as f:
                            # Create a file-like object that Streamlit's uploader would return
                            class UploadedFile:
                                def __init__(self, file, name):
                                    self.file = file
                                    self.name = name
                                    
                                def getvalue(self):
                                    return self.file.read()
                            
                            file_content = f.read()
                            uploaded_file = UploadedFile(open(doc_path, 'rb'), os.path.basename(doc_path))
                            
                            # Add to vector database
                            metadata = {
                                "source": doc_info.get("name", os.path.basename(doc_path)),
                                "campaign_name": doc_info.get("campaign_name", "Unknown"),
                                "document_id": doc_id
                            }
                            
                            success = st.session_state.vector_manager.add_document(uploaded_file, metadata)
                            
                            if success:
                                # Update document info to mark as loaded
                                doc_info["loaded_in_vector_db"] = True
                                st.session_state.campaign_manager.save_document_info(doc_info)
                                print(f"Loaded document {doc_info.get('name')} into vector database")
                            else:
                                print(f"Failed to add document {doc_info.get('name')} to vector database")
                    except Exception as e:
                        print(f"Error processing document {doc_info.get('name')}: {e}")
                        traceback.print_exc()
    except Exception as e:
        print(f"Error loading campaign documents: {e}")
        traceback.print_exc()

# Initialize session state
if "messages" not in st.session_state:
    st.session_state.messages = []

if "current_character" not in st.session_state:
    st.session_state.current_character = None

if "config_manager" not in st.session_state:
    # Initialize configuration manager
    st.session_state.config_manager = ConfigManager()

if "campaign_manager" not in st.session_state:
    # Initialize campaign manager
    st.session_state.campaign_manager = CampaignManager()

if "game_state" not in st.session_state:
    # Try to load the last campaign state
    campaigns = st.session_state.campaign_manager.load_campaigns()
    if campaigns:
        # Get the last campaign (assuming the most recently used one)
        last_campaign_name = list(campaigns.keys())[-1]
        st.session_state.game_state = campaigns[last_campaign_name]
    else:
        # Create a new default game state
        st.session_state.game_state = {
            "campaign_name": "New Campaign",
            "dm_notes": "",
            "current_location": "",
            "active_quest": ""
        }

if "llm_client" not in st.session_state:
    # Get default settings from config (OpenRouter only)
    default_model = st.session_state.config_manager.get_app_setting("default_model", "google/gemini-2.5-flash-lite-preview-09-2025")
    
    # Store in session state
    st.session_state.llm_provider = "openrouter"
    st.session_state.llm_model = default_model
    
    # Initialize client
    try:
        st.session_state.llm_client = get_llm_client(
            provider=st.session_state.llm_provider,
            model=st.session_state.llm_model
        )
    except Exception as e:
        st.error(f"Error initializing LLM client: {str(e)}")
        st.session_state.llm_client = None

if "llm_temperature" not in st.session_state:
    # Set default temperature from config
    st.session_state.llm_temperature = st.session_state.config_manager.get_app_setting("default_temperature", 0.7)

if "sql_manager" not in st.session_state:
    # Initialize SQL database manager
    db_path = os.getenv("SQLITE_DB_PATH", "./data/dnd_game.db")
    st.session_state.sql_manager = SQLDatabaseManager(db_path)

if "vector_manager" not in st.session_state:
    # Initialize Vector database manager
    vector_db_path = os.getenv("VECTOR_DB_PATH", "./data/vector_db")
    st.session_state.vector_manager = VectorDatabaseManager(vector_db_path)
    
    # Теперь вызываем функцию после её определения
    load_campaign_documents()

def save_chat_history(campaign_name):
    """Save chat history to a compressed file"""
    if "messages" in st.session_state:
        chat_history = st.session_state.messages
        file_path = os.path.join("data", "chat_histories", f"{campaign_name}.gz")
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        with gzip.open(file_path, 'wt', encoding='utf-8') as f:
            json.dump(chat_history, f)
        st.success(_("chat_saved", "Chat history saved successfully!"))


def load_chat_history(campaign_name):
    """Load chat history from a compressed file"""
    file_path = os.path.join("data", "chat_histories", f"{campaign_name}.gz")
    if os.path.exists(file_path):
        with gzip.open(file_path, 'rt', encoding='utf-8') as f:
            st.session_state.messages = json.load(f)
        st.success(_("chat_loaded", "Chat history loaded successfully!"))
    else:
        st.info(_("no_chat_history", "No chat history found for this campaign."))

def main():
    # Add language selector to the top right
    col1, col2 = st.columns([9, 1])
    with col2:
        available_locales = st.session_state.localization_manager.get_available_locales()
        locale_options = list(available_locales.values())
        locale_keys = list(available_locales.keys())
        
        current_locale = st.session_state.localization_manager.get_current_locale()
        current_index = locale_keys.index(current_locale) if current_locale in locale_keys else 0
        
        selected_locale_name = st.selectbox(
            "Language",
            options=locale_options,
            index=current_index,
            key="locale_selector"
        )
        
        # Update locale if changed
        selected_index = locale_options.index(selected_locale_name)
        selected_locale = locale_keys[selected_index]
        
        if selected_locale != current_locale:
            st.session_state.localization_manager.set_locale(selected_locale)
            st.rerun()
    
    # Инициализация LLM клиента, если он отсутствует
    if "llm_client" not in st.session_state:
        # Get default settings from config (OpenRouter only)
        default_model = st.session_state.config_manager.get_app_setting("default_model", "google/gemini-2.5-flash-lite-preview-09-2025")
        
        # Store in session state
        st.session_state.llm_provider = "openrouter"
        st.session_state.llm_model = default_model
        
        # Initialize client
        try:
            st.session_state.llm_client = get_llm_client(
                provider=st.session_state.llm_provider,
                model=st.session_state.llm_model
            )
        except Exception as e:
            st.error(f"Error initializing LLM client: {str(e)}")
            st.session_state.llm_client = None
    
    # Render the sidebar
    render_sidebar()
    
    # Main content area with tabs
    tab1, tab2, tab3 = st.tabs([
        _("game_tab", "Game"), 
        _("character_tab", "Character Sheet"), 
        _("campaign_tab", "Campaign")
    ])
    
    with tab1:
        render_chat_interface()
    
    with tab2:
        render_character_sheet()
    
    with tab3:
        render_campaign_tab()

def render_campaign_tab():
    """Render the campaign tab"""
    st.header(_("campaign_info", "Campaign Information"))
    
    # Campaign name with save button
    col1, col2, col3 = st.columns([3, 1, 1])
    with col1:
        st.text_input(_("campaign_name", "Campaign Name"), value=st.session_state.game_state.get("campaign_name", ""), 
                    key="campaign_name", on_change=update_game_state)
    with col2:
        if st.button(_("save_campaign", "Save Campaign"), key="save_campaign_btn"):
            if st.session_state.campaign_manager.save_campaign_state(st.session_state.game_state):
                st.success(_("success_save", "Saved successfully!"))
            else:
                st.error(_("error_save", "Failed to save"))
    with col3:
        if st.button(_("save_chat", "Save Chat History"), key="save_chat_btn"):
            save_chat_history(st.session_state.game_state.get("campaign_name", ""))
    
    # Load chat history when loading a campaign
    load_chat_history(st.session_state.game_state.get("campaign_name", ""))
    
    # Campaign details
    st.text_area(_("dm_notes", "DM Notes"), value=st.session_state.game_state.get("dm_notes", ""), 
                key="dm_notes", height=200, on_change=update_game_state)
    st.text_input(_("current_location", "Current Location"), value=st.session_state.game_state.get("current_location", ""), 
                key="current_location", on_change=update_game_state)
    st.text_input(_("active_quest", "Active Quest"), value=st.session_state.game_state.get("active_quest", ""), 
                key="active_quest", on_change=update_game_state)
    
    # Campaign Documents section
    st.subheader(_("campaign_docs", "Campaign Documents"))
    
    # Display existing documents
    documents = st.session_state.campaign_manager.get_campaign_documents(
        st.session_state.game_state.get("campaign_name", "")
    )
    
    if documents:
        st.write("Uploaded Documents:")
        for doc in documents:
            col1, col2, col3 = st.columns([3, 1, 1])
            with col1:
                st.write(f"📄 {doc.get('name', 'Unknown')} ({doc.get('type', 'Unknown')})")
                # Показываем статус загрузки в векторную базу
                if doc.get("loaded_in_vector_db", False):
                    st.success(_("doc_available", "Available in chat"), icon="✅")
                else:
                    st.error(_("doc_unavailable", "Not available in chat"), icon="❌")
            with col2:
                # Добавляем кнопку для повторной загрузки в векторную базу
                if not doc.get("loaded_in_vector_db", False):
                    if st.button(_("load_to_chat", "Load to Chat"), key=f"load_{doc.get('id')}", help="Load this document to vector database for chat"):
                        try:
                            doc_path = doc.get("file_path")
                            if doc_path and os.path.exists(doc_path):
                                with open(doc_path, 'rb') as f:
                                    class UploadedFile:
                                        def __init__(self, file, name):
                                            self.file = file
                                            self.name = name
                                        
                                        def getvalue(self):
                                            return self.file.read()
                                    
                                    uploaded_file = UploadedFile(open(doc_path, 'rb'), os.path.basename(doc_path))
                                    
                                    metadata = {
                                        "source": doc.get("name", os.path.basename(doc_path)),
                                        "campaign_name": doc.get("campaign_name", "Unknown"),
                                        "document_id": doc.get("id")
                                    }
                                    
                                    success = st.session_state.vector_manager.add_document(uploaded_file, metadata)
                                    
                                    if success:
                                        # Update document info to mark as loaded
                                        doc["loaded_in_vector_db"] = True
                                        st.session_state.campaign_manager.save_document_info(doc)
                                        st.success(f"{_('doc_added', 'Document loaded to chat!')}")
                                        st.rerun()
                                    else:
                                        st.error(f"{_('doc_save_failed', 'Failed to load document to chat. Check console for details.')}")
                        except Exception as e:
                            st.error(f"Error: {str(e)}")
                            traceback.print_exc()
            with col3:
                if st.button(_("delete_btn", "Delete"), key=f"delete_{doc.get('id')}", help="Delete this document"):
                    # Delete from campaign manager
                    if st.session_state.campaign_manager.delete_document(doc.get('id')):
                        # Also delete from vector database if possible
                        if doc.get("loaded_in_vector_db", False):
                            st.session_state.vector_manager.delete_by_metadata("document_id", doc.get('id'))
                        st.success(_("doc_delete_success", "Document deleted"))
                        st.rerun()
                    else:
                        st.error(_("doc_delete_failed", "Failed to delete document"))
    else:
        st.info(_("no_docs", "No documents uploaded for this campaign yet"))
    
    # Upload new document
    uploaded_file = st.file_uploader(_("upload_doc", "Upload campaign document"), type=["pdf", "txt", "md"], key="campaign_doc_uploader")
    if uploaded_file is not None:
        # Save the file to disk
        save_path = os.path.join("data", "documents", uploaded_file.name)
        os.makedirs(os.path.dirname(save_path), exist_ok=True)
        
        with open(save_path, "wb") as f:
            f.write(uploaded_file.getvalue())
        
        # Create document info
        doc_info = {
            "id": str(uuid.uuid4()),
            "name": uploaded_file.name,
            "type": uploaded_file.name.split(".")[-1],
            "file_path": save_path,
            "campaign_name": st.session_state.game_state.get("campaign_name", ""),
            "uploaded_at": str(time.time()),
            "loaded_in_vector_db": False
        }
        
        # Save document info
        if st.session_state.campaign_manager.save_document_info(doc_info):
            # Add to vector database
            try:
                metadata = {
                    "source": uploaded_file.name,
                    "campaign_name": st.session_state.game_state.get("campaign_name", ""),
                    "document_id": doc_info["id"]
                }
                
                success = st.session_state.vector_manager.add_document(uploaded_file, metadata)
                
                if success:
                    # Update document info to mark as loaded
                    doc_info["loaded_in_vector_db"] = True
                    st.session_state.campaign_manager.save_document_info(doc_info)
                    st.success(_("doc_added", "Document added to the campaign and available in chat!"))
                else:
                    st.warning(_("doc_save_failed", "Document saved but failed to add to vector database. You can try to load it to chat later."))
            except Exception as e:
                st.warning(f"{_('doc_save_failed', 'Document saved but failed to add to vector database')}: {str(e)}")
                traceback.print_exc()
        else:
            st.error(_("error_save", "Failed to save document information"))
    
    # Добавляем инструкции по использованию документов в чате
    with st.expander(_("how_to_use_docs", "How to use documents in chat")):
        st.markdown(f"""
        ### {_("docs_usage_title", "Using Campaign Documents in Chat")}
        
        {_("docs_usage_step1", "1. Upload your campaign documents (PDF, TXT, MD) using the uploader above")}
        {_("docs_usage_step2", "2. Make sure they are loaded to chat (green checkmark)")}
        {_("docs_usage_step3", "3. In the chat, you can ask questions about the documents")}
        
        **{_("docs_usage_examples", "Example questions")}:**
        {_("docs_usage_example1", '- "What does the rulebook say about spellcasting?"')}
        {_("docs_usage_example2", '- "Tell me about the main villain in the campaign document"')}
        {_("docs_usage_example3", '- "Summarize the key locations in the uploaded documents"')}
        
        {_("docs_usage_footer", "The AI will search through your documents and provide relevant information.")}
        """)

def update_game_state():
    """Update game state from session state"""
    st.session_state.game_state["campaign_name"] = st.session_state.campaign_name
    st.session_state.game_state["dm_notes"] = st.session_state.dm_notes
    st.session_state.game_state["current_location"] = st.session_state.current_location
    st.session_state.game_state["active_quest"] = st.session_state.active_quest
    
    # Auto-save game state
    st.session_state.campaign_manager.save_campaign_state(st.session_state.game_state)

if __name__ == "__main__":
    main() 