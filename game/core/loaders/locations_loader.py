# Load Locations from JSONL file stored in assets/ru/start_locations.jsonl

from core.utils.load_functions import load_jsonl_file
from core.entities.location import Location, IndoorLevel, Room
from core.entities.treasure import Treasure

def load_locations_from_jsonl(file_path: str):
    """Load Locations from JSONL file and add them to game_state.locations"""
    from core.data import game_state

    if game_state.locations is None:
        assert False, "game_state.locations is not initialized"

    locations = load_jsonl_file(file_path)
    for location in locations:
        # Build levels with room id lists; then we'll fill game_state.levels and .rooms
        levels_data = location["levels"]
        level_objs = []
        for level in levels_data:
            room_ids = [room["id"] for room in level["rooms"]]
            lvl = IndoorLevel(
                id=level["id"],
                level_number=level["level_number"],
                level_description=level["level_description"],
                level_type=level["level_type"],
                rooms=room_ids,
            )
            level_objs.append(lvl)
            game_state.levels[level["id"]] = lvl
            for room in level["rooms"]:
                rm = Room(
                    id=room["id"],
                    location_id=location["id"],
                    name=room["name"],
                    level=room["level"],
                    can_leave=room["can_leave"],
                    description=room["description"],
                    npcs=list(room["npcs"]),
                    connections=list(room["connections"]),
                    treasures=[t["id"] if isinstance(t, dict) else t for t in room["treasures"]],
                )
                game_state.rooms[room["id"]] = rm
                for treasure in room["treasures"]:
                    tr = Treasure(
                        id=treasure["id"],
                        name=treasure["name"],
                        description=treasure["description"],
                        value=treasure["value"],
                        room_id=room["id"],
                        owner=treasure.get("owner"),
                        is_looted=treasure.get("is_looted", False),
                        is_hidden=treasure.get("is_hidden", False),
                        difficulty_for_unhidden=treasure.get("difficulty_for_unhidden", 0),
                        is_quest_item=treasure.get("is_quest_item", False),
                        connected_quest=treasure.get("connected_quest"),
                        items=treasure.get("items", []),
                    )
                    game_state.treasures[treasure["id"]] = tr

        loc = Location(
            id=location["id"],
            name=location["name"],
            description=location["description"],
            type=location["type"],
            subtype=location["subtype"],
            region=location["region"],
            city=location["city"],
            is_indoors=location["is_indoors"],
            entrance_room_id=location.get("entrance_room_id"),
            levels=level_objs,
            connected_locations=list(location["connected_locations"]),
            npcs=list(location["npcs"]),
            quests_in_location=list(location["quests_in_location"]),
            can_leave=location["can_leave"],
        )
        game_state.locations[location["id"]] = loc