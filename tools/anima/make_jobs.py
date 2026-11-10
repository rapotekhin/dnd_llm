"""The jobs of anima_gen.py from the game's data: one icon per item, spell, class feature, race trait, condition,
combat act and group of the inventory. Runs in the repo; the jobs file is what is copied to the machine with Forge.

    python tools/anima/make_jobs.py                  # → tools/anima/jobs/icons.json from subjects.json
    python tools/anima/make_jobs.py --describe       # first ask the model for the subjects not written yet (cents)
    python tools/anima/make_jobs.py --describe --redo items/longsword,spells/fireball

What an icon shows is a subject in English — booru tags and one plain sentence — kept in tools/anima/subjects.json
by "<kind>/<id>". The model writes the missing ones once (OpenRouter, the key from the root .env); the author edits
the file by hand where an icon comes out wrong, and a written subject is never overwritten unless --redo names it.
A subject without a written entry falls back to its English name, which is poor for abstract things.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SUBJECTS = HERE / "subjects.json"
JOBS = HERE / "jobs" / "icons.json"
MODEL = "deepseek/deepseek-v4.1-flash-1017"  # the master's default (llm_server.config.DEFAULT_MODEL)
BATCH = 30

# The Anima card (huggingface.co/circlestone-labs/Anima): lowercase Danbooru tags with spaces, then plain sentences
# that describe the look; it knows anime tags, not D&D names; it is weak at text. The generator adds the quality tags,
# «no humans», the style and the background — the model writes only the object.
ASK = """You write the subject of a small game icon for a fantasy RPG (D&D 5e). The icon is drawn by Anima, an anime
image model, as one minimalist flat-color silhouette on a plain background, and is seen in the game at 32-64 px.
The image prompt is built as: [quality tags] [your tags]. [your sentence] [a fixed style text]. You write only the
object; never write quality, style, background, «icon», «no humans» or «simple background» — they are added.

For each entry give:
- "tags": 3-7 Danbooru tags of the object, lowercase, words separated by spaces (never underscores), comma-separated,
  most important first: the object's own tag (sword, potion, shield, skull, book, scroll, key, ring, boots, fire,
  lightning, snowflake, feather, wolf, moon, eye...), then its parts and colors as Danbooru writes them (red liquid,
  wooden handle, glowing, cork, sheath, crossguard), then its view when it matters (front view, from side, diagonal).
- "sentence": 1-2 plain English sentences, at most 35 words, starting with "A single". Describe how it looks: its
  shape, its 2-3 main colors, how it is turned. Never a name the model cannot know (no D&D, spell or monster proper
  names — not «Bigby's hand», but «a huge blue glowing open hand of force»), never a story or a use.
- "green": true when the object's main color is green (it is then drawn on a magenta background).

Rules:
1. One simple object or emblem with a big readable outline, never a scene, never two objects. Small details vanish
   at 32 px: choose the shape that says what it is.
2. No people: no human, face, hand, arm, body or silhouette of a person. A spell, an ability, a trait, a condition or
   an action is an emblem: an element, a weapon, a tool, an animal or its head, a plant, a gem, a star, an eye, a
   shield, a chain, a geometric magic symbol. An undead or a monster may be a skull or a beast's head.
3. No text, letters, numbers or readable runes: write «glowing magic circle» or «geometric symbol», not «rune with the
   letter».
4. Things alike look alike: every potion is a round or tall glass flask in its liquid's color; every scroll is a
   rolled parchment with a wax seal; armor is the armor piece alone on no body, seen from the front; a +1 or a magic
   weapon is the plain weapon with a soft glow of its element.
5. Colors carry meaning. Damage: fire orange and red, cold light blue and white, lightning yellow, thunder pale blue,
   acid green, poison green and purple, necrotic dark purple and black, radiant gold and white, force violet, psychic
   pink. A spell without damage takes its school: abjuration blue, conjuration teal, divination gold, enchantment
   pink, evocation orange, illusion violet, necromancy dark purple, transmutation green-brown. Healing is green or
   warm white with a small plus sign.

Examples (key → answer):
items/longsword → {"tags": "longsword, sword, steel blade, crossguard, brown handle, diagonal", "sentence": "A single straight steel longsword lying diagonally, blade up and to the right, with a short crossguard and a brown leather grip.", "green": false}
items/chain_mail → {"tags": "chainmail, armor, sleeved shirt, grey metal, front view", "sentence": "A single grey chainmail shirt with short sleeves and a round neck, seen from the front, lying flat with no body inside.", "green": false}
items/healing_potion → {"tags": "potion, round bottle, red liquid, cork, glass", "sentence": "A single round glass flask with a narrow neck, filled with bright red liquid and closed with a brown cork.", "green": false}
items/hempen_rope → {"tags": "rope, coiled rope, hemp, brown", "sentence": "A single coil of thick light-brown hemp rope, wound in a neat circle with one loose end.", "green": false}
items/thieves_tools → {"tags": "lockpick, key ring, small tools, grey metal", "sentence": "A single iron ring holding three thin grey lockpicks and a small hooked pick, fanned out.", "green": false}
spells/fireball → {"tags": "fireball, fire, flame, orange, glowing", "sentence": "A single round ball of orange fire with a bright yellow core and a few flame tongues licking upward.", "green": false}
spells/shield → {"tags": "magic shield, hexagon, barrier, blue, glowing", "sentence": "A single glowing blue hexagonal barrier of light, slightly transparent, with a brighter edge.", "green": false}
spells/cure_wounds → {"tags": "heart, glowing, plus sign, green, sparkle", "sentence": "A single green glowing heart with a small white plus sign in its middle and a few sparkles around it.", "green": true}
features/second_wind → {"tags": "wind, swirl, spiral, plus sign, green", "sentence": "A single green spiral gust of wind curling around a small white plus sign.", "green": true}
features/rage → {"tags": "wolf, wolf head, snarling, fangs, red", "sentence": "A single red snarling wolf head seen from the front, fangs bared, ears back.", "green": false}
features/sneak_attack → {"tags": "dagger, dark, purple glow, diagonal", "sentence": "A single black dagger pointing down diagonally, its edge trailing a thin purple glow.", "green": false}
traits/darkvision → {"tags": "eye, glowing eye, purple, night", "sentence": "A single wide open eye with a glowing violet iris on a dark round field.", "green": false}
conditions/poisoned → {"tags": "skull, poison, drop, green, purple", "sentence": "A single green drop of poison with a small white skull on it.", "green": true}
conditions/prone → {"tags": "arrow, down arrow, grey, broken line", "sentence": "A single thick grey arrow bending down to a flat line, a symbol of falling to the ground.", "green": false}
acts/dash → {"tags": "boot, winged boots, speed lines, brown", "sentence": "A single brown leather boot with a small white wing at the heel and three speed lines behind it.", "green": false}
acts/hide → {"tags": "hood, cloak, dark, shadow, grey", "sentence": "A single empty dark grey hooded cloak, the hood's opening black, with no one inside.", "green": false}
groups/weapon → {"tags": "crossed swords, sword, steel, x shape", "sentence": "A single pair of steel swords crossed in an X, hilts down, as one emblem.", "green": false}

Answer JSON only: {"<key>": {"tags": "...", "sentence": "...", "green": false}, ...} with every key given.
Entries:
"""


def load(p: str) -> dict:
    return json.loads((ROOT / p).read_text(encoding="utf-8"))


def short(text: str, n: int = 220) -> str:
    return re.sub(r"\s+", " ", str(text or ""))[:n]


def entries() -> list[dict]:
    """Every thing that gets an icon: kind, id, the Russian name, the English one, a hint of what it is."""
    out: list[dict] = []
    for iid, it in load("game/data/items.json")["catalog"].items():
        out.append({"kind": "items", "id": iid, "name": it.get("name", iid), "en": it.get("name_en", ""),
                    "hint": " ".join(filter(None, [str(it.get("item_type", "")), str(it.get("base", "") or ""),
                                                   short(it.get("desc", ""), 160)]))})
    for sid, sp in load("game/data/srd/spells.json").items():
        out.append({"kind": "spells", "id": sid, "name": sp.get("name", sid), "en": sp.get("name_en", ""),
                    "hint": f"spell, school {sp.get('school_id', '')}; " + short(sp.get("desc", ""))})
    for fid, f in load("game/data/srd/classes.json")["features"].items():
        out.append({"kind": "features", "id": fid, "name": f.get("name", fid), "en": f.get("name_en", ""),
                    "hint": "class feature; " + short(f.get("desc", ""))})
    for tid, t in load("game/data/srd/races.json")["traits"].items():
        out.append({"kind": "traits", "id": tid, "name": t.get("name", tid), "en": t.get("name_en", ""),
                    "hint": "race trait; " + short(t.get("desc", ""))})
    for cid, c in load("game/data/rules.json")["condition_effects"].items():
        if cid.startswith("_"):
            continue
        out.append({"kind": "conditions", "id": cid, "name": str(c.get("name", cid)), "en": cid.replace("_", " "),
                    "hint": "a condition on a creature or a thing; " + short(json.dumps(c, ensure_ascii=False), 160)})
    for g in load("game/data/rules.json")["item_rules"]["groups"]["rows"]:  # the group buttons of the inventory
        out.append({"kind": "groups", "id": g["id"], "name": g["name"], "en": g["id"],
                    "hint": "a group of things in the inventory, its button shows the whole group"})
    for gd in sorted((ROOT / "game/core/acts").glob("*.gd")):
        if gd.stem == "act":  # the base class of every act
            continue
        text = gd.read_text(encoding="utf-8")
        title = re.search(r'func title\(\)[^:]*:\s*return "([^"]+)"', text)
        tip = re.search(r'func tip\(\)[^:]*:\s*return "([^"]+)"', text)
        out.append({"kind": "acts", "id": gd.stem, "name": title.group(1) if title else gd.stem,
                    "en": gd.stem.replace("_", " "), "hint": "a combat action; " + (tip.group(1) if tip else "")})
    return out


def api_key() -> str:
    key = os.environ.get("OPENROUTER_API_KEY", "")
    env = ROOT / ".env"
    if not key and env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("OPENROUTER_API_KEY="):
                key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        sys.exit("no OPENROUTER_API_KEY in the environment or the root .env")
    return key


def describe(batch: list[dict], key: str) -> dict:
    lines = "\n".join(json.dumps({"key": f"{e['kind']}/{e['id']}", "ru": e["name"], "en": e["en"], "what": e["hint"]},
                                 ensure_ascii=False) for e in batch)
    body = {"model": MODEL, "messages": [{"role": "user", "content": ASK + lines}],
            "response_format": {"type": "json_object"}, "temperature": 0.4,
            "provider": {"only": ["wafer"], "allow_fallbacks": True}}
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}",
                                          "X-Title": "Between the Rolls: icon subjects"})
    with urllib.request.urlopen(req, timeout=300) as resp:
        text = json.load(resp)["choices"][0]["message"]["content"]
    return json.loads(text[text.find("{"):text.rfind("}") + 1])


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--describe", action="store_true", help="ask the model for the subjects not written yet")
    p.add_argument("--redo", default="", help="kind/id,…: describe these again")
    a = p.parse_args()

    all_entries = entries()
    subjects: dict = json.loads(SUBJECTS.read_text(encoding="utf-8")) if SUBJECTS.exists() else {}
    for k in filter(None, a.redo.split(",")):
        subjects.pop(k.strip(), None)
    if a.describe:
        todo = [e for e in all_entries if f"{e['kind']}/{e['id']}" not in subjects]
        key = api_key()
        for i in range(0, len(todo), BATCH):
            batch = todo[i:i + BATCH]
            got = describe(batch, key)
            for e in batch:
                k = f"{e['kind']}/{e['id']}"
                s = got.get(k)
                if isinstance(s, dict) and s.get("tags") and s.get("sentence"):
                    subjects[k] = {"tags": str(s["tags"]), "sentence": str(s["sentence"]), "green": bool(s.get("green"))}
            SUBJECTS.write_text(json.dumps(subjects, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
            print(f"described {min(i + BATCH, len(todo))}/{len(todo)}", flush=True)

    jobs, fallback = [], 0
    for e in all_entries:
        s = subjects.get(f"{e['kind']}/{e['id']}")
        if s is None:
            fallback += 1
            name = (e["en"] or e["id"].replace("_", " ")).lower()
            s = {"tags": name, "sentence": f"A single {name}, a simple emblem.", "green": False}
        jobs.append({"id": e["id"], "kind": e["kind"], "name": e["name"], "tags": s["tags"], "sentence": s["sentence"],
                     "key": "magenta" if s.get("green") else ""})
    JOBS.parent.mkdir(parents=True, exist_ok=True)
    JOBS.write_text(json.dumps({"jobs": jobs}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    kinds: dict[str, int] = {}
    for j in jobs:
        kinds[j["kind"]] = kinds.get(j["kind"], 0) + 1
    print(f"{JOBS.relative_to(ROOT)}: {len(jobs)} icons {kinds}; {fallback} by the bare name")


if __name__ == "__main__":
    main()
