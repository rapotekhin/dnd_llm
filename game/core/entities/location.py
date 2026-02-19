import dataclasses
import json
from dataclasses import field
from typing import Optional, List
from core.entities.npc import NPC
from core.entities.treasure import Treasure
from core.data.quest import Quest
from core.entities.base import BaseEntity, ID

LOCATION_TYPES = [
    "town",
    "village",
    "countryside",
    "wilderness",
    "road",
    "dungeon",
]

LOCATION_SUBTYPES = [
    # ЖИЛЫЕ
    "house",
    "inn",
    "tavern",

    # ТОРГОВЛЯ
    "market",
    "shop",

    # ПРОИЗВОДСТВО
    "forge",
    "workshop",
    "farm",

    # РЕЛИГИЯ / КУЛЬТЫ
    "church",

    # ВЛАСТЬ / ГОРОД
    "town_hall",
    "guard_post",
    "barracks",
    "prison",
    "watchtower",

    # ПУТЕШЕСТВИЯ
    "road",
    "bridge",
    "crossroad",
    "gate",

    # ПРИРОДА
    "forest",
    "swamp",
    "mountain",
    "hill",
    "river",
    "lake",
    "cave",
    "valley",
    "ruins",

    # ОПАСНЫЕ / ПРИКЛЮЧЕНИЯ
    "dungeon",
    "crypt",
    "catacombs",
    "lair",
    "bandit_camp",
    "battlefield",
    "abandoned_house",
    "haunted_place",
]

@dataclasses.dataclass
class Room(BaseEntity):
    name: str
    level: int
    description: str
    npcs: List[ID] = field(default_factory=list)
    connections: List[ID] = field(default_factory=list)  # connected rooms in location
    treasures: List[ID] = field(default_factory=list)
    id: Optional[ID] = field(default=None)
    location_id: Optional[ID] = None
    can_leave: bool = True  # Can the player leave the location whenever he wants?
    _id_prefix: str = "room"

    def __post_init__(self):
        super().__post_init__()

@dataclasses.dataclass
class IndoorLevel(BaseEntity):
    level_number: int
    level_description: str
    level_type: str  # "basement", "ground", "upper", "attic"
    rooms: List[ID]
    id: Optional[ID] = field(default=None)
    _id_prefix: str = "level"

    def __post_init__(self):
        super().__post_init__()

@dataclasses.dataclass
class Location(BaseEntity):
    name: str
    description: str
    type: str
    subtype: str
    region: str = "Forgotten Realms"
    city: str = "Neverwinter"
    is_indoors: bool = False
    entrance_room_id: Optional[ID] = None

    # indoor parameters
    levels: List[IndoorLevel] = field(default_factory=list)

    connected_locations: List[ID] = field(default_factory=list)
    npcs: List[ID] = field(default_factory=list)
    quests_in_location: List[ID] = field(default_factory=list)

    can_leave: bool = True  # Can the player leave the location whenever he wants?

    location_history_summary: str = ""
    id: Optional[ID] = field(default=None)
    _id_prefix: str = "location"

    def __post_init__(self):
        super().__post_init__()

    def __repr__(self) -> str:
        from core.data import game_state
        description = f"{self.description}" if self.description else ""
        for level in self.levels:
            description += f"\n{level.level_number}: {level.level_description}"
            for room_id in level.rooms:
                room = game_state.rooms.get(room_id)
                if not room:
                    continue
                description += f"\n{room.name}: {room.description}"
                for npc_id in room.npcs:
                    npc = game_state.npcs.get(npc_id)
                    if npc:
                        description += f"\n{npc.name}: {npc.description}"
                for treasure_id in room.treasures:
                    treasure = game_state.treasures.get(treasure_id)
                    if treasure:
                        description += f"\n{treasure.name}: {treasure.description}"
        return f"{self.name} ({self.type} - {self.subtype}): {description}"

    def get_global_location(self) -> str:
        return f"{self.region} - {self.city}"

    def get_treasures(self) -> List[str]:
        from core.data import game_state
        result = []
        for level in self.levels:
            for room_id in level.rooms:
                room = game_state.rooms.get(room_id)
                if not room:
                    continue
                for treasure_id in room.treasures:
                    treasure = game_state.treasures.get(treasure_id)
                    if treasure:
                        result.append(f"At level {level.level_number} in room {room.name} there is {treasure.name} - {treasure.description}")
        return result

    def get_open_quests(self) -> List[Quest]:
        from core.data import game_state
        result = []
        for quest_id in self.quests_in_location:
            if game_state.quests[quest_id].is_open():
                result.append(game_state.quests[quest_id].description)
        return result

    def get_hidden_quests(self) -> List[Quest]:
        from core.data import game_state
        result = []
        for quest_id in self.quests_in_location:
            if game_state.quests[quest_id].is_hidden():
                result.append(f"Hidden quest: {game_state.quests[quest_id].description} - Ways to unhidden: {game_state.quests[quest_id].ways_to_unhidden}")
        return result

    @staticmethod
    def load_from_json(json_path: str) -> "Location":
        with open(json_path, 'r') as f:
            json_data = json.load(f)

        return Location(
            id=json_data["id"],
            name=json_data["name"],
            description=json_data["description"],
            type=json_data["type"],
            subtype=json_data["subtype"],
            region=json_data["region"],
            city=json_data["city"],
            is_indoors=json_data["is_indoors"],
            levels=json_data["levels"],
            connected_locations=json_data["connected_locations"],
            npcs=json_data["npcs"],
            quests_in_location=json_data["quests_in_location"],
            can_leave=json_data["can_leave"],
        )