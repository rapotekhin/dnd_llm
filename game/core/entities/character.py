"""
Game Character - wrapper around dnd_5e_core Character
"""

from dnd_5e_core.entities.character import Character as CoreCharacter
from dnd_5e_core.data.loaders import simple_character_generator
from typing import Optional, List, Dict, Any, TYPE_CHECKING
from dataclasses import field
from core.utils import coin_converter
from core.entities.base import BaseEntity, ID

if TYPE_CHECKING:
    from dnd_5e_core.spells.spell import Spell


class Character(BaseEntity, CoreCharacter):
    """Game character with simplified creation"""
    role: str | None = None

    # Additional fields for game-specific features
    prepared_spells: List['Spell'] = field(default_factory=list)
    alignment: Optional[str] = None
    background: Optional[str] = None

    coins: int = 0  # copper pieces

    # Racial features from JSON
    damage_vulnerabilities: List[str] = field(default_factory=list)
    damage_resistances: List[str] = field(default_factory=list)
    damage_immunities: List[str] = field(default_factory=list)
    condition_advantages: List[str] = field(default_factory=list)
    condition_immunities: List[str] = field(default_factory=list)
    senses: Dict[str, str] = field(default_factory=dict)

    # Class features
    features: List[str] = field(default_factory=list)  # List of feature indices (including chosen subfeatures)

    # Class-specific features (action_surges, indomitable_uses, extra_attacks, etc.)
    class_specific: Dict[str, Any] = field(default_factory=dict)
    id: Optional[ID] = field(default=None)
    _id_prefix: str = "character"

    def __init__(self, **kwargs):
        # Initialize CoreCharacter (dnd_5e_core) so we get race, class_type, abilities, etc.
        core_fields = {k: v for k, v in kwargs.items() if k in CoreCharacter.__dataclass_fields__}
        CoreCharacter.__init__(self, **core_fields)
        BaseEntity.__init__(self, **kwargs)
        # Game Character fields
        self.role = kwargs.get("role")
        self.prepared_spells = kwargs.get("prepared_spells", [])
        self.alignment = kwargs.get("alignment")
        self.background = kwargs.get("background")
        self.coins = kwargs.get("coins", 0)
        self.damage_vulnerabilities = kwargs.get("damage_vulnerabilities", [])
        self.damage_resistances = kwargs.get("damage_resistances", [])
        self.damage_immunities = kwargs.get("damage_immunities", [])
        self.condition_advantages = kwargs.get("condition_advantages", [])
        self.condition_immunities = kwargs.get("condition_immunities", [])
        self.senses = kwargs.get("senses", {})
        self.features = kwargs.get("features", [])
        self.class_specific = kwargs.get("class_specific", {})
        self.id = kwargs.get("id")
        if self.id is None:
            self.__post_init__()

    def __post_init__(self):
        super().__post_init__()

    def __repr__(self):
        race_display = self.subrace.name if self.subrace else self.race.name
        return f"{self.name} (Level {self.level} {race_display} {self.class_type.name}, AC {self.armor_class}, HP {self.hit_points}/{self.max_hit_points})"

    @classmethod
    def create_random_character(
        cls,
        name: Optional[str] = None,
        race: Optional[str] = None,
        class_type: Optional[str] = None,
        level: int = 1,
        alignment: Optional[str] = None,
        coins: int = 0,
    ):
        """
        Create a new character with simplified parameters.
        
        Args:
            name: Character name (random if not provided)
            race: Race name: "human", "elf", "dwarf", "halfling" (random if not provided)
            class_type: Class name: "fighter", "wizard", "rogue", "cleric" (random if not provided)
            level: Starting level (default: 1)
            
        Returns:
            Character instance
        """
        # Use the built-in generator
        core_char = simple_character_generator(
            level=level,
            race_name=race,
            class_name=class_type,
            name=name
        )
        
        # Convert to our Character class (same structure, just different type)
        char = cls(
            name=core_char.name,
            race=core_char.race,
            subrace=core_char.subrace,
            ethnic=core_char.ethnic,
            gender=core_char.gender,
            height=core_char.height,
            weight=core_char.weight,
            age=core_char.age,
            class_type=core_char.class_type,
            proficiencies=core_char.proficiencies,
            abilities=core_char.abilities,
            ability_modifiers=core_char.ability_modifiers,
            hit_points=core_char.hit_points,
            max_hit_points=core_char.max_hit_points,
            speed=core_char.speed,
            haste_timer=core_char.haste_timer,
            hasted=core_char.hasted,
            xp=core_char.xp,
            level=core_char.level,
            inventory=core_char.inventory,
            gold=core_char.gold,
            sc=core_char.sc,
            conditions=core_char.conditions,
            st_advantages=core_char.st_advantages,
        )
        # Set additional fields
        char.prepared_spells = []
        char.alignment = alignment
        char.background = None
        char.coins = coins if coins else coin_converter(core_char.gold, "gp")
        
        # Initialize racial features (will be set from race_data in character_builder)
        char.damage_vulnerabilities = []
        char.damage_resistances = []
        char.damage_immunities = []
        char.condition_advantages = []
        char.condition_immunities = []
        char.senses = {}
        
        # Initialize class_specific (will be set from class data in character_builder)
        char.class_specific = {}

        delattr(core_char, "gold")

        return char
