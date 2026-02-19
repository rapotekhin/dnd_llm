"""
Level Up Builder - stores level up choices
"""

from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any, Union
from core.entities.player import Player
from core.database.json_database import JsonDatabase


@dataclass
class LevelUpBuild:
    """Stores all choices during level up"""
    
    # New level
    new_level: int = 0
    
    # Ability score improvements (if any)
    ability_score_bonuses: int = 0  # How many points to distribute
    abilities: Dict[str, int] = field(default_factory=lambda: {
        "str": 0, "dex": 0, "con": 0, "int": 0, "wis": 0, "cha": 0
    })
    
    # New features
    features: List[str] = field(default_factory=list)  # List of feature indices
    feature_choices: Dict[str, Union[str, List[str]]] = field(default_factory=dict)  # feature_index -> chosen_subfeature_index(es) - can be string or list
    
    # New spells (if spellcaster)
    new_cantrips: List[str] = field(default_factory=list)
    new_spells: List[str] = field(default_factory=list)
    
    # Proficiency choices (if any)
    proficiency_choices_selected: List[str] = field(default_factory=list)
    
    def apply_level_up(self, player: Player) -> Player:
        """
        Apply level up changes to the player character.
        
        Args:
            player: Character to level up
            
        Returns:
            Updated character
        """
        # Increase level
        player.level = self.new_level
        
        # Apply ability score improvements
        if self.ability_score_bonuses > 0:
            from dnd_5e_core.abilities import Abilities
            # Apply ability increases
            for ability, bonus in self.abilities.items():
                if bonus > 0:
                    current = getattr(player.abilities, ability)
                    setattr(player.abilities, ability, current + bonus)
            
            # Recalculate modifiers
            mod = lambda x: (x - 10) // 2
            player.ability_modifiers = Abilities(
                str=mod(player.abilities.str),
                dex=mod(player.abilities.dex),
                con=mod(player.abilities.con),
                int=mod(player.abilities.int),
                wis=mod(player.abilities.wis),
                cha=mod(player.abilities.cha)
            )
            
            # Note: HP increase for new level is handled at the end, after all modifiers are updated
        
        # Add new features
        if self.features:
            for feat_index in self.features:
                if feat_index not in player.features:
                    player.features.append(feat_index)
            
            # Replace parent features with chosen subfeatures
            for parent_feat, chosen_sub in self.feature_choices.items():
                # Handle both single choice (string) and multiple choices (list)
                if isinstance(chosen_sub, list):
                    # Multiple subfeatures chosen
                    # Remove parent feature if present
                    if parent_feat in player.features:
                        idx = player.features.index(parent_feat)
                        player.features.pop(idx)
                    # Add all chosen subfeatures
                    for subfeat in chosen_sub:
                        if subfeat not in player.features:
                            player.features.append(subfeat)
                else:
                    # Single subfeature chosen
                    if parent_feat in player.features:
                        idx = player.features.index(parent_feat)
                        player.features[idx] = chosen_sub
                    elif chosen_sub not in player.features:
                        player.features.append(chosen_sub)
        
        # Add new spells if spellcaster
        if player.sc and (self.new_cantrips or self.new_spells):
            from dnd_5e_core.data.loader import load_spell
            from dnd_5e_core.spells.spell import Spell as CoreSpell
            from dnd_5e_core.equipment.weapon import DamageType
            from dnd_5e_core.combat.special_ability import AreaOfEffect
            
            db = JsonDatabase()
            
            # Add new cantrips
            for cantrip_index in self.new_cantrips:
                try:
                    spell_data = db.get(f"/spells/{cantrip_index}.json")
                    spell = self._create_spell_from_json(spell_data, db)
                    if spell and spell not in player.sc.learned_spells:
                        player.sc.learned_spells.append(spell)
                except Exception as e:
                    print(f"Error loading cantrip {cantrip_index}: {e}")
            
            # Add new spells
            for spell_index in self.new_spells:
                try:
                    spell_data = db.get(f"/spells/{spell_index}.json")
                    spell = self._create_spell_from_json(spell_data, db)
                    if spell and spell not in player.sc.learned_spells:
                        player.sc.learned_spells.append(spell)
                except Exception as e:
                    print(f"Error loading spell {spell_index}: {e}")
            
            # Update spell slots from new level
            try:
                class_index = player.class_type.index if hasattr(player.class_type, 'index') else str(player.class_type)
                level_data = db.get(f"/classes/{class_index}/levels/{self.new_level}.json")
                spellcasting_info = level_data.get("spellcasting", {})
                if spellcasting_info:
                    spell_slots = []
                    for level in range(1, 10):
                        slot_key = f"spell_slots_level_{level}"
                        slots = spellcasting_info.get(slot_key, 0)
                        spell_slots.append(slots)
                    player.sc.spell_slots = spell_slots
                    
                    # Update spell DC
                    if player.class_type.is_spellcaster and player.class_type.spellcasting_ability:
                        dc_type = player.class_type.spellcasting_ability  # "int", "wis", or "cha"
                        ability_mod = getattr(player.ability_modifiers, dc_type, 0)
                        prof_bonus = player.class_type.get_proficiency_bonus(self.new_level)
                        player.sc.dc_value = 8 + prof_bonus + ability_mod
                        player.sc.ability_modifier = ability_mod
            except Exception as e:
                print(f"Error updating spell slots: {e}")
        
        # Add new proficiencies
        if self.proficiency_choices_selected:
            from dnd_5e_core.classes.proficiency import Proficiency, ProfType
            from dnd_5e_core.abilities.abilities import AbilityType
            
            db = JsonDatabase()
            for prof_index in self.proficiency_choices_selected:
                try:
                    prof_data = db.get(f"/proficiencies/{prof_index}.json")
                    prof_type_str = prof_data.get("type", "Skills")
                    type_map = {
                        "Skills": ProfType.SKILL,
                        "Armor": ProfType.ARMOR,
                        "Weapons": ProfType.WEAPON,
                        "Artisan's Tools": ProfType.TOOLS,
                        "Musical Instruments": ProfType.MUSIC,
                        "Gaming Sets": ProfType.GAMING,
                        "Vehicles": ProfType.VEHICLE,
                        "Saving Throws": ProfType.ST,
                        "Other": ProfType.OTHER
                    }
                    prof_type = type_map.get(prof_type_str, ProfType.OTHER)
                    
                    ref = None
                    ref_data = prof_data.get("reference", {})
                    if isinstance(ref_data, dict):
                        ref_url = ref_data.get("url", "")
                        if ref_url:
                            parts = ref_url.strip("/").split("/")
                            if len(parts) >= 3:
                                category = parts[-2]
                                ref_index = parts[-1]
                                if category == "ability-scores":
                                    ref = AbilityType(ref_index)
                                else:
                                    ref = ref_index
                    
                    new_prof = Proficiency(
                        index=prof_data.get("index", prof_index),
                        name=prof_data.get("name", prof_index),
                        type=prof_type,
                        ref=ref
                    )
                    if not any(p.index == new_prof.index for p in player.proficiencies):
                        player.proficiencies.append(new_prof)
                except Exception as e:
                    print(f"Error loading proficiency {prof_index}: {e}")
        
        # Increase HP for new level (with new CON modifier after ability improvements)
        if player.class_type:
            # Use the updated CON modifier after ability improvements
            con_modifier = player.ability_modifiers.con
            hp_increase = player.class_type.hit_die + con_modifier
            player.max_hit_points += hp_increase
            player.hit_points += hp_increase
        
        # Update class_specific features from level data
        from core.utils.level_up_utils import get_level_data
        class_index = player.class_type.index if hasattr(player.class_type, 'index') else str(player.class_type)
        level_data = get_level_data(class_index, self.new_level)
        if level_data and "class_specific" in level_data:
            # Update class_specific fields
            class_specific = level_data.get("class_specific", {})
            if not hasattr(player, "class_specific") or player.class_specific is None:
                player.class_specific = {}
            # Update all class_specific fields from level data
            for key, value in class_specific.items():
                player.class_specific[key] = value
        
        return player
    
    def _create_spell_from_json(self, spell_data: Dict[str, Any], db: JsonDatabase) -> Optional[Any]:
        """Create Spell object from JSON data"""
        try:
            from dnd_5e_core.spells.spell import Spell as CoreSpell
            from dnd_5e_core.equipment.weapon import DamageType
            from dnd_5e_core.combat.special_ability import AreaOfEffect
            
            desc = spell_data.get("desc", [])
            if isinstance(desc, list):
                desc = " ".join(desc)
            
            allowed_classes = [c.get("index", "") for c in spell_data.get("classes", [])]
            
            range_str = spell_data.get("range", "Self")
            range_val = 5
            if "feet" in range_str.lower():
                try:
                    range_val = int(range_str.split()[0])
                except:
                    pass
            
            area = None
            if "area_of_effect" in spell_data:
                aoe_data = spell_data["area_of_effect"]
                area = AreaOfEffect(
                    type=aoe_data.get("type", "sphere"),
                    size=aoe_data.get("size", range_val)
                )
            else:
                area = AreaOfEffect(type="sphere", size=range_val)
            
            damage_type = None
            damage_at_slot_level = None
            damage_at_character_level = None
            if "damage" in spell_data:
                dmg_data = spell_data["damage"]
                if "damage_type" in dmg_data:
                    dt_data = dmg_data["damage_type"]
                    if isinstance(dt_data, dict):
                        dt_index = dt_data.get("index", "")
                        if dt_index:
                            try:
                                dt_json = db.get(f"/damage-types/{dt_index}.json")
                                damage_type = DamageType(
                                    index=dt_json.get("index", dt_index),
                                    name=dt_json.get("name", dt_index),
                                    desc=dt_json.get("desc", [""])[0] if isinstance(dt_json.get("desc"), list) else dt_json.get("desc", "")
                                )
                            except Exception:
                                damage_type = DamageType(index=dt_index, name=dt_index, desc="")
                damage_at_slot_level = dmg_data.get("damage_at_slot_level")
                damage_at_character_level = dmg_data.get("damage_at_character_level")
            
            heal_at_slot_level = None
            if "heal_at_slot_level" in spell_data:
                heal_at_slot_level = spell_data["heal_at_slot_level"]
            
            dc_type = None
            dc_success = None
            if "dc" in spell_data:
                dc_data = spell_data["dc"]
                dc_type = dc_data.get("dc_type", {}).get("index")
                dc_success = dc_data.get("dc_success")
            
            school = spell_data.get("school", {}).get("index", "evocation")
            
            return CoreSpell(
                index=spell_data.get("index", ""),
                name=spell_data.get("name", ""),
                desc=desc,
                level=spell_data.get("level", 0),
                allowed_classes=allowed_classes,
                heal_at_slot_level=heal_at_slot_level,
                damage_type=damage_type,
                damage_at_slot_level=damage_at_slot_level,
                damage_at_character_level=damage_at_character_level,
                dc_type=dc_type,
                dc_success=dc_success,
                range=range_val,
                area_of_effect=area,
                school=school
            )
        except Exception as e:
            print(f"Error creating spell from JSON: {e}")
            return None
