class_name AnimRules
extends RefCounted
## The stub animations of a fight (v0.8.4.23, docs/design/systems/combat-animations.md): which kind a spell, a blow, a miss and a
## lasting state are, by `data/anims.json`, and the events the engine leaves for the interface. How a kind looks is the
## interface's (FightAnims): its phases are stubs until the row's `frames` or `scene` replaces them, with no change of code.
## Anybody's (ADR-0016): what is in the hands is read off any fighter. The look of a miss is cosmetic: a hash of the game's seed
## and the event's number picks it, never `s.rng`, so the dice of the game stay where they were.

const MELEE := "melee"
const SHOT := "shot"
const SPELL := "spell"
const NEAR := "near"
const RANGED_SPRITES: Array[String] = ["bow", "crossbow", "sling"]


static func cfg(data: Dictionary) -> Dictionary:
	return data.get("anims", {})


## Every kind of a group: spell, outcome, strike, defence, move, state.
static func kinds_of(data: Dictionary, group: String) -> Array[String]:
	var out: Array[String] = []
	for k: String in cfg(data)["kinds"]:
		if str(cfg(data)["kinds"][k]["group"]) == group:
			out.append(k)
	return out


## The delivery of a spell: its row of `spells`, else its fields — a master's spell gets one the same way (pillar 6).
static func of_spell(data: Dictionary, id: String) -> String:
	var c := cfg(data)
	if (c["spells"] as Dictionary).has(id):
		return str(c["spells"][id])
	var sp: Dictionary = data["spells"].get(id, {})
	var area := str(sp.get("area", {}).get("type", ""))
	if int(sp.get("range_ft", 0)) <= 0:
		return area if area in ["cone", "line"] else "aura" if area.is_empty() else "nova"
	if int(sp.get("range_ft", 0)) == int(c["rule"]["touch_ft"]):  # "1 миля" is 1 in the data: not a touch
		return "touch"
	var lasting := bool(sp.get("concentration", false)) or not str(sp.get("duration", "")).begins_with(str(c["rule"]["instant"]))
	if not area.is_empty():
		return "zone" if lasting and (not sp.has("damage_at_slot") or bool(sp.get("concentration", false))) else "burst"
	if sp.has("attack"):
		return "bolt" if str(sp["attack"]) == "ranged" else "touch"
	if sp.has("damage_type") or sp.has("save") or sp.has("heal_at_slot") or (data["rules"]["combat"]["spell_targets"] as Dictionary).has(id):
		return "sigil"
	return "aura"


## How a zone of the field looks on its squares (v0.8.4.30): {kind, colour (#hex), moves, texture} of anims.json `surfaces`,
## by the zone's id before «:», its damage type or its tile; {} — a plain tint.
static func surface(data: Dictionary, z: Dictionary) -> Dictionary:
	var c: Dictionary = cfg(data).get("surfaces", {})
	if c.is_empty():
		return {}
	var kind := str(c["spells"].get(str(z.get("spell", "")).get_slice(":", 0), ""))
	if kind.is_empty():
		kind = str(c["types"].get(str(z.get("type", "")), ""))
	if kind.is_empty() and not str(z.get("tile", "")).is_empty():
		kind = str(c["tile"])
	if kind.is_empty() or not (c["kinds"] as Dictionary).has(kind):
		return {}
	var row: Dictionary = c["kinds"][kind]
	var colour := str(row["colour"])
	return {"kind": kind, "colour": colour if colour.begins_with("#") else str(cfg(data)["palette"].get(colour, "#ffffff")),
		"moves": bool(row.get("moves", false)), "texture": str(row.get("texture", ""))}


## The colour key of a spell: its damage, a heal, else magic.
static func spell_colour(data: Dictionary, id: String) -> String:
	var sp: Dictionary = data["spells"].get(id, {})
	if sp.has("heal_at_slot"):
		return "heal"
	return str(sp.get("damage_type", "magic"))


## What a blow looks like: {anim, dtype, proj, sprite}. `t` decides a throw from a strike of the same weapon.
static func of_blow(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary) -> Dictionary:
	var c := cfg(data)
	var pieces: Array = b.get("pieces", [])
	var dtype := str(pieces[0].get("type", "")) if not pieces.is_empty() else ""
	if b.has("spell"):
		return {"anim": of_spell(data, str(b["spell"])), "dtype": dtype if not dtype.is_empty() else "magic", "proj": "", "sprite": ""}
	var a: Dictionary = b.get("act", {})
	var item := str(a.get("item", "")) if not a.is_empty() else str(b.get("id", ""))
	var items: Dictionary = s.items if s != null else {}
	var kind := ItemRules.plain_of(data["items"], items, item)  # a fine storm longsword is a longsword
	var out := {"anim": "", "dtype": dtype, "proj": "", "sprite": sprite_of(data, item, items)}
	if not item.is_empty() and s != null and Attack.shot(f, t, b) and bool(b.get("melee", false)):
		out["anim"] = "throw"  # a dagger or a javelin out of the hand
	elif not item.is_empty() and (c["shots"] as Dictionary).has(kind):
		out["anim"] = "throw" if kind == "dart" else "shot"
		out["proj"] = str(c["shots"][kind])
	elif not item.is_empty() and not str(out["sprite"]).is_empty():
		out["anim"] = str(c["weapon_by_dtype"].get(dtype, "swing"))
	elif not item.is_empty():
		out["anim"] = "throw"  # a net, a thing with no sprite
	elif not a.is_empty():
		out["anim"] = str(c["natural"].get(_plain(str(a.get("name_en", ""))), c["by_dtype"].get(dtype, "punch")))
		if str(out["anim"]) == "shot":
			out["proj"] = "dart"
	else:
		out["anim"] = "punch"  # empty hands: a fist
	return out


## A save action of a template (a breath, a gaze, a song): by its area.
static func of_save(data: Dictionary, a: Dictionary) -> String:
	var area := str(a.get("effect", {}).get("area", {}).get("type", ""))
	return str(cfg(data)["save_by_area"].get(area, "burst"))


## "Claw (Bite in Beast Form)" → "Claw".
static func _plain(name_en: String) -> String:
	return name_en.get_slice(" (", 0)


## The sprite of a thing in the hand by its plain kind through every base, "" — none (an empty hand, a dart, a net).
static func sprite_of(data: Dictionary, item: String, items: Dictionary) -> String:
	return "" if item.is_empty() else str(cfg(data)["weapons"].get(ItemRules.plain_of(data["items"], items, item), ""))


## What a fighter shows on its token: {shield: bool, sprite: "", item: ""}. The hero's hands, anybody's things in a fight.
static func gear(s: GameSession, data: Dictionary, f: Dictionary) -> Dictionary:
	var out := {"shield": false, "sprite": "", "item": ""}
	if Sheet.is_hero(f):
		var c := s.character
		if Guise.has_body(c):
			return out
		var eq: Dictionary = c.get("equipped", {})
		out["shield"] = not CharacterRules.shield_in(eq, data, s.items).is_empty()
		out["item"] = str(eq.get("main_hand", ""))
	else:
		var eq: Dictionary = f.get("equipped", Gear.start(data, Sheet.template_id(data, f))["equipped"])
		out["shield"] = not CharacterRules.shield_in(eq, data, s.items).is_empty()
		var inv: Dictionary = f.get("inventory", {})
		for kind: String in ["melee", "ranged"]:
			var item := str(CombatRules._best_action(data, f, kind).get("item", "")) if not Sheet.template(data, f).is_empty() else ""
			if not item.is_empty() and (inv.is_empty() or int(inv.get(item, 0)) > 0):
				out["item"] = item
				break
	out["sprite"] = sprite_of(data, str(out["item"]), s.items)
	return out


## The looks a miss of `anim` at `t` may take: those its gear allows.
static func defences(s: GameSession, data: Dictionary, t: Dictionary, anim: String) -> Array[String]:
	var c := cfg(data)
	var key := SHOT if anim in ["shot", "throw"] else SPELL if anim == "bolt" else NEAR if str(c["kinds"].get(anim, {}).get("group", "")) == "spell" else MELEE
	var g := gear(s, data, t)
	var out: Array[String] = []
	for d: String in c["misses"][key]:
		var need := str(c["needs"].get(d, ""))
		if need == "shield" and not bool(g["shield"]):
			continue
		if need == "blade" and (str(g["sprite"]).is_empty() or RANGED_SPRITES.has(str(g["sprite"]))):
			continue
		out.append(d)
	return out


## One of `options` by the seed of the game and the event's number: the same game shows the same, the dice are untouched.
static func pick(s: GameSession, options: Array[String], n: int) -> String:
	if options.is_empty():
		return ""
	return options[absi(hash([s.game_seed, n])) % options.size()]


## An event for the interface: {by, to, at, from, act, anim, dtype, result, n, …}; the squares are taken now, as they stand.
static func emit(s: GameSession, ev: Dictionary) -> Dictionary:
	if s.combat.is_empty():
		return ev
	var n := int(s.combat.get("anim_n", 0)) + 1
	s.combat["anim_n"] = n
	ev["n"] = n
	for side: String in ["by", "to"]:
		var id := str(ev.get(side, ""))
		if not id.is_empty() and not ev.has(side + "_at"):
			var f := CombatRules.fighter(s, id)
			if not f.is_empty():
				var at := FightGrid.cell(f)
				ev[side + "_at"] = FightGrid.tag(at)
	var list: Array = s.combat.get("anims", [])
	list.append(ev)
	s.combat["anims"] = list
	return ev


## A blow at `t`: the strike's event, its result put in later by `result`.
static func blow(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, b: Dictionary) -> Dictionary:
	var look := of_blow(s, data, f, t, b)
	var act := "cast" if b.has("spell") else SHOT if str(look["anim"]) in ["shot", "throw"] else MELEE
	if b.has("spell"):
		return spell_at(s, data, str(b["spell"]), f, t)
	return emit(s, {"by": str(f["id"]), "to": str(t["id"]), "act": act, "anim": look["anim"], "dtype": look["dtype"], "proj": look["proj"],
		"sprite": look["sprite"], "spell": str(b.get("spell", "")), "result": ""})


## A dart or a ray of a spell at `t`: the first lands on the cast already shown, each next one flies by itself.
static func spell_at(s: GameSession, data: Dictionary, spell: String, f: Dictionary, t: Dictionary) -> Dictionary:
	var open := _open_cast(s, spell, str(t["id"]))
	if not open.is_empty():
		return open
	return emit(s, {"by": str(f["id"]), "to": str(t["id"]), "act": "cast", "anim": of_spell(data, spell), "dtype": spell_colour(data, spell),
		"spell": spell, "result": "", "again": true})


## The cast event of this spell at this target still without a result: a spell's attack roll lands on the cast already shown.
static func _open_cast(s: GameSession, spell: String, to: String) -> Dictionary:
	var list: Array = s.combat.get("anims", [])
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		if str(e.get("act")) == "cast" and str(e.get("spell")) == spell and str(e.get("result", "")).is_empty() and str(e.get("to", "")) in [to, ""]:
			e["to"] = to
			return e
	return {}


## The result of a blow: hit, crit or miss; a miss takes one of the looks the target's gear allows.
static func result(s: GameSession, data: Dictionary, ev: Dictionary, t: Dictionary, res: String) -> void:
	if ev.is_empty():
		return
	ev["result"] = res
	if res == "miss":
		ev["miss"] = pick(s, defences(s, data, t, str(ev["anim"])), int(ev.get("n", 0)))


## A spell is cast: its delivery at a fighter, a square or itself, with the squares of its area as they are laid now.
static func cast(s: GameSession, data: Dictionary, f: Dictionary, spell: String, to: String) -> Dictionary:
	var ev := {"by": str(f["id"]), "act": "cast", "anim": of_spell(data, spell), "dtype": spell_colour(data, spell), "spell": spell, "result": ""}
	if FightGrid.is_aim(to):
		var at := FightGrid.aim_of(to)
		ev["at"] = FightGrid.tag(at)
	elif not to.is_empty():
		ev["to"] = to
	var sp: Dictionary = data["spells"].get(spell, {})
	if sp.has("area") and not s.combat.is_empty():
		var t := CombatRules.aimed(s, to) if not to.is_empty() else f
		if not t.is_empty():
			ev["cells"] = FightGrid.pack_cells(CombatRules.area_cells(s, data, sp, t))
	return emit(s, ev)


## A breath, a gaze or a song of a template: its area at `t`.
static func breath(s: GameSession, data: Dictionary, f: Dictionary, t: Dictionary, a: Dictionary) -> Dictionary:
	var pieces: Array = a.get("damage", [])
	var ev := {"by": str(f["id"]), "to": str(t["id"]), "act": "cast", "anim": of_save(data, a), "result": "hit",
		"dtype": str(pieces[0].get("type", "magic")) if not pieces.is_empty() else "magic"}
	if not a.get("effect", {}).get("area", {}).is_empty():
		ev["cells"] = FightGrid.pack_cells(CombatRules.monster_area(s, data, f, a, FightGrid.cell(t)))
	return emit(s, ev)


## An act of the field by its row of `acts` (a feature by `features`): before it runs, so it is seen before what comes of it.
static func act(s: GameSession, data: Dictionary, f: Dictionary, id: String, to: String, how: Dictionary) -> Dictionary:
	var c := cfg(data)
	var anim := str(c["acts"].get(id, ""))
	if id == "feature" and not how.has("answer"):
		anim = str(c["features"].get(str(how.get("id", "_stock")) if not how.has("stock") else "_stock", "aura"))
	if anim.is_empty() or s.combat.is_empty():
		return {}
	var ev := {"by": str(f["id"]), "act": "move", "anim": anim, "dtype": "magic", "result": "", "sprite": str(gear(s, data, f)["sprite"])}
	if how.has("at"):
		var at := FightGrid.aim_of(str(how["at"]))
		ev["at"] = FightGrid.tag(at)
	if not to.is_empty() and not FightGrid.is_aim(to) and not CombatRules.fighter(s, to).is_empty():
		ev["to"] = to
	return emit(s, ev)


## What came of it on one fighter: impact, crit, heal, buff, debuff, resist.
static func outcome(s: GameSession, who: Dictionary, anim: String, dtype: String = "") -> Dictionary:
	if who.is_empty() or not who.has("id"):
		return {}
	return emit(s, {"to": str(who["id"]), "act": "outcome", "anim": anim, "dtype": dtype if not dtype.is_empty() else anim, "result": anim})


## A move or an act of the body: step, jump, push, pull, fall, rise, vanish, drink, talk, swap. `from` — the square it left.
static func move(s: GameSession, f: Dictionary, anim: String, to: Dictionary = {}, from: Vector2i = FightGrid.NONE) -> Dictionary:
	var ev := {"by": str(f["id"]), "act": "move", "anim": anim, "result": ""}
	if not to.is_empty():
		ev["to"] = str(to["id"])
	if from != FightGrid.NONE:
		ev["from"] = FightGrid.tag(from)
	return emit(s, ev)


static func take(s: GameSession) -> Array:
	var list: Array = s.combat.get("anims", [])
	s.combat.erase("anims")
	return list


## The lasting states of a fighter, for its token: kinds of the group "state".
static func states(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var me := Sheet.holder(s, f)
	var status := str(f.get("status", "active"))
	if status == "dead":
		return ["dead"]
	var down := int(me.get("hp", 1)) <= 0 if Sheet.is_hero(f) else status in ["down", "unconscious"]
	if down:
		return ["down"]
	if bool(f.get("hidden", false)):
		out.append("hidden")
	if ConditionRules.has(me, "invisible"):
		out.append("invisible")
	if ConditionRules.has(me, "prone"):
		out.append("prone")
	if ConditionRules.has(me, "grappled") or ConditionRules.has(me, "restrained"):
		out.append("grappled")
	if Move.air(s, data, f):
		out.append("flying")
	if not str(me.get("concentration", f.get("concentration", ""))).is_empty():
		out.append("concentrating")
	if bool(f.get("dodging", false)):
		out.append("dodging")
	if bool(f.get("raging", false)):
		out.append("raging")
	return out
