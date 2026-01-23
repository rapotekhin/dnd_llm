import os
import sqlite3
import json
from typing import Dict, List, Any, Optional, Tuple
from pathlib import Path

class SQLDatabaseManager:
    """Manager for SQL database operations"""
    
    def __init__(self, db_path: str):
        """Initialize the SQL database manager"""
        self.db_path = db_path
        self._ensure_db_exists()
        self._create_tables()
    
    def _ensure_db_exists(self):
        """Ensure the database file exists"""
        db_dir = os.path.dirname(self.db_path)
        if db_dir and not os.path.exists(db_dir):
            os.makedirs(db_dir)
    
    def _create_tables(self):
        """Create necessary tables if they don't exist"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            # Characters table
            cursor.execute('''
            CREATE TABLE IF NOT EXISTS characters (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                race TEXT NOT NULL,
                class TEXT NOT NULL,
                level INTEGER NOT NULL,
                attributes TEXT NOT NULL,
                skills TEXT NOT NULL,
                background TEXT,
                description TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            ''')
            
            # Inventory table
            cursor.execute('''
            CREATE TABLE IF NOT EXISTS inventory (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                character_id INTEGER NOT NULL,
                item_name TEXT NOT NULL,
                item_type TEXT NOT NULL,
                quantity INTEGER NOT NULL,
                description TEXT,
                properties TEXT,
                FOREIGN KEY (character_id) REFERENCES characters (id)
            )
            ''')
            
            # NPCs table (allies and enemies)
            cursor.execute('''
            CREATE TABLE IF NOT EXISTS npcs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL,
                race TEXT,
                class TEXT,
                level INTEGER,
                attributes TEXT,
                description TEXT,
                is_ally BOOLEAN NOT NULL,
                campaign_id INTEGER
            )
            ''')
            
            # Campaigns table
            cursor.execute('''
            CREATE TABLE IF NOT EXISTS campaigns (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                description TEXT,
                dm_notes TEXT,
                current_location TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
            ''')
            
            conn.commit()
    
    def create_character(self, character_data: Dict[str, Any]) -> int:
        """
        Create a new character
        
        Args:
            character_data: Dictionary containing character information
            
        Returns:
            The ID of the newly created character
        """
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            # Convert dictionaries to JSON strings
            attributes = json.dumps(character_data.get('attributes', {}))
            skills = json.dumps(character_data.get('skills', {}))
            
            cursor.execute('''
            INSERT INTO characters (name, race, class, level, attributes, skills, background, description)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                character_data.get('name', ''),
                character_data.get('race', ''),
                character_data.get('class', ''),
                character_data.get('level', 1),
                attributes,
                skills,
                character_data.get('background', ''),
                character_data.get('description', '')
            ))
            
            conn.commit()
            return cursor.lastrowid
    
    def get_character(self, character_id: int) -> Optional[Dict[str, Any]]:
        """
        Get a character by ID
        
        Args:
            character_id: The ID of the character to retrieve
            
        Returns:
            Dictionary containing character information or None if not found
        """
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            
            cursor.execute('SELECT * FROM characters WHERE id = ?', (character_id,))
            row = cursor.fetchone()
            
            if not row:
                return None
            
            character = dict(row)
            
            # Parse JSON strings back to dictionaries
            character['attributes'] = json.loads(character['attributes'])
            character['skills'] = json.loads(character['skills'])
            
            # Get character's inventory
            cursor.execute('SELECT * FROM inventory WHERE character_id = ?', (character_id,))
            inventory_rows = cursor.fetchall()
            
            character['inventory'] = [dict(row) for row in inventory_rows]
            for item in character['inventory']:
                if 'properties' in item and item['properties']:
                    item['properties'] = json.loads(item['properties'])
            
            return character
    
    def get_all_characters(self) -> List[Dict[str, Any]]:
        """
        Get all characters
        
        Returns:
            List of dictionaries containing character information
        """
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            
            cursor.execute('SELECT id, name, race, class, level FROM characters')
            rows = cursor.fetchall()
            
            return [dict(row) for row in rows]
    
    def update_character(self, character_id: int, character_data: Dict[str, Any]) -> bool:
        """
        Update a character
        
        Args:
            character_id: The ID of the character to update
            character_data: Dictionary containing updated character information
            
        Returns:
            True if successful, False otherwise
        """
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            # Convert dictionaries to JSON strings
            attributes = json.dumps(character_data.get('attributes', {}))
            skills = json.dumps(character_data.get('skills', {}))
            
            cursor.execute('''
            UPDATE characters
            SET name = ?, race = ?, class = ?, level = ?, attributes = ?, skills = ?, 
                background = ?, description = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            ''', (
                character_data.get('name', ''),
                character_data.get('race', ''),
                character_data.get('class', ''),
                character_data.get('level', 1),
                attributes,
                skills,
                character_data.get('background', ''),
                character_data.get('description', ''),
                character_id
            ))
            
            conn.commit()
            return cursor.rowcount > 0
    
    def add_item_to_inventory(self, character_id: int, item_data: Dict[str, Any]) -> int:
        """
        Add an item to a character's inventory
        
        Args:
            character_id: The ID of the character
            item_data: Dictionary containing item information
            
        Returns:
            The ID of the newly added item
        """
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            properties = json.dumps(item_data.get('properties', {}))
            
            cursor.execute('''
            INSERT INTO inventory (character_id, item_name, item_type, quantity, description, properties)
            VALUES (?, ?, ?, ?, ?, ?)
            ''', (
                character_id,
                item_data.get('item_name', ''),
                item_data.get('item_type', ''),
                item_data.get('quantity', 1),
                item_data.get('description', ''),
                properties
            ))
            
            conn.commit()
            return cursor.lastrowid
    
    def create_npc(self, npc_data: Dict[str, Any]) -> int:
        """
        Create a new NPC (ally or enemy)
        
        Args:
            npc_data: Dictionary containing NPC information
            
        Returns:
            The ID of the newly created NPC
        """
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            attributes = json.dumps(npc_data.get('attributes', {}))
            
            cursor.execute('''
            INSERT INTO npcs (name, type, race, class, level, attributes, description, is_ally, campaign_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                npc_data.get('name', ''),
                npc_data.get('type', ''),
                npc_data.get('race', ''),
                npc_data.get('class', ''),
                npc_data.get('level', 1),
                attributes,
                npc_data.get('description', ''),
                npc_data.get('is_ally', True),
                npc_data.get('campaign_id')
            ))
            
            conn.commit()
            return cursor.lastrowid
    
    def get_npcs(self, campaign_id: Optional[int] = None, is_ally: Optional[bool] = None) -> List[Dict[str, Any]]:
        """
        Get NPCs filtered by campaign and/or ally status
        
        Args:
            campaign_id: Optional campaign ID to filter by
            is_ally: Optional boolean to filter allies or enemies
            
        Returns:
            List of dictionaries containing NPC information
        """
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            
            query = 'SELECT * FROM npcs'
            params = []
            
            conditions = []
            if campaign_id is not None:
                conditions.append('campaign_id = ?')
                params.append(campaign_id)
            
            if is_ally is not None:
                conditions.append('is_ally = ?')
                params.append(is_ally)
            
            if conditions:
                query += ' WHERE ' + ' AND '.join(conditions)
            
            cursor.execute(query, params)
            rows = cursor.fetchall()
            
            npcs = [dict(row) for row in rows]
            for npc in npcs:
                if 'attributes' in npc and npc['attributes']:
                    npc['attributes'] = json.loads(npc['attributes'])
            
            return npcs
    
    def execute_query(self, query: str, params: Tuple = ()) -> List[Dict[str, Any]]:
        """
        Execute a custom SQL query (for LLM to use)
        
        Args:
            query: SQL query string
            params: Query parameters
            
        Returns:
            List of dictionaries containing query results
        """
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            
            try:
                cursor.execute(query, params)
                rows = cursor.fetchall()
                return [dict(row) for row in rows]
            except sqlite3.Error as e:
                print(f"Database error: {e}")
                return [] 