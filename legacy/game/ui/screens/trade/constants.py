"""Trade screen constants and layout helpers."""
from localization import loc

SB_W = 10
SB_PAD = 3

SLOTS = [
    ("head",       "inv_head",       []),
    ("body",       "inv_body",       ["armor"]),
    ("hands",      "inv_hands",      []),
    ("feet",       "inv_feet",       []),
    ("cloak",      "inv_cloak",      []),
    ("amulet",     "inv_amulet",     ["amulet"]),
    ("ring_1",     "inv_ring_1",     ["ring"]),
    ("ring_2",     "inv_ring_2",     ["ring"]),
    ("left_hand",  "inv_left_hand",  ["weapon", "armor"]),
    ("right_hand", "inv_right_hand", ["weapon"]),
]


def _sc(v: float, s: float) -> int:
    return max(1, int(v * s))


def _slot_label(loc_key: str) -> str:
    try:
        return loc[loc_key]
    except Exception:
        return loc_key.replace("inv_", "").replace("_", " ").capitalize()
