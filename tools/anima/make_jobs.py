"""The jobs of anima_gen.py from the game's data: one icon per item, spell, class feature, race trait, condition,
combat act and group of the inventory. Runs in the repo; the jobs file is what is copied to the machine with Forge.

    python tools/anima/make_jobs.py                  # → tools/anima/jobs/icons.json from subjects.json
    python tools/anima/make_jobs.py --describe       # first ask the model for the subjects not written yet (cents)
    python tools/anima/make_jobs.py --describe --redo items/longsword,spells/fireball
    python tools/anima/make_jobs.py --portraits --describe   # → jobs/portraits.json: people and monsters

Portraits (v0.8.4.43.5): a person's look is built from the tables of tools/anima/portraits.json by race, sex and age,
5 looks each (a child 1), no model; a monster's look is a subject the model writes once from its SRD template
(«portraits/monsters/<id>» in subjects.json), its 5 variants are 5 seeds, an ordinary person of a monster template
(a bandit, a guard) a man in some and a woman in the others.

What an icon shows is a subject in English — booru tags and one plain sentence — kept in tools/anima/subjects.json
by "<kind>/<id>". The model writes the missing ones once (OpenRouter, the key from the root .env); the author edits
the file by hand where an icon comes out wrong, and a written subject is never overwritten unless --redo names it.
A subject without a written entry falls back to its English name, which is poor for abstract things.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SUBJECTS = HERE / "subjects.json"
JOBS = HERE / "jobs" / "icons.json"
LOOKS = HERE / "portraits.json"
PORTRAIT_JOBS = HERE / "jobs" / "portraits.json"
PICKS = HERE / "picks.json"
FRAME = "portrait, upper body, looking at viewer"  # the tags of a person's portrait after its sex and age
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
- "dark": true when the object's main color is black or very dark (it is then drawn on grey, not on dark).

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
6. The icon sits on a dark slot: never make the whole object black or very dark — a black or dark thing is drawn in
   slate grey or a lighter tone of its color with one bright detail (eyes, a glow, an edge). Chain armor is covered in
   a clear pattern of small interlocking rings, or it reads as a cloth shirt.
7. Never tag a bigger thing the object belongs to: a crossbow bolt is «short arrow», not «crossbow»; a speech bubble
   or a zigzag in a rounded square reads as an app logo — choose another emblem.

Examples (key → answer):
items/longsword → {"tags": "longsword, sword, steel blade, crossguard, brown handle, diagonal", "sentence": "A single straight steel longsword lying diagonally, blade up and to the right, with a short crossguard and a brown leather grip.", "dark": false}
items/chain_mail → {"tags": "chainmail, armor, sleeved shirt, grey metal, front view", "sentence": "A single grey chainmail shirt with short sleeves and a round neck, seen from the front, lying flat with no body inside.", "dark": false}
items/healing_potion → {"tags": "potion, round bottle, red liquid, cork, glass", "sentence": "A single round glass flask with a narrow neck, filled with bright red liquid and closed with a brown cork.", "dark": false}
items/hempen_rope → {"tags": "rope, coiled rope, hemp, brown", "sentence": "A single coil of thick light-brown hemp rope, wound in a neat circle with one loose end.", "dark": false}
items/thieves_tools → {"tags": "lockpick, key ring, small tools, grey metal", "sentence": "A single iron ring holding three thin grey lockpicks and a small hooked pick, fanned out.", "dark": false}
spells/fireball → {"tags": "fireball, fire, flame, orange, glowing", "sentence": "A single round ball of orange fire with a bright yellow core and a few flame tongues licking upward.", "dark": false}
spells/shield → {"tags": "magic shield, hexagon, barrier, blue, glowing", "sentence": "A single glowing blue hexagonal barrier of light, slightly transparent, with a brighter edge.", "dark": false}
spells/cure_wounds → {"tags": "heart, glowing, plus sign, green, sparkle", "sentence": "A single green glowing heart with a small white plus sign in its middle and a few sparkles around it.", "dark": false}
features/second_wind → {"tags": "wind, swirl, spiral, plus sign, green", "sentence": "A single green spiral gust of wind curling around a small white plus sign.", "dark": false}
features/rage → {"tags": "wolf, wolf head, snarling, fangs, red", "sentence": "A single red snarling wolf head seen from the front, fangs bared, ears back.", "dark": false}
features/sneak_attack → {"tags": "dagger, dark, purple glow, diagonal", "sentence": "A single black dagger pointing down diagonally, its edge trailing a thin purple glow.", "dark": true}
traits/darkvision → {"tags": "eye, glowing eye, purple, night", "sentence": "A single wide open eye with a glowing violet iris on a dark round field.", "dark": false}
conditions/poisoned → {"tags": "skull, poison, drop, green, purple", "sentence": "A single green drop of poison with a small white skull on it.", "dark": false}
conditions/prone → {"tags": "arrow, down arrow, grey, broken line", "sentence": "A single thick grey arrow bending down to a flat line, a symbol of falling to the ground.", "dark": false}
acts/dash → {"tags": "boot, winged boots, speed lines, brown", "sentence": "A single brown leather boot with a small white wing at the heel and three speed lines behind it.", "dark": false}
acts/hide → {"tags": "hood, cloak, dark, shadow, grey", "sentence": "A single empty dark grey hooded cloak, the hood's opening black, with no one inside.", "dark": true}
groups/weapon → {"tags": "crossed swords, sword, steel, x shape", "sentence": "A single pair of steel swords crossed in an X, hilts down, as one emblem.", "dark": false}

Answer JSON only: {"<key>": {"tags": "...", "sentence": "...", "dark": false}, ...} with every key given.
Entries:
"""

ASK_MONSTER = """You write the subject of a character portrait of a creature for a fantasy RPG (D&D 5e). Anima, an
anime image model, paints it as a head-and-shoulders portrait in a soft painterly style on a dark muted background;
the game shows it as a round token of 48-64 px and in the creature's card. The image prompt is built as: [quality
tags] [your tags]. [your sentence] [a fixed portrait text]. You write only the creature; never write quality, style,
background, «portrait» or framing — they are added.

For each entry give:
- "tags": 5-9 Danbooru tags, lowercase, words separated by spaces (never underscores), comma-separated: first
  «no humans» for any creature that is not an ordinary person, then the creature's own tag (wolf, bear, giant spider,
  dragon, skeleton, zombie, goblin, orc, ghost, slime, rat, eagle, horse...), then its colors and features as Danbooru
  writes them (grey fur, yellow eyes, fangs, horns, green skin, glowing eyes, tattered cloak), then what it wears
  (leather armor, hood, helmet, chainmail, robe).
- "sentence": 1-2 plain English sentences, at most 40 words, starting with "A". How its head and upper body look: the
  shape, 2-3 main colors, the eyes, what it wears. Never a name the model cannot know (not «owlbear» alone, but «a huge
  bear with the head of an owl, a hooked yellow beak and brown feathers»), never a story or an action scene.
- "person": true when it is an ordinary person of a human-like people (a bandit, a guard, a priest, a knight, a mage,
  a noble, a commoner, a cultist, a scout, a spy, a druid, a berserker, a werewolf or a wererat in human form). Then
  write it with no sex: no beard, no «he» or «she», no «man» or «woman» — write {person} where it goes («A {person}
  in a hooded dark leather jerkin, a scarf over the mouth»), and no «no humans» tag: it is drawn as a man in some
  variants and as a woman in the others. A creature of another people (goblin, orc, gnoll, kobold, hobgoblin,
  bugbear, lizardfolk, drow, duergar, deep gnome) is not a person: it is drawn as itself, with its own sex if any.

Rules:
1. One creature, its head and chest filling the frame. A big beast or a dragon: its head and neck. A swarm: a tight
   cluster of a few of its animals. A creature with no face (an ooze, an elemental, a will-o'-wisp, a shrub): its body
   as one mass with a clear center.
2. Frightening is fine, gore is not: no blood, no open wounds, no guts.
3. Things alike look alike: every skeleton is bare off-white bone, every zombie grey-green rotting skin in rags, every
   ghost pale and translucent; a dragon wyrmling is a young dragon of its color (a red wyrmling red, a brass one
   brass); a werewolf hybrid is a wolf-headed humanoid in fur, its wolf form a plain wolf.

Examples (key → answer):
portraits/monsters/wolf → {"tags": "no humans, wolf, grey fur, yellow eyes, fangs, snarling", "sentence": "A grey wolf with thick fur, pricked ears and amber yellow eyes, lips drawn back from white fangs.", "person": false}
portraits/monsters/goblin → {"tags": "no humans, goblin, green skin, pointy ears, yellow eyes, sharp teeth, leather armor", "sentence": "A small green-skinned goblin with long pointed ears, yellow eyes, a wide grin of sharp teeth and scraps of dirty leather armor.", "person": false}
portraits/monsters/guard → {"tags": "chainmail, helmet, spear, tabard, blue tabard", "sentence": "A {person} of the town watch in a chainmail shirt under a blue tabard, an open steel helmet and the shaft of a spear at the shoulder.", "person": true}

Answer JSON only: {"<key>": {"tags": "...", "sentence": "...", "person": false}, ...} with every key given.
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
    icons = load("game/data/icons.json")
    for uid, what in icons["ui"].items():  # the interface's own buttons: the value is what to draw
        if not uid.startswith("_"):
            out.append({"kind": "ui", "id": uid, "name": what, "en": uid.replace("_", " "),
                        "hint": f"a button of the game's interface; draw: {what}"})
    marks = {"elements": "a damage type", "materials": "a material of a weapon or armor", "shapes": "a spell's area"}
    for what, hint in marks.items():  # small marks over an icon's corner: marks/<what>/<id>.png
        for mid in icons[what]:
            if not mid.startswith("_"):
                out.append({"kind": f"marks/{what}", "id": mid, "name": mid, "en": mid,
                            "hint": f"a tiny mark of {hint} drawn over the corner of another icon: one bold simple "
                                    f"emblem readable at 16 px, colored {icons[what][mid]}"})
    return out


# --- portraits ------------------------------------------------------------------------------------------------------


def monster_entries() -> list[dict]:
    """Every monster template the game reads (not in rules.off.monsters), with a hint of how it looks."""
    off = set(load("game/data/rules.json")["off"]["monsters"])
    out = []
    for mid, m in load("game/data/srd/monsters.json").items():
        if mid in off:
            continue
        acts = [str(x.get("name_en") or x.get("name", "")) for x in m.get("actions", [])][:4]
        traits = [str(t.get("id", "")).replace("_", " ") for t in m.get("traits", [])][:4]
        out.append({"kind": "portraits/monsters", "id": mid, "name": m.get("name", mid), "en": m.get("name_en", ""),
                    "hint": f"{m.get('size', '')} {m.get('type', '')}; wears {', '.join(m.get('equipment', [])) or 'nothing'}; "
                            f"attacks {', '.join(acts) or 'none'}; traits {', '.join(traits) or 'none'}"})
    return out


def _pick(seed: str, options: list, i: int):
    """The i-th of a fixed shuffle: the variants of one portrait take different options, the same on every run."""
    opts = list(options)
    random.Random(seed).shuffle(opts)
    return opts[i % len(opts)] if opts else ""


def _a(phrase: str) -> str:
    """The phrase with its article: «an elf», «a short beard», «stubble», «leather armor»."""
    if phrase.split()[0] in ("stubble", "sideburns") or phrase.endswith("armor"):
        return phrase
    return ("an " if phrase[0] in "aeiou" else "a ") + phrase


def person_look(t: dict, rid: str, sex: str, age_id: str, i: int) -> dict:
    """The tags and the sentence of variant i of a person of race `rid`, sex and age by the tables of portraits.json."""
    race, age = t["races"][rid], t["ages"][age_id]
    base = f"{rid}/{sex}/{age_id}"
    own_sex = race.get("sex", {}).get(sex)
    head = ", ".join(filter(None, [own_sex, race.get("ages", {}).get(age_id, "")])) if own_sex else age[sex]["tags"]
    tags, says = [head, FRAME, race["tags"]], []
    if race.get("hair") is not None:
        color = age.get("hair") or _pick(base + "/hair", race["hair"], i)
        styles = t["styles"][sex] + (t["styles"]["bald"] if age.get("bald") and sex == "male" else [])
        style = _pick(base + "/style", styles, i)
        tags += [style["tag"]] if style.get("bald") else [color, style["tag"]]
        says.append(style["say"] if style.get("bald") else f"{color} {style['say']}")
    eyes, skin = _pick(base + "/eyes", race["eyes"], i), _pick(base + "/skin", race["skin"], i)
    tags += [eyes, skin]
    says += [eyes, skin]
    if sex == "male" and age.get("beard", True) and not age.get("minor"):
        beard = _pick(base + "/beard", race.get("beards", t["beards"]), i)
        if beard:
            tags.append(beard)
            says.append(_a(beard.split(",")[0]))
    kind = age.get("clothes", "any")
    wear = t["clothes"][kind] + ([] if kind == "child" else t["clothes"].get(sex, []))
    cloth = f"{_pick(base + '/color', t['colors'], i)} {_pick(base + '/clothes', wear, i)}"
    tags.append(cloth)
    pron = "He" if sex == "male" else "She"
    sentence = (f"{_a(race['word'] + ' ' + age[sex]['who']).capitalize()}, with {', '.join(says[:-1])} and "
                f"{says[-1]}, wearing {_a(cloth)}.")
    feats = race.get("features")
    if isinstance(feats, dict):  # by sex, a minor's own: a dwarf woman's or child's face is no weathered man's
        feats = feats.get("minor") if age.get("minor") and feats.get("minor") else feats.get(sex)
    if feats:
        sentence += f" {pron} has {feats}."
    if race.get("grown") and not age.get("minor"):
        sentence += f" {pron} is a grown-up of a small folk with adult proportions and an adult face."
    return {"tags": ", ".join(x for x in tags if x), "sentence": sentence}


def people_jobs() -> list[dict]:
    """One job per race, sex and age of the engine (rules.body.age), its looks one per variant."""
    t = json.loads(LOOKS.read_text(encoding="utf-8"))
    races, ages = load("game/data/srd/races.json")["races"], load("game/data/rules.json")["body"]["age"]
    jobs = []
    for rid in races:
        for sex in ("male", "female"):
            for age_id, words in ages.items():
                age = t["ages"][age_id]
                n = int(age.get("variants", t["variants"]))
                job = {"id": f"{rid}/{sex}/{age_id}", "kind": "portraits/people", "style": "portrait",
                       "name": f"{races[rid]['name']}, {words[sex]}", "seeds": t["seeds"][:n],
                       "looks": [person_look(t, rid, sex, age_id, i) for i in range(n)]}
                if age.get("minor"):  # the negative against children of the event images, minus what draws this one
                    job["neg_drop"], job["neg_add"] = age.get("neg_drop", []), t["minor_neg"]
                jobs.append(job)
    return jobs


def monster_jobs(subjects: dict) -> tuple[list[dict], int]:
    seeds = json.loads(LOOKS.read_text(encoding="utf-8"))["seeds"]
    jobs, fallback = [], 0
    for e in monster_entries():
        s = subjects.get(f"{e['kind']}/{e['id']}")
        if s is None:
            fallback += 1
            s = {"tags": f"no humans, {e['en'].lower()}", "sentence": f"A {e['en'].lower()}.", "person": False}
        job = {"id": e["id"], "kind": e["kind"], "name": e["name"], "style": "portrait", "seeds": seeds}
        if s.get("person"):  # an ordinary person: a man in the odd variants, a woman in the even ones
            job["looks"] = [{"tags": f"{'1boy, solo, man' if n % 2 == 0 else '1girl, solo, woman'}, {FRAME}, {s['tags']}",
                             "sentence": s["sentence"].replace("{person}", "man" if n % 2 == 0 else "woman")}
                            for n in range(len(seeds))]
        else:
            solo = "" if "swarm" in e["id"] else "solo, "
            job["tags"], job["sentence"] = f"{solo}portrait, looking at viewer, {s['tags']}", s["sentence"]
        jobs.append(job)
    return jobs, fallback


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


def describe(batch: list[dict], key: str, ask: str = ASK) -> dict:
    lines = "\n".join(json.dumps({"key": f"{e['kind']}/{e['id']}", "ru": e["name"], "en": e["en"], "what": e["hint"]},
                                 ensure_ascii=False) for e in batch)
    body = {"model": MODEL, "messages": [{"role": "user", "content": ask + lines}],
            "response_format": {"type": "json_object"}, "temperature": 0.4,
            "provider": {"only": ["wafer"], "allow_fallbacks": True}}
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}",
                                          "X-Title": "Between the Rolls: icon subjects"})
    for attempt in range(3):  # an empty or broken answer now and then: ask again, then leave the batch for the next run
        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                text = json.load(resp)["choices"][0]["message"]["content"] or ""
            return json.loads(text[text.find("{"):text.rfind("}") + 1])
        except (OSError, ValueError, KeyError, IndexError) as exc:
            print(f"  attempt {attempt + 1}: {str(exc)[:120]}", flush=True)
    return {}


def key_of(s: dict) -> str:
    """The background of a job: the author's own `key`, else grey for a dark object (the dark background's cut would
    eat its edge), else the generator's dark one. A black or dark grey object by its sentence too: the
    model's flag misses some."""
    if s.get("key"):
        return str(s["key"])
    dark = bool(s.get("dark")) or bool(re.search(r"\b(black|dark grey|dark gray)\b", s["sentence"].lower()))
    return "grey" if dark else ""


def reseeded(jobs: list[dict]) -> list[dict]:
    """A variant drawn badly by chance gets another seed: «<kind>/<id>__<n>»: seed in `reseed` of picks.json; anima_gen
    draws it again, as its raw frame of that seed is not there yet."""
    reseed = json.loads(PICKS.read_text(encoding="utf-8")).get("reseed", {}) if PICKS.exists() else {}
    for j in jobs:
        seeds = list(j["seeds"])
        for n in range(1, len(seeds) + 1):
            seeds[n - 1] = int(reseed.get(f"{j['kind']}/{j['id']}__{n}", seeds[n - 1]))
        j["seeds"] = seeds
    return jobs


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--describe", action="store_true", help="ask the model for the subjects not written yet")
    p.add_argument("--redo", default="", help="kind/id,…: describe these again")
    p.add_argument("--portraits", action="store_true", help="the portraits of people and monsters → jobs/portraits.json")
    a = p.parse_args()

    all_entries = monster_entries() if a.portraits else entries()
    subjects: dict = json.loads(SUBJECTS.read_text(encoding="utf-8")) if SUBJECTS.exists() else {}
    for k in filter(None, a.redo.split(",")):
        subjects.pop(k.strip(), None)
    if a.describe:
        todo = [e for e in all_entries if f"{e['kind']}/{e['id']}" not in subjects]
        key = api_key()
        for i in range(0, len(todo), BATCH):
            batch = todo[i:i + BATCH]
            got = describe(batch, key, ASK_MONSTER if a.portraits else ASK)
            for e in batch:
                k = f"{e['kind']}/{e['id']}"
                s = got.get(k)
                if isinstance(s, dict) and s.get("tags") and s.get("sentence"):
                    flag = "person" if a.portraits else "dark"
                    subjects[k] = {"tags": str(s["tags"]), "sentence": str(s["sentence"]), flag: bool(s.get(flag))}
            SUBJECTS.write_text(json.dumps(subjects, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
            print(f"described {min(i + BATCH, len(todo))}/{len(todo)}", flush=True)

    if a.portraits:
        people = reseeded(people_jobs())
        monsters, fallback = monster_jobs(subjects)
        monsters = reseeded(monsters)
        PORTRAIT_JOBS.parent.mkdir(parents=True, exist_ok=True)
        PORTRAIT_JOBS.write_text(json.dumps({"jobs": people + monsters}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        frames = sum(len(j["seeds"]) for j in people + monsters)
        print(f"{PORTRAIT_JOBS.relative_to(ROOT)}: {len(people)} people and {len(monsters)} monsters, {frames} portraits; "
              f"{fallback} monsters by the bare name")
        return

    jobs, fallback = [], 0
    for e in all_entries:
        s = subjects.get(f"{e['kind']}/{e['id']}")
        if s is None:
            fallback += 1
            name = (e["en"] or e["id"].replace("_", " ")).lower()
            s = {"tags": name, "sentence": f"A single {name}, a simple emblem."}
        jobs.append({"id": e["id"], "kind": e["kind"], "name": e["name"], "tags": s["tags"], "sentence": s["sentence"],
                     "key": key_of(s)})
    JOBS.parent.mkdir(parents=True, exist_ok=True)
    JOBS.write_text(json.dumps({"jobs": jobs}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    kinds: dict[str, int] = {}
    for j in jobs:
        kinds[j["kind"]] = kinds.get(j["kind"], 0) + 1
    print(f"{JOBS.relative_to(ROOT)}: {len(jobs)} icons {kinds}; {fallback} by the bare name")


if __name__ == "__main__":
    main()
