"""
Level Up Utilities - functions for checking and handling level ups
"""

from typing import Optional, Dict, Any
from core.database.json_database import JsonDatabase
from core.entities.character import Character


def can_level_up(player: Optional[Character]) -> bool:
    """
    Check if player has enough XP to level up.
    
    Args:
        player: Character to check
        
    Returns:
        True if player can level up, False otherwise
    """
    if not player:
        return False
    
    # Max level is 20
    if player.level >= 20:
        return False
    
    db = JsonDatabase()
    try:
        level_up_data = db.get("/rules/level_up.json")
        # Find the entry for the next level
        next_level = player.level + 1
        for entry in level_up_data:
            if entry.get("level") == next_level:
                xp_required = entry.get("xp_required_total", 0)
                return player.xp >= xp_required
    except Exception as e:
        print(f"Error checking level up: {e}")
        return False
    
    return False


def get_next_level_xp_required(player: Optional[Character]) -> Optional[int]:
    """
    Get the XP required for the next level.
    
    Args:
        player: Character to check
        
    Returns:
        XP required for next level, or None if max level
    """
    if not player or player.level >= 20:
        return None
    
    db = JsonDatabase()
    try:
        level_up_data = db.get("/rules/level_up.json")
        next_level = player.level + 1
        for entry in level_up_data:
            if entry.get("level") == next_level:
                return entry.get("xp_required_total", None)
    except Exception as e:
        print(f"Error getting next level XP: {e}")
        return None
    
    return None


def get_level_data(class_index: str, level: int) -> Optional[Dict[str, Any]]:
    """
    Get level data for a specific class and level.
    
    Args:
        class_index: Class index (e.g., "fighter", "wizard")
        level: Level number (1-20)
        
    Returns:
        Level data dictionary or None if not found
    """
    db = JsonDatabase()
    try:
        return db.get(f"/classes/{class_index}/levels/{level}.json")
    except Exception as e:
        print(f"Error loading level data for {class_index} level {level}: {e}")
        return None
