import random
import re
from typing import Dict, List, Tuple, Union, Optional

class DiceRoller:
    """Utility for rolling dice and handling D&D mechanics"""
    
    @staticmethod
    def roll_dice(dice_notation: str) -> Dict[str, Union[int, List[int], str]]:
        """
        Roll dice based on standard dice notation (e.g., 2d6+3)
        
        Args:
            dice_notation: Dice notation string (e.g., "2d6+3", "1d20", "3d8-2")
            
        Returns:
            Dictionary containing roll results
        """
        try:
            # Parse the dice notation
            pattern = r"(\d+)d(\d+)([+-]\d+)?"
            match = re.match(pattern, dice_notation.lower().replace(" ", ""))
            
            if not match:
                return {
                    "success": False,
                    "error": f"Invalid dice notation: {dice_notation}"
                }
            
            num_dice = int(match.group(1))
            dice_type = int(match.group(2))
            modifier = int(match.group(3) or "+0")
            
            # Roll the dice
            rolls = [random.randint(1, dice_type) for _ in range(num_dice)]
            total = sum(rolls) + modifier
            
            return {
                "success": True,
                "rolls": rolls,
                "modifier": modifier,
                "total": total,
                "dice_notation": dice_notation
            }
        
        except Exception as e:
            return {
                "success": False,
                "error": f"Error rolling dice: {str(e)}"
            }
    
    @staticmethod
    def roll_with_advantage(disadvantage: bool = False) -> Dict[str, Union[int, List[int], str, bool]]:
        """
        Roll with advantage or disadvantage (two d20s, take highest or lowest)
        
        Args:
            disadvantage: If True, take the lower roll (disadvantage)
            
        Returns:
            Dictionary containing roll results
        """
        roll1 = random.randint(1, 20)
        roll2 = random.randint(1, 20)
        
        if disadvantage:
            final_roll = min(roll1, roll2)
            advantage_type = "disadvantage"
        else:
            final_roll = max(roll1, roll2)
            advantage_type = "advantage"
        
        return {
            "success": True,
            "rolls": [roll1, roll2],
            "total": final_roll,
            "advantage_type": advantage_type,
            "dice_notation": "1d20 with " + advantage_type
        }
    
    @staticmethod
    def check_success(dc: int, roll_result: int, ability_modifier: int = 0) -> Dict[str, Union[int, bool, str]]:
        """
        Check if a roll succeeds against a DC (Difficulty Class)
        
        Args:
            dc: Difficulty Class to beat
            roll_result: Result of the dice roll
            ability_modifier: Additional modifier to add
            
        Returns:
            Dictionary containing success information
        """
        total = roll_result + ability_modifier
        success = total >= dc
        
        return {
            "success": success,
            "roll": roll_result,
            "ability_modifier": ability_modifier,
            "total": total,
            "dc": dc,
            "margin": abs(total - dc)
        }
    
    @staticmethod
    def calculate_ability_modifier(ability_score: int) -> int:
        """
        Calculate ability modifier from ability score
        
        Args:
            ability_score: Ability score (e.g., Strength, Dexterity)
            
        Returns:
            Ability modifier
        """
        return (ability_score - 10) // 2
    
    @staticmethod
    def roll_initiative(dexterity_modifier: int, advantage: bool = False, 
                       disadvantage: bool = False) -> Dict[str, Union[int, List[int], bool]]:
        """
        Roll for initiative
        
        Args:
            dexterity_modifier: Character's dexterity modifier
            advantage: Roll with advantage
            disadvantage: Roll with disadvantage
            
        Returns:
            Dictionary containing initiative roll results
        """
        if advantage or disadvantage:
            advantage_roll = DiceRoller.roll_with_advantage(disadvantage)
            base_roll = advantage_roll["total"]
            rolls = advantage_roll["rolls"]
        else:
            base_roll = random.randint(1, 20)
            rolls = [base_roll]
        
        initiative = base_roll + dexterity_modifier
        
        return {
            "success": True,
            "rolls": rolls,
            "dexterity_modifier": dexterity_modifier,
            "total": initiative,
            "advantage": advantage,
            "disadvantage": disadvantage
        }
    
    @staticmethod
    def attack_roll(attack_bonus: int, advantage: bool = False, 
                   disadvantage: bool = False) -> Dict[str, Union[int, List[int], bool, str]]:
        """
        Make an attack roll
        
        Args:
            attack_bonus: Character's attack bonus
            advantage: Roll with advantage
            disadvantage: Roll with disadvantage
            
        Returns:
            Dictionary containing attack roll results
        """
        if advantage or disadvantage:
            advantage_roll = DiceRoller.roll_with_advantage(disadvantage)
            base_roll = advantage_roll["total"]
            rolls = advantage_roll["rolls"]
        else:
            base_roll = random.randint(1, 20)
            rolls = [base_roll]
        
        # Check for critical hit or miss
        is_crit = base_roll == 20
        is_crit_fail = base_roll == 1
        
        attack_total = base_roll + attack_bonus
        
        return {
            "success": True,
            "rolls": rolls,
            "attack_bonus": attack_bonus,
            "total": attack_total,
            "is_critical_hit": is_crit,
            "is_critical_fail": is_crit_fail,
            "advantage": advantage,
            "disadvantage": disadvantage
        }
    
    @staticmethod
    def damage_roll(damage_dice: str, critical: bool = False) -> Dict[str, Union[int, List[int], str, bool]]:
        """
        Roll for damage
        
        Args:
            damage_dice: Damage dice notation (e.g., "2d6+3")
            critical: Whether this is a critical hit (double dice)
            
        Returns:
            Dictionary containing damage roll results
        """
        # Parse the damage dice
        pattern = r"(\d+)d(\d+)([+-]\d+)?"
        match = re.match(pattern, damage_dice.lower().replace(" ", ""))
        
        if not match:
            return {
                "success": False,
                "error": f"Invalid damage dice notation: {damage_dice}"
            }
        
        num_dice = int(match.group(1))
        dice_type = int(match.group(2))
        modifier = int(match.group(3) or "+0")
        
        # Double dice for critical hits
        if critical:
            num_dice *= 2
        
        # Roll the dice
        rolls = [random.randint(1, dice_type) for _ in range(num_dice)]
        total = sum(rolls) + modifier
        
        return {
            "success": True,
            "rolls": rolls,
            "modifier": modifier,
            "total": total,
            "critical": critical,
            "damage_dice": damage_dice,
            "effective_dice": f"{num_dice}d{dice_type}{match.group(3) or ''}" if critical else damage_dice
        } 