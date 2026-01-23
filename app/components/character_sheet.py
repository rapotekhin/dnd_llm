import streamlit as st
from typing import Dict, Any, List, Optional
import json
from datetime import datetime

from utils.dice_roller import DiceRoller

def render_character_sheet():
    """Render the character sheet interface"""
    
    # Get localization function
    _ = lambda key, default="", **kwargs: st.session_state.localization_manager.get_text(key, default, **kwargs)
    
    st.header(_("character.header", "Character Sheet"))
    
    # Check if we should show the character creation form
    if "show_character_creation" in st.session_state and st.session_state.show_character_creation:
        render_character_creation_form()
        return
    
    # Check if a character is loaded
    if not st.session_state.current_character:
        st.info(_("character.no_character", "No character loaded. Select a character from the sidebar or create a new one."))
        if st.button(_("character.create_new", "Create New Character"), key="create_character_btn_main"):
            st.session_state.show_character_creation = True
            st.rerun()
        return
    
    # Get the current character
    character = st.session_state.current_character
    
    # Character tabs
    tab1, tab2, tab3, tab4 = st.tabs([
        _("character.basic_info", "Basic Info"), 
        _("character.attributes_skills", "Attributes & Skills"), 
        _("character.inventory", "Inventory"), 
        _("character.notes", "Notes")
    ])
    
    with tab1:
        render_basic_info(character)
    
    with tab2:
        render_attributes_and_skills(character)
    
    with tab3:
        render_inventory(character)
    
    with tab4:
        render_notes(character)
    
    # Save changes button
    if st.button(_("character.save_changes", "Save Changes"), key="save_character_changes_btn"):
        save_character_changes(character)

def render_character_creation_form():
    """Render form for creating a new character"""
    
    # Helper function for localized text
    def _(key, default=""):
        """Get localized text for a key"""
        return st.session_state.localization_manager.get_text(key, default=default)
    
    st.subheader(_("character_creation.header", "Create New Character"))
    
    with st.form("character_creation_form"):
        col1, col2 = st.columns(2)
        
        with col1:
            name = st.text_input(_("character_name", "Character Name"))
            race = st.selectbox(_("race", "Race"), ["Human", "Elf", "Dwarf", "Halfling", "Gnome", "Half-Elf", "Half-Orc", "Tiefling", "Dragonborn"])
            
        with col2:
            character_class = st.selectbox(_("class", "Class"), ["Fighter", "Wizard", "Cleric", "Rogue", "Ranger", "Paladin", "Barbarian", "Bard", "Druid", "Monk", "Sorcerer", "Warlock"])
            level = st.number_input(_("level", "Level"), min_value=1, max_value=20, value=1, key="create_level")
        
        # Attributes
        st.subheader(_("attributes", "Attributes"))
        col1, col2, col3 = st.columns(3)
        
        with col1:
            strength = st.number_input(_("strength", "Strength"), min_value=3, max_value=20, value=10, key="create_strength")
            dexterity = st.number_input(_("dexterity", "Dexterity"), min_value=3, max_value=20, value=10, key="create_dexterity")
        
        with col2:
            constitution = st.number_input(_("constitution", "Constitution"), min_value=3, max_value=20, value=10, key="create_constitution")
            intelligence = st.number_input(_("intelligence", "Intelligence"), min_value=3, max_value=20, value=10, key="create_intelligence")
        
        with col3:
            wisdom = st.number_input(_("wisdom", "Wisdom"), min_value=3, max_value=20, value=10, key="create_wisdom")
            charisma = st.number_input(_("charisma", "Charisma"), min_value=3, max_value=20, value=10, key="create_charisma")
        
        # Background and description
        st.subheader(_("background", "Background"))
        background = st.text_area(_("background", "Character Background"), key="create_background")
        description = st.text_area(_("description", "Character Description"), key="create_description")
        
        # Submit button
        submitted = st.form_submit_button(_("create_button", "Create Character"))
        
        if submitted:
            if not name:
                st.error(_("error_name_required", "Character name is required"))
                return
            
            # Build character data
            character_data = {
                "name": name,
                "race": race,
                "class": character_class,
                "level": level,
                "attributes": {
                    "strength": strength,
                    "dexterity": dexterity,
                    "constitution": constitution,
                    "intelligence": intelligence,
                    "wisdom": wisdom,
                    "charisma": charisma
                },
                "skills": {
                    # Default skills based on D&D 5e
                    "acrobatics": 0,
                    "animal_handling": 0,
                    "arcana": 0,
                    "athletics": 0,
                    "deception": 0,
                    "history": 0,
                    "insight": 0,
                    "intimidation": 0,
                    "investigation": 0,
                    "medicine": 0,
                    "nature": 0,
                    "perception": 0,
                    "performance": 0,
                    "persuasion": 0,
                    "religion": 0,
                    "sleight_of_hand": 0,
                    "stealth": 0,
                    "survival": 0
                },
                "background": background,
                "description": description,
                "inventory": [],
                "notes": "",
                "campaign_id": st.session_state.get("active_campaign", "default"),
                "created_at": datetime.now().isoformat()
            }
            
            # Save character to database
            try:
                character_id = st.session_state.sql_manager.create_character(character_data)
                
                if character_id:
                    # Update session state
                    st.session_state.active_character = character_id
                    st.session_state.show_character_creation = False
                    success_message = _("success", "Character created successfully!")
                    st.success(f"Character '{name}' created successfully!")
                    st.rerun()
                else:
                    st.error(_("error", "Failed to create character. Please try again."))
                    print("Error creating character: No character ID returned")
            except Exception as e:
                st.error(_("error", "Failed to create character. Please try again."))
                print(f"Error creating character: {e}")

def render_basic_info(character: Dict[str, Any]):
    """Render the basic info section of the character sheet"""
    
    # Helper function for localized text
    def _(key, default=""):
        """Get localized text for a key"""
        return st.session_state.localization_manager.get_text(key, default=default)
    
    with st.expander(_("character_info", "Basic Information"), expanded=True):
        col1, col2, col3 = st.columns(3)
        with col1:
            st.text_input(_("character_name", "Character Name"), value=character.get("name", ""), key="char_name")
            st.selectbox(_("race", "Race"), ["Human", "Elf", "Dwarf", "Halfling", "Gnome", "Half-Elf", "Half-Orc", "Tiefling", "Dragonborn"],
                         index=["Human", "Elf", "Dwarf", "Halfling", "Gnome", "Half-Elf", "Half-Orc", "Tiefling", "Dragonborn"].index(character.get("race", "Human")),
                         key="char_race")
        
        with col2:
            st.selectbox(_("class", "Class"), ["Fighter", "Wizard", "Cleric", "Rogue", "Ranger", "Paladin", "Barbarian", "Bard", "Druid", "Monk", "Sorcerer", "Warlock"],
                        index=["Fighter", "Wizard", "Cleric", "Rogue", "Ranger", "Paladin", "Barbarian", "Bard", "Druid", "Monk", "Sorcerer", "Warlock"].index(character.get("class", "Fighter")),
                        key="char_class")
            st.number_input(_("level", "Level"), min_value=1, max_value=20, value=character.get("level", 1), key="char_level")
        
        with col3:
            st.text_area(_("description", "Character Description"), value=character.get("description", ""), key="char_description")
            st.text_area(_("background", "Background"), value=character.get("background", ""), key="char_background")

def render_attributes_and_skills(character: Dict[str, Any]):
    """Render the attributes and skills section of the character sheet"""
    
    # Helper function for localized text
    def _(key, default=""):
        """Get localized text for a key"""
        return st.session_state.localization_manager.get_text(key, default=default)
    
    # Get attributes from character
    attributes = character.get("attributes", {})
    
    with st.expander(_("attributes", "Attributes"), expanded=True):
        col1, col2, col3 = st.columns(3)
        
        with col1:
            # Strength
            st.markdown(f"**{_('strength', 'Strength')}**")
            strength = st.number_input(_("strength", "Strength"), min_value=3, max_value=20, value=attributes.get("strength", 10), key="attr_strength")
            modifier = (strength - 10) // 2
            st.markdown(f"Modifier: {modifier:+d}")
            
            # Dexterity
            st.markdown(f"**{_('dexterity', 'Dexterity')}**")
            dexterity = st.number_input(_("dexterity", "Dexterity"), min_value=3, max_value=20, value=attributes.get("dexterity", 10), key="attr_dexterity")
            modifier = (dexterity - 10) // 2
            st.markdown(f"Modifier: {modifier:+d}")
            
        with col2:
            # Constitution
            st.markdown(f"**{_('constitution', 'Constitution')}**")
            constitution = st.number_input(_("constitution", "Constitution"), min_value=3, max_value=20, value=attributes.get("constitution", 10), key="attr_constitution")
            modifier = (constitution - 10) // 2
            st.markdown(f"Modifier: {modifier:+d}")
            
            # Intelligence
            st.markdown(f"**{_('intelligence', 'Intelligence')}**")
            intelligence = st.number_input(_("intelligence", "Intelligence"), min_value=3, max_value=20, value=attributes.get("intelligence", 10), key="attr_intelligence")
            modifier = (intelligence - 10) // 2
            st.markdown(f"Modifier: {modifier:+d}")
            
        with col3:
            # Wisdom
            st.markdown(f"**{_('wisdom', 'Wisdom')}**")
            wisdom = st.number_input(_("wisdom", "Wisdom"), min_value=3, max_value=20, value=attributes.get("wisdom", 10), key="attr_wisdom")
            modifier = (wisdom - 10) // 2
            st.markdown(f"Modifier: {modifier:+d}")
            
            # Charisma
            st.markdown(f"**{_('charisma', 'Charisma')}**")
            charisma = st.number_input(_("charisma", "Charisma"), min_value=3, max_value=20, value=attributes.get("charisma", 10), key="attr_charisma")
            modifier = (charisma - 10) // 2
            st.markdown(f"Modifier: {modifier:+d}")
    
    # Skills
    st.subheader("Skills")
    
    # Get skills
    skills = character.get("skills", {})
    
    # Create columns for skills
    col1, col2, col3 = st.columns(3)
    
    # Define skills with their associated ability
    skill_definitions = {
        "Acrobatics": ("acrobatics", "dexterity"),
        "Animal Handling": ("animal_handling", "wisdom"),
        "Arcana": ("arcana", "intelligence"),
        "Athletics": ("athletics", "strength"),
        "Deception": ("deception", "charisma"),
        "History": ("history", "intelligence"),
        "Insight": ("insight", "wisdom"),
        "Intimidation": ("intimidation", "charisma"),
        "Investigation": ("investigation", "intelligence"),
        "Medicine": ("medicine", "wisdom"),
        "Nature": ("nature", "intelligence"),
        "Perception": ("perception", "wisdom"),
        "Performance": ("performance", "charisma"),
        "Persuasion": ("persuasion", "charisma"),
        "Religion": ("religion", "intelligence"),
        "Sleight of Hand": ("sleight_of_hand", "dexterity"),
        "Stealth": ("stealth", "dexterity"),
        "Survival": ("survival", "wisdom")
    }
    
    # Distribute skills across columns
    skill_list = list(skill_definitions.items())
    skills_per_column = len(skill_list) // 3 + (1 if len(skill_list) % 3 > 0 else 0)
    
    for i, (col, skill_subset) in enumerate(zip([col1, col2, col3], [skill_list[i:i+skills_per_column] for i in range(0, len(skill_list), skills_per_column)])):
        with col:
            for skill_name, (skill_key, ability) in skill_subset:
                # Get the ability modifier
                ability_mod = DiceRoller.calculate_ability_modifier(attributes.get(ability, 10))
                
                # Get the skill proficiency bonus
                proficiency = st.number_input(f"{skill_name} ({ability[0:3].upper()})", 
                                            min_value=0, max_value=10, 
                                            value=skills.get(skill_key, 0),
                                            key=f"skill_{skill_key}")
                
                # Calculate total bonus
                total_bonus = ability_mod + proficiency
                st.text(f"Total: {'+' if total_bonus >= 0 else ''}{total_bonus}")

def render_inventory(character: Dict[str, Any]):
    """Render character inventory"""
    
    # Get localization function
    _ = lambda key, default="", **kwargs: st.session_state.localization_manager.get_text(key, default, **kwargs)
    
    st.subheader(_("character.inventory", "Inventory"))
    
    # Get inventory
    inventory = character.get("inventory", [])
    
    # Display existing items
    if inventory:
        for i, item in enumerate(inventory):
            with st.expander(f"{item.get('quantity')}x {item.get('item_name')} ({item.get('item_type')})"):
                st.text_input("Item Name", value=item.get("item_name", ""), key=f"item_name_{i}")
                st.text_input("Item Type", value=item.get("item_type", ""), key=f"item_type_{i}")
                st.number_input("Quantity", min_value=1, value=item.get("quantity", 1), key=f"item_quantity_{i}")
                st.text_area("Description", value=item.get("description", ""), key=f"item_description_{i}")
                
                # Display properties if any
                properties = item.get("properties", {})
                if properties:
                    st.json(properties)
    else:
        st.info("No items in inventory")
    
    # Add new item form
    with st.expander("Add New Item"):
        with st.form("add_item_form"):
            st.text_input("Item Name", key="new_item_name")
            st.text_input("Item Type", key="new_item_type")
            st.number_input("Quantity", min_value=1, value=1, key="new_item_quantity")
            st.text_area("Description", key="new_item_description")
            
            # Properties as JSON
            st.text_area("Properties (JSON)", "{}", key="new_item_properties")
            
            submitted = st.form_submit_button("Add Item")
            
            if submitted:
                try:
                    # Parse properties JSON
                    properties = json.loads(st.session_state.new_item_properties)
                    
                    # Create item data
                    item_data = {
                        "item_name": st.session_state.new_item_name,
                        "item_type": st.session_state.new_item_type,
                        "quantity": st.session_state.new_item_quantity,
                        "description": st.session_state.new_item_description,
                        "properties": properties
                    }
                    
                    # Add item to inventory
                    item_id = st.session_state.sql_manager.add_item_to_inventory(character["id"], item_data)
                    
                    if item_id:
                        # Reload character to get updated inventory
                        st.session_state.current_character = st.session_state.sql_manager.get_character(character["id"])
                        st.success(f"Item '{item_data['item_name']}' added to inventory!")
                        st.rerun()
                    else:
                        st.error("Failed to add item to inventory. Please try again.")
                
                except json.JSONDecodeError:
                    st.error("Invalid JSON for properties. Please check the format.")

def render_notes(character: Dict[str, Any]):
    """Render character notes"""
    
    # Get localization function
    _ = lambda key, default="", **kwargs: st.session_state.localization_manager.get_text(key, default, **kwargs)
    
    st.subheader(_("character.notes", "Notes"))
    
    # Get notes from character description for now
    # In a real app, you might want a separate notes field
    notes = character.get("description", "")
    
    st.text_area("Character Notes", value=notes, height=300, key="char_notes")

def save_character_changes(character: Dict[str, Any]):
    """Save changes to the character"""
    
    # Get localization function
    _ = lambda key, default="", **kwargs: st.session_state.localization_manager.get_text(key, default, **kwargs)
    
    # Update character data from session state
    character_data = {
        "name": st.session_state.char_name,
        "race": st.session_state.char_race,
        "class": st.session_state.char_class,
        "level": st.session_state.char_level,
        "description": st.session_state.char_description,
        "background": st.session_state.char_background,
        "attributes": {
            "strength": st.session_state.attr_strength,
            "dexterity": st.session_state.attr_dexterity,
            "constitution": st.session_state.attr_constitution,
            "intelligence": st.session_state.attr_intelligence,
            "wisdom": st.session_state.attr_wisdom,
            "charisma": st.session_state.attr_charisma
        },
        "skills": {}
    }
    
    # Update skills
    skill_definitions = {
        "acrobatics": "Acrobatics",
        "animal_handling": "Animal Handling",
        "arcana": "Arcana",
        "athletics": "Athletics",
        "deception": "Deception",
        "history": "History",
        "insight": "Insight",
        "intimidation": "Intimidation",
        "investigation": "Investigation",
        "medicine": "Medicine",
        "nature": "Nature",
        "perception": "Perception",
        "performance": "Performance",
        "persuasion": "Persuasion",
        "religion": "Religion",
        "sleight_of_hand": "Sleight of Hand",
        "stealth": "Stealth",
        "survival": "Survival"
    }
    
    for skill_key in skill_definitions:
        if f"skill_{skill_key}" in st.session_state:
            character_data["skills"][skill_key] = st.session_state[f"skill_{skill_key}"]
    
    # Update character in database
    success = st.session_state.sql_manager.update_character(character["id"], character_data)
    
    if success:
        # Reload character
        st.session_state.current_character = st.session_state.sql_manager.get_character(character["id"])
        st.success(_("character.saved_success", "Character updated successfully!"))
    else:
        st.error(_("character.saved_error", "Failed to update character. Please try again.")) 