import dataclasses
from dataclasses import field
from typing import Optional
from core.entities.base import BaseEntity, ID

@dataclasses.dataclass
class Item(BaseEntity):
    _id_prefix: str = "item"
    id: Optional[ID] = field(default=None)

    def __post_init__(self):
        super().__post_init__()