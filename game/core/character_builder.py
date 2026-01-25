"""
Character Builder - stores character creation choices
"""

from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any
from core.entities.player import Player
from core.database.json_database import JsonDatabase
import random


@dataclass
class CharacterBuild:
    """Stores all choices during character creation"""
    
    # Biography
    name: str = ""
    alignment: Optional[str] = None
    gender: Optional[str] = None  # "male" / "female"
    age: Optional[int] = None
    weight: Optional[int] = None
    
    # Step 2: Race
    race: Optional[str] = None
    race_data: Optional[Dict[str, Any]] = None
    
    # Step 3: Subrace
    subrace: Optional[str] = None
    subrace_data: Optional[Dict[str, Any]] = None
    
    # Step 4: Class
    class_type: Optional[str] = None
    class_data: Optional[Dict[str, Any]] = None
    
    # Step 5: Subclass
    subclass: Optional[str] = None
    subclass_data: Optional[Dict[str, Any]] = None
    
    # Step 6: Cantrips (level 0 spells)
    cantrips: List[str] = field(default_factory=list)
    cantrips_known: int = 0
    
    # Step 7: Spells
    spells: List[str] = field(default_factory=list)
    spells_known: int = 0
    
    # Step 8: Prepared spells
    prepared_spells: List[str] = field(default_factory=list)
    prepared_count: int = 0
    
    # Step 9: Background
    background: Optional[str] = None
    background_data: Optional[Dict[str, Any]] = None
    
    # Step 10: Abilities (Point Buy)
    abilities: Dict[str, int] = field(default_factory=lambda: {
        "str": 8, "dex": 8, "con": 8, "int": 8, "wis": 8, "cha": 8
    })
    points_remaining: int = 27  # Standard point buy
    
    # Step 11: Proficiency choices (class skills, etc.)
    proficiency_choices_selected: List[str] = field(default_factory=list)
    proficiency_choose: int = 0  # how many to pick (from first choice)
    
    # Step 12: Features (class features from level 1)
    features: List[str] = field(default_factory=list)  # List of feature indices
    feature_choices: Dict[str, str] = field(default_factory=dict)  # feature_index -> chosen_subfeature_index
    
    def get_ability_modifier(self, ability: str) -> int:
        """Calculate ability modifier"""
        score = self.abilities.get(ability, 10)
        return (score - 10) // 2
        
    def get_point_cost(self, score: int) -> int:
        """Get point cost for ability score (point buy system)"""
        costs = {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9}
        return costs.get(score, 0)
        
    def calculate_points_spent(self) -> int:
        """Calculate total points spent"""
        return sum(self.get_point_cost(score) for score in self.abilities.values())
        
    def can_increase_ability(self, ability: str) -> bool:
        """Check if ability can be increased"""
        current = self.abilities.get(ability, 8)
        if current >= 15:
            return False
        next_cost = self.get_point_cost(current + 1) - self.get_point_cost(current)
        return self.points_remaining >= next_cost
        
    def can_decrease_ability(self, ability: str) -> bool:
        """Check if ability can be decreased"""
        return self.abilities.get(ability, 8) > 8
        
    def increase_ability(self, ability: str) -> bool:
        """Increase ability score"""
        if not self.can_increase_ability(ability):
            return False
        current = self.abilities[ability]
        cost = self.get_point_cost(current + 1) - self.get_point_cost(current)
        self.abilities[ability] += 1
        self.points_remaining -= cost
        return True
        
    def decrease_ability(self, ability: str) -> bool:
        """Decrease ability score"""
        if not self.can_decrease_ability(ability):
            return False
        current = self.abilities[ability]
        refund = self.get_point_cost(current) - self.get_point_cost(current - 1)
        self.abilities[ability] -= 1
        self.points_remaining += refund
        return True
    
    def create_character(self) -> Player:
        """
        Create a Character object from this CharacterBuild.
        
        Returns:
            Character instance with all selected attributes
        """
        # Use Character.create_random_character with our selections
        char = Player.create_random_character(
            name=self.name or None,
            race=self.race,
            class_type=self.class_type,
            level=1,
            alignment=self.alignment
        )
        
        # Update abilities from point buy (use actual values from self.abilities, default to 8 if not set)
        from dnd_5e_core.abilities import Abilities
        char.abilities = Abilities(
            str=self.abilities.get("str", 8),
            dex=self.abilities.get("dex", 8),
            con=self.abilities.get("con", 8),
            int=self.abilities.get("int", 8),
            wis=self.abilities.get("wis", 8),
            cha=self.abilities.get("cha", 8)
        )
        
        # Recalculate ability modifiers
        mod = lambda x: (x - 10) // 2
        char.ability_modifiers = Abilities(
            str=mod(char.abilities.str),
            dex=mod(char.abilities.dex),
            con=mod(char.abilities.con),
            int=mod(char.abilities.int),
            wis=mod(char.abilities.wis),
            cha=mod(char.abilities.cha)
        )
        
        # Recalculate hit points with new CON modifier
        if char.class_type:
            char.hit_points = char.class_type.hit_die + char.ability_modifiers.con
            char.max_hit_points = char.hit_points
        
        # Set speed from race data (if available)
        if self.race_data and "speed" in self.race_data:
            char.speed = self.race_data.get("speed", 30)
        
        # Apply biography: gender, age, weight (Character has these from CoreCharacter)
        if self.gender is not None:
            char.gender = self.gender
        if self.age is not None:
            char.age = self.age
        if self.weight is not None:
            char.weight = str(self.weight)
        
        # Load database for proficiency/spell loading
        db = JsonDatabase()
        
        # Apply race ability bonuses first (if any)
        if self.race_data:
            bonuses = self.race_data.get("ability_bonuses", [])
            for bonus in bonuses:
                ab_score = bonus.get("ability_score", {})
                ab_index = ab_score.get("index", "")
                bonus_val = bonus.get("bonus", 0)
                if ab_index in ["str", "dex", "con", "int", "wis", "cha"]:
                    current = getattr(char.abilities, ab_index)
                    setattr(char.abilities, ab_index, current + bonus_val)
        
        # Apply subrace bonuses if subrace selected (adds to race bonuses)
        if self.subrace_data:
            bonuses = self.subrace_data.get("ability_bonuses", [])
            for bonus in bonuses:
                ab_score = bonus.get("ability_score", {})
                ab_index = ab_score.get("index", "")
                bonus_val = bonus.get("bonus", 0)
                if ab_index in ["str", "dex", "con", "int", "wis", "cha"]:
                    current = getattr(char.abilities, ab_index)
                    setattr(char.abilities, ab_index, current + bonus_val)
        
        # Recalculate modifiers after all ability bonuses (race + subrace)
        # Always recalculate to ensure modifiers match final abilities
        char.ability_modifiers = Abilities(
            str=mod(char.abilities.str),
            dex=mod(char.abilities.dex),
            con=mod(char.abilities.con),
            int=mod(char.abilities.int),
            wis=mod(char.abilities.wis),
            cha=mod(char.abilities.cha)
        )
        # Recalculate HP with final CON modifier
        if char.class_type:
            char.hit_points = char.class_type.hit_die + char.ability_modifiers.con
            char.max_hit_points = char.hit_points
        
        def _extract_strings(data_list: List) -> List[str]:
            """Extract strings from list that may contain strings or objects with index/name."""
            result = []
            for item in (data_list or []):
                if isinstance(item, str):
                    result.append(item)
                elif isinstance(item, dict):
                    # Try index first, then name
                    val = item.get("index") or item.get("name")
                    if val:
                        result.append(val)
            return result
        
        # Apply racial features from race_data (damage resistances, immunities, etc.)
        if self.race_data:
            char.damage_vulnerabilities = _extract_strings(self.race_data.get("damage_vulnerabilities", []))
            char.damage_resistances = _extract_strings(self.race_data.get("damage_resistances", []))
            char.damage_immunities = _extract_strings(self.race_data.get("damage_immunities", []))
            char.condition_advantages = _extract_strings(self.race_data.get("condition_advantages", []))
            char.condition_immunities = _extract_strings(self.race_data.get("condition_immunities", []))
            senses_data = self.race_data.get("senses", {})
            if isinstance(senses_data, dict):
                char.senses = senses_data.copy()
            else:
                char.senses = {}
        
        # Apply subrace features (merge with race, subrace overrides)
        if self.subrace_data:
            sub_vuln = _extract_strings(self.subrace_data.get("damage_vulnerabilities", []))
            if sub_vuln:
                char.damage_vulnerabilities = list(set(char.damage_vulnerabilities + sub_vuln))
            sub_res = _extract_strings(self.subrace_data.get("damage_resistances", []))
            if sub_res:
                char.damage_resistances = list(set(char.damage_resistances + sub_res))
            sub_imm = _extract_strings(self.subrace_data.get("damage_immunities", []))
            if sub_imm:
                char.damage_immunities = list(set(char.damage_immunities + sub_imm))
            sub_cond_adv = _extract_strings(self.subrace_data.get("condition_advantages", []))
            if sub_cond_adv:
                char.condition_advantages = list(set(char.condition_advantages + sub_cond_adv))
            sub_cond_imm = _extract_strings(self.subrace_data.get("condition_immunities", []))
            if sub_cond_imm:
                char.condition_immunities = list(set(char.condition_immunities + sub_cond_imm))
            sub_senses = self.subrace_data.get("senses", {})
            if isinstance(sub_senses, dict):
                char.senses.update(sub_senses)
        
        # Apply class features from level 1 and create SpellCaster if needed
        if self.class_type:
            try:
                level_data = db.get(f"/classes/{self.class_type}/levels/1.json")
                features_data = level_data.get("features", [])
                # Start with all features from level 1
                char.features = [f.get("index", "") for f in features_data if f.get("index")]
                # Replace parent features with chosen subfeatures
                for parent_feat, chosen_sub in self.feature_choices.items():
                    if parent_feat in char.features:
                        idx = char.features.index(parent_feat)
                        char.features[idx] = chosen_sub
                    elif chosen_sub not in char.features:
                        char.features.append(chosen_sub)
                
                # Create SpellCaster if class has spellcasting
                if self.class_data and self.class_data.get("spellcasting"):
                    from dnd_5e_core.spells.spellcaster import SpellCaster
                    
                    spellcasting_data = self.class_data.get("spellcasting", {})
                    spellcasting_ability = spellcasting_data.get("spellcasting_ability", {})
                    dc_type = spellcasting_ability.get("index", "cha") if isinstance(spellcasting_ability, dict) else str(spellcasting_ability)
                    
                    # Get spell slots from level_data
                    spellcasting_info = level_data.get("spellcasting", {})
                    spell_slots = []
                    for level in range(1, 10):  # Levels 1-9
                        slot_key = f"spell_slots_level_{level}"
                        slots = spellcasting_info.get(slot_key, 0)
                        spell_slots.append(slots)
                    
                    # Calculate ability modifier for spellcasting
                    ability_mod = getattr(char.ability_modifiers, dc_type, 0)
                    
                    # Calculate spell save DC (proficiency bonus = 2 for level 1)
                    prof_bonus = 2  # Level 1 proficiency bonus
                    dc_value = 8 + prof_bonus + ability_mod
                    
                    # Create SpellCaster
                    char.sc = SpellCaster(
                        level=char.level,
                        spell_slots=spell_slots,
                        learned_spells=[],
                        dc_type=dc_type,
                        dc_value=dc_value,
                        ability_modifier=ability_mod
                    )
            except Exception as e:
                print(f"Error loading features/spellcasting: {e}")
                char.features = []
        
        # Add selected proficiencies from proficiency_choices_selected
        from dnd_5e_core.classes.proficiency import Proficiency, ProfType
        from dnd_5e_core.abilities.abilities import AbilityType
        
        for prof_index in self.proficiency_choices_selected:
            try:
                prof_data = db.get(f"/proficiencies/{prof_index}.json")
                prof_type_str = prof_data.get("type", "Skills")
                # Map type string to ProfType enum
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
                
                # Handle reference
                ref = None
                ref_data = prof_data.get("reference", {})
                if isinstance(ref_data, dict):
                    ref_url = ref_data.get("url", "")
                    if ref_url:
                        parts = ref_url.strip("/").split("/")
                        if len(parts) >= 3:
                            category = parts[-2]  # e.g., "skills", "ability-scores"
                            ref_index = parts[-1]
                            if category == "ability-scores":
                                ref = AbilityType(ref_index)
                            # For skills/equipment, we can use the index string as ref for now
                            # Full implementation would load Equipment objects
                            else:
                                ref = ref_index
                
                new_prof = Proficiency(
                    index=prof_data.get("index", prof_index),
                    name=prof_data.get("name", prof_index),
                    type=prof_type,
                    ref=ref
                )
                # Add if not already in list (avoid duplicates)
                if not any(p.index == new_prof.index for p in char.proficiencies):
                    char.proficiencies.append(new_prof)
            except Exception as e:
                print(f"Error loading proficiency {prof_index}: {e}")
        
        # Add background proficiencies
        if self.background_data:
            bg_profs = self.background_data.get("starting_proficiencies", [])
            for bg_prof_data in bg_profs:
                if isinstance(bg_prof_data, dict):
                    prof_index = bg_prof_data.get("index", "")
                    if prof_index:
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
                            if not any(p.index == new_prof.index for p in char.proficiencies):
                                char.proficiencies.append(new_prof)
                        except Exception as e:
                            print(f"Error loading background proficiency {prof_index}: {e}")
        
        # Add selected spells/cantrips if spellcaster
        if char.sc and (self.cantrips or self.spells):
            from dnd_5e_core.data.loader import load_spell
            from dnd_5e_core.spells.spell import Spell as CoreSpell
            from dnd_5e_core.equipment.weapon import DamageType
            from dnd_5e_core.combat.special_ability import AreaOfEffect
            
            # Load and add cantrips
            for cantrip_index in self.cantrips:
                try:
                    spell_data = db.get(f"/spells/{cantrip_index}.json")
                    # Convert JSON to Spell object
                    spell = self._create_spell_from_json(spell_data, db)
                    if spell and spell not in char.sc.learned_spells:
                        char.sc.learned_spells.append(spell)
                except Exception as e:
                    print(f"Error loading cantrip {cantrip_index}: {e}")
            
            # Load and add level 1 spells
            for spell_index in self.spells:
                try:
                    spell_data = db.get(f"/spells/{spell_index}.json")
                    spell = self._create_spell_from_json(spell_data, db)
                    if spell and spell not in char.sc.learned_spells:
                        char.sc.learned_spells.append(spell)
                except Exception as e:
                    print(f"Error loading spell {spell_index}: {e}")
            
            # Load and add prepared spells (subset of learned spells)
            # Prepared spells must be from learned_spells
            if self.prepared_spells:
                for prepared_spell_index in self.prepared_spells:
                    try:
                        # Find the spell in learned_spells first
                        found_spell = None
                        for learned_spell in char.sc.learned_spells:
                            if learned_spell.index == prepared_spell_index:
                                found_spell = learned_spell
                                break
                        
                        # If not found in learned_spells, load it and add to learned_spells
                        if not found_spell:
                            spell_data = db.get(f"/spells/{prepared_spell_index}.json")
                            found_spell = self._create_spell_from_json(spell_data, db)
                            if found_spell:
                                # Add to learned_spells if not already there
                                if found_spell not in char.sc.learned_spells:
                                    char.sc.learned_spells.append(found_spell)
                        
                        # Add to prepared_spells if found and not already there
                        if found_spell and found_spell not in char.prepared_spells:
                            char.prepared_spells.append(found_spell)
                    except Exception as e:
                        print(f"Error loading prepared spell {prepared_spell_index}: {e}")
        
        # Generate starting equipment
        if self.class_data:
            self._add_starting_equipment(char, db)
        
        # Set background
        char.background = self.background
        
        return char
    
    def _create_spell_from_json(self, spell_data: Dict[str, Any], db: JsonDatabase) -> Optional[Any]:
        """Create Spell object from JSON data"""
        try:
            from dnd_5e_core.spells.spell import Spell as CoreSpell
            from dnd_5e_core.equipment.weapon import DamageType
            from dnd_5e_core.combat.special_ability import AreaOfEffect
            
            # Parse description
            desc = spell_data.get("desc", [])
            if isinstance(desc, list):
                desc = " ".join(desc)
            
            # Parse allowed classes
            allowed_classes = [c.get("index", "") for c in spell_data.get("classes", [])]
            
            # Parse range
            range_str = spell_data.get("range", "Self")
            range_val = 5  # default
            if "feet" in range_str.lower():
                try:
                    range_val = int(range_str.split()[0])
                except:
                    pass
            
            # Parse area of effect
            area = None
            if "area_of_effect" in spell_data:
                aoe_data = spell_data["area_of_effect"]
                area = AreaOfEffect(
                    type=aoe_data.get("type", "sphere"),
                    size=aoe_data.get("size", range_val)
                )
            else:
                area = AreaOfEffect(type="sphere", size=range_val)
            
            # Parse damage
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
            
            # Parse healing
            heal_at_slot_level = None
            if "heal_at_slot_level" in spell_data:
                heal_at_slot_level = spell_data["heal_at_slot_level"]
            
            # Parse DC
            dc_type = None
            dc_success = None
            if "dc" in spell_data:
                dc_data = spell_data["dc"]
                dc_type = dc_data.get("dc_type", {}).get("index")
                dc_success = dc_data.get("dc_success")
            
            # Parse school
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
    
    def _create_equipment_from_json(self, equipment_data: Dict[str, Any], db: JsonDatabase) -> Optional[Any]:
        """Create GameEquipment from JSON data"""
        try:
            from dnd_5e_core.equipment.equipment import Cost, EquipmentCategory
            from core.data.equipment import GameEquipment
            
            # Get equipment category
            eq_category = equipment_data.get("equipment_category", {})
            category_index = eq_category.get("index", "adventuring-gear")
            category_name = eq_category.get("name", "Adventuring Gear")
            category_url = eq_category.get("url", f"/api/2014/equipment-categories/{category_index}")
            
            category = EquipmentCategory(
                index=category_index,
                name=category_name,
                url=category_url
            )
            
            # Get cost
            cost_data = equipment_data.get("cost", {})
            cost = Cost(
                quantity=cost_data.get("quantity", 0),
                unit=cost_data.get("unit", "gp")
            )
            
            # Get weight (default to 0 if not specified)
            weight = equipment_data.get("weight", 0)
            
            armor_class_base = None
            damage_dice_str = None
            if category_index == "armor":
                ac_data = equipment_data.get("armor_class", {})
                if isinstance(ac_data, dict):
                    armor_class_base = ac_data.get("base", 10)
                elif isinstance(ac_data, int):
                    armor_class_base = ac_data
            elif category_index == "weapon":
                damage_data = equipment_data.get("damage", {})
                if isinstance(damage_data, dict):
                    damage_dice_str = damage_data.get("damage_dice", None)
            
            # Get description
            desc = equipment_data.get("desc", [])
            if isinstance(desc, str):
                desc = [desc]
            
            return GameEquipment(
                index=equipment_data.get("index", ""),
                name=equipment_data.get("name", ""),
                cost=cost,
                weight=weight,
                desc=desc if desc else None,
                category=category,
                equipped=False,
                equipped_left_hand=False,
                equipped_right_hand=False,
                equipped_slot=None,
                armor_class_base=armor_class_base,
                damage_dice_str=damage_dice_str,
            )
        except Exception as e:
            print(f"Error creating equipment from JSON: {e}")
            return None
    
    def _add_item_to_inventory(self, char: Player, item_index: str, quantity: int, db: JsonDatabase) -> None:
        """Add item(s) to character inventory (unlimited capacity)"""
        try:
            equipment_data = db.get(f"/equipment/{item_index}.json")
            equipment = self._create_equipment_from_json(equipment_data, db)
            
            if equipment:
                # Check if item has contents (equipment pack)
                contents = equipment_data.get("contents", [])
                if contents:
                    # Don't add pack itself, only unpack contents
                    # Unpack contents
                    for content_item in contents:
                        content_data = content_item.get("item", {})
                        content_index = content_data.get("index", "")
                        content_quantity = content_item.get("quantity", 1)
                        
                        if content_index:
                            # Add each content item
                            for _ in range(quantity * content_quantity):
                                content_eq_data = db.get(f"/equipment/{content_index}.json")
                                content_eq = self._create_equipment_from_json(content_eq_data, db)
                                if content_eq:
                                    # Add to inventory (unlimited capacity)
                                    # First try to find empty slot, otherwise append
                                    slot_found = False
                                    for i, slot in enumerate(char.inventory):
                                        if slot is None:
                                            char.inventory[i] = content_eq
                                            slot_found = True
                                            break
                                    if not slot_found:
                                        char.inventory.append(content_eq)
                else:
                    # Regular item, add quantity times (each copy is a new instance)
                    for _ in range(quantity):
                        eq = self._create_equipment_from_json(equipment_data, db)
                        if not eq:
                            break
                        slot_found = False
                        for i, slot in enumerate(char.inventory):
                            if slot is None:
                                char.inventory[i] = eq
                                slot_found = True
                                break
                        if not slot_found:
                            char.inventory.append(eq)
        except Exception as e:
            print(f"Error adding item {item_index} to inventory: {e}")
    
    def _resolve_equipment_option(self, option: Dict[str, Any], db: JsonDatabase) -> List[tuple]:
        """Resolve an equipment option to list of (index, quantity) tuples"""
        result = []
        option_type = option.get("option_type", "")
        
        if option_type == "counted_reference":
            # Direct reference to equipment
            of_data = option.get("of", {})
            item_index = of_data.get("index", "")
            count = option.get("count", 1)
            if item_index:
                result.append((item_index, count))
        
        elif option_type == "multiple":
            # Multiple items
            items = option.get("items", [])
            for item in items:
                result.extend(self._resolve_equipment_option(item, db))
        
        elif option_type == "choice":
            # Nested choice (e.g., "any simple weapon")
            choice_data = option.get("choice", {})
            choice_type = choice_data.get("type", "")
            choose_count = choice_data.get("choose", 1)
            
            if choice_type == "equipment":
                from_data = choice_data.get("from", {})
                option_set_type = from_data.get("option_set_type", "")
                
                if option_set_type == "equipment_category":
                    # Category choice - pick random from category
                    category_data = from_data.get("equipment_category", {})
                    category_index = category_data.get("index", "")
                    
                    if category_index:
                        # Get all equipment in category
                        try:
                            category_data_file = db.get(f"/equipment-categories/{category_index}.json")
                            equipment_list = category_data_file.get("equipment", [])
                            
                            if equipment_list:
                                # Pick random equipment(s) based on choose_count
                                selected_equipment = random.sample(equipment_list, min(choose_count, len(equipment_list)))
                                for random_eq in selected_equipment:
                                    eq_index = random_eq.get("index", "")
                                    if eq_index:
                                        result.append((eq_index, 1))
                        except Exception as e:
                            print(f"Error resolving equipment category {category_index}: {e}")
        
        return result
    
    def _add_starting_equipment(self, char: Player, db: JsonDatabase) -> None:
        """Add starting equipment from class data"""
        if not self.class_data:
            return
        
        # Add starting_equipment (guaranteed items)
        starting_equipment = self.class_data.get("starting_equipment", [])
        for item in starting_equipment:
            equipment_data = item.get("equipment", {})
            item_index = equipment_data.get("index", "")
            quantity = item.get("quantity", 1)
            
            if item_index:
                self._add_item_to_inventory(char, item_index, quantity, db)
        
        # Process starting_equipment_options (random choices)
        starting_options = self.class_data.get("starting_equipment_options", [])
        for option_group in starting_options:
            choose = option_group.get("choose", 1)
            from_data = option_group.get("from", {})
            option_set_type = from_data.get("option_set_type", "")
            
            if option_set_type == "options_array":
                options = from_data.get("options", [])
                
                # Randomly select 'choose' number of options
                if options and choose > 0:
                    selected = random.sample(options, min(choose, len(options)))
                    
                    for selected_option in selected:
                        # Resolve the option to equipment items
                        resolved_items = self._resolve_equipment_option(selected_option, db)
                        
                        # Add each resolved item
                        for item_index, quantity in resolved_items:
                            self._add_item_to_inventory(char, item_index, quantity, db)
