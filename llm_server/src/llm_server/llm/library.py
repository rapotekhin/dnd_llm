"""Library of generated items (ADR-0008 §6): shared content for all games, not party state.

Items the engine accepted are appended to <data_dir>/items/library.jsonl; find_items searches it next to the
engine catalog. Moving items into the game catalog (tools/promote_items.py) is a later step.
"""

import json
import threading
from pathlib import Path

from ..protocol import FoundItem, GeneratedItem


class ItemLibrary:
    def __init__(self, path: Path):
        self.path = path
        self._lock = threading.Lock()

    def add(self, item_id: str, item: GeneratedItem) -> None:
        with self._lock:
            if any(f.item_id == item_id for f in self._all()):
                return
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with self.path.open("a", encoding="utf-8") as f:
                f.write(json.dumps({"item_id": item_id, **item.model_dump()}, ensure_ascii=False) + "\n")

    def search(self, query: str, base: str | None = None, properties: list[str] | None = None, limit: int = 5) -> list[FoundItem]:
        q = query.lower().strip()
        props = set(properties or [])
        out: list[FoundItem] = []
        for item in self._all():
            if q and q not in item.name.lower() and q not in (item.item_type or ""):
                continue
            if props and not props.issubset(item.properties):
                continue
            out.append(item)
        if base:
            out.sort(key=lambda f: 0 if base in f.item_id or base in f.name.lower() else 1)
        return out[:limit]

    def _all(self) -> list[FoundItem]:
        try:
            lines = self.path.read_text(encoding="utf-8").splitlines()
        except OSError:
            return []
        items: list[FoundItem] = []
        for line in lines:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            items.append(FoundItem(item_id=d["item_id"], name=d["name"], item_type=d.get("item_type", ""),
                                   rarity=d.get("rarity", "common"), value_cp=int(d.get("value_cp", 0)),
                                   properties=list(d.get("properties", [])), source="library"))
        return items
