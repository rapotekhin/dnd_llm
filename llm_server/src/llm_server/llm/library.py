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

    def get(self, item_id: str) -> GeneratedItem | None:
        try:
            lines = self.path.read_text(encoding="utf-8").splitlines()
        except OSError:
            return None
        for line in lines:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("item_id") == item_id:
                d.pop("item_id")
                try:
                    return GeneratedItem.model_validate(d)
                except ValueError:
                    return None
        return None

    def search(self, query: str, base: str | None = None, properties: list[str] | None = None, limit: int = 5) -> list[FoundItem]:
        """By words (v0.7.18): any word of the query, by its stem, in the name, the type or the properties; the best
        matches first."""
        words = [w[:5] for w in query.lower().replace("ё", "е").split() if len(w) >= 3]
        props = set(properties or [])
        scored: list[tuple[int, FoundItem]] = []
        for item in self._all():
            if props and not props.issubset(item.properties):
                continue
            hay = " ".join([item.name.lower().replace("ё", "е"), item.item_type or "", *item.properties])
            score = sum(1 for w in words if w in hay)
            if base and (base in item.item_id or base in item.name.lower()):
                score += 2
            if words and score == 0:
                continue
            scored.append((score, item))
        scored.sort(key=lambda x: -x[0])
        return [item for _, item in scored[:limit]]

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
                                   properties=list(d.get("properties", [])), power=power_of(d), source="library"))
        return items


def power_of(d: dict) -> list[str]:
    """What a made thing does beyond its properties, as the engine's ItemRules.power_of says it (v0.8.4.42.16, the
    author's trace: a stealth amulet listed by its properties alone was taken for an amulet of invisibility)."""
    out: list[str] = []
    for k, v in (d.get("wear") or {}).items():
        out.append(f"носящему {v}" if k == "status" else f"носящему {k}" if isinstance(v, bool) else f"носящему {k} {v}")
    use = {k: v for k, v in (d.get("use") or {}).items() if v is not None}
    if use:
        out.append(f"при использовании: заклинание {use['spell']}{'' if use.get('charges') else ' (свиток)'}" if use.get("spell")
                   else "при использовании: " + ", ".join(use))
    for sp in d.get("spells") or []:
        out.append(f"заклинание {sp.get('spell', '')} ×{int(sp.get('uses', 1))} за долгий отдых")
    if d.get("hit"):
        out.append(f"при попадании: {d['hit'].get('cond', '')}")
    return out
