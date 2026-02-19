import uuid
from uuid import UUID
from typing import Optional, Union

# ID can be a readable string (e.g. "tavern-001", "npc-blacksmith-001") or UUID
ID = Union[str, UUID]

# Per-prefix counter for readable id generation (e.g. entity-001, entity-002)
_id_counters: dict[str, int] = {}

def _next_id(prefix: str = "entity") -> str:
    _id_counters[prefix] = _id_counters.get(prefix, 0) + 1
    return f"{prefix}-{_id_counters[prefix]:03d}"


class BaseEntity:
    """Base class for entities. Subclasses (dataclasses) must add:
    id: Optional[ID] = field(default_factory=...)
    as the last field and call super().__post_init__() in __post_init__.
    When id is not set, a readable id is generated using class._id_prefix (e.g. "room-001").
    """
    _id_prefix: str = "entity"

    def __init__(self, **kwargs):
        """Accept kwargs so subclasses with custom __init__ can pass them."""
        pass

    id: Optional[ID] = None

    def __post_init__(self):
        if self.id is None:
            prefix = getattr(self, "_id_prefix", None) or getattr(self.__class__, "_id_prefix", "entity")
            self.id = _next_id(prefix)
        elif isinstance(self.id, UUID):
            # Keep UUID as-is (e.g. from pickle); could normalize to str if you prefer
            pass
        # else: id is already str, keep as-is
