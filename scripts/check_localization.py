#!/usr/bin/env python3
"""
Compare string IDs across game/localization/*.xml (RU ↔ EN parity).

Exit code 0 if every file has the same set of ids as ru.xml (baseline).
Exit code 1 if any language is missing keys or has duplicate ids.

Usage (from repo root):
    python scripts/check_localization.py
"""
from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def _ids_from_file(path: Path) -> tuple[list[str], dict[str, int]]:
    """Return ordered ids and duplicate counts."""
    root = ET.parse(path).getroot()
    seen: dict[str, int] = {}
    order: list[str] = []
    for elem in root.findall("string"):
        sid = elem.get("id")
        if not sid:
            continue
        order.append(sid)
        seen[sid] = seen.get(sid, 0) + 1
    return order, seen


def main() -> int:
    loc_dir = Path(__file__).resolve().parent.parent / "game" / "localization"
    ru_path = loc_dir / "ru.xml"
    if not ru_path.is_file():
        print(f"Baseline missing: {ru_path}", file=sys.stderr)
        return 1

    _, ru_seen = _ids_from_file(ru_path)
    ru_keys = set(ru_seen.keys())
    dup_ru = [k for k, n in ru_seen.items() if n > 1]
    if dup_ru:
        print(f"Duplicate ids in ru.xml: {sorted(dup_ru)}", file=sys.stderr)
        return 1

    errors = False
    for xml_path in sorted(loc_dir.glob("*.xml")):
        if xml_path.name == "ru.xml":
            continue
        _, seen = _ids_from_file(xml_path)
        dup = [k for k, n in seen.items() if n > 1]
        if dup:
            print(f"Duplicate ids in {xml_path.name}: {sorted(dup)}", file=sys.stderr)
            errors = True
            continue
        keys = set(seen.keys())
        missing = sorted(ru_keys - keys)
        extra = sorted(keys - ru_keys)
        if missing or extra:
            errors = True
            if missing:
                print(f"{xml_path.name}: missing vs ru.xml ({len(missing)}): {missing}", file=sys.stderr)
            if extra:
                print(f"{xml_path.name}: extra vs ru.xml ({len(extra)}): {extra}", file=sys.stderr)

    if errors:
        return 1

    print(f"OK: {len(ru_keys)} string ids match across {len(list(loc_dir.glob('*.xml')))} file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
