import dataclasses
from dataclasses import field
from typing import List, Optional
from core.entities.item import Item
from core.entities.base import BaseEntity, ID

@dataclasses.dataclass
class Treasure(BaseEntity):
    name: str
    description: str
    value: int  # in copper pieces
    room_id: ID  # Room ID (str or UUID)
    owner: Optional[ID] = None  # NPC ID, if None, then the treasure is not owned by any NPC
    is_looted: bool = False
    is_hidden: bool = False
    difficulty_for_unhidden: int = 0  # 10 - trivial, 12 - easy, 14 - medium, 16 - hard, 20 - deadly
    is_quest_item: bool = False
    connected_quest: Optional[ID] = None
    items: List[Item] = field(default_factory=list)
    id: Optional[ID] = field(default=None)
    _id_prefix: str = "treasure"

    def __post_init__(self):
        super().__post_init__()

if __name__ == "__main__":
    treasure = Treasure(
        name="Test Treasure",
        description="Test Description",
        value=100,
        room_id="room-001",
        owner=None,
        is_looted=False,
        is_hidden=False,
    )
    print(treasure)