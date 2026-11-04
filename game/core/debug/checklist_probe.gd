class_name ChecklistProbe
extends RefCounted
## One automatic check per row of the author's checklist (tools/checklist.py → docs/checklist/test-checklist.xlsx): a fresh
## game for each row, the thing put into it by the console's own roads (Gear.give, StudyRules.learn_spell, a fight with
## the monster, a status laid by ConditionRules.impose), then what its data and its description promise, done by the
## engine and looked at. A row is {status, steps}; a step is «✓ …» (the engine did it), «✗ …» (it did otherwise — a bug),
## «○ …» (promised, and the engine has nothing for it — a gap for the backlog), «◇ …» (left to the master's words).
## The results are kept in game/test/fixtures/checklist_probes.json (written by res://tools/checklist_probes.gd), held by
## test_checklist_probes.gd and shown on the sheet. Pure: no nodes.

const OK := "работает"
const BUG := "ошибка"
const GAP := "нет механики"
const MASTER := "через мастера"
const PLAIN := "без механики"
## A trait the engine reads through an act shown for the template that has it: in the engine only where that act shows.
const BY_ACT := {"shapechanger": "shape"}
## A step's mark → the status it gives its row; the worst one wins.
const MARKS := {"✗": BUG, "○": GAP, "◇": MASTER, "✓": OK}
const WORST: Array[String] = [BUG, GAP, MASTER, OK, PLAIN]
## The sheets of the checklist this checks, in its order.
const SHEETS: Array[String] = ["Обычные предметы", "Магические предметы", "Монстры", "Способности", "Заклинания", "Состояния",
	"Сопротивления и иммунитеты", "Типы урона", "Жидкости"]
## The probe of damage: 8 before a defense, then what each leaves (as tools/checklist.py says it).
const PROBE := 8
const LEFT := {"": 8, "resist": 4, "immune": 0, "vulnerable": 16}
## Words of a description that promise a rule (an SRD text of gear): an item with none of the engine's mechanics and such a
## word is a gap. A word → what it promises.
## Properties that say what a thing's use does, checked with the use (the antitoxin's resist_poison is its boon).
const USE_SAYS: Array[String] = ["healing", "thrown", "resist_poison"]
const PROMISES := {"Действием": "действие", "бонусным действием": "бонусное действие", "спасбросок": "спасбросок",
	"урон": "урон", "преимуществ": "преимущество", "помех": "помеху", "хит": "хиты", "Сл ": "проверку со Сл",
	"проверк": "проверку", "свет": "свет", "радиус": "радиус", "скорост": "скорость", "вмещает": "вместимость",
	"поднимать груз": "подъём груза", "увеличени": "увеличение", "защищает": "защиту"}


# --- the whole checklist ---------------------------------------------------------------------------------------------


## Every row of every sheet: {sheet: {id: {status, steps}}}. `data` — the game data with the start pack applied.
static func all(data: Dictionary) -> Dictionary:
	var out := {}
	for sheet: String in SHEETS:
		out[sheet] = sheet_rows(data, sheet)
	return out


## The rows of one sheet: {id: {status, steps}}.
static func sheet_rows(data: Dictionary, sheet: String) -> Dictionary:
	var out := {}
	match sheet:
		"Обычные предметы", "Магические предметы":
			var magic := sheet == "Магические предметы"
			for id: String in items(data):
				if is_magic(items(data)[id]) == magic:
					out[id] = item(data, id)
		"Монстры":
			for id: String in data["monsters"]:
				out[id] = monster(data, id)
		"Способности":
			for id: String in data["classes"]["features"]:
				out[id] = feature(data, id)
			for id: String in data["races"]["traits"]:
				out["trait:" + id] = race_trait(data, id)
		"Заклинания":
			for id: String in data["spells"]:
				out[id] = spell(data, id)
		"Состояния":
			for id: String in Cheats.conditions(data):
				out[id] = condition(data, id)
		"Сопротивления и иммунитеты":
			for dtype: String in data["misc"]["damage_types"]:
				for kind: String in Cheats.DEFENSES:
					out["%s:%s" % [kind, dtype]] = defense(data, kind, dtype)
			for cond: String in data["rules"]["conditions"]:
				var who := immune_to(data, cond)
				if not who.is_empty():
					out["condition:" + cond] = condition_immunity(data, cond, who)
		"Типы урона":
			for dtype: String in data["misc"]["damage_types"]:
				out[dtype] = damage_type(data, dtype)
		"Жидкости":
			for lid: String in LiquidRules.cfg(data)["kinds"]:
				out[lid] = liquid(data, lid)
	return out


## The things of the game as the checklist lists them: the catalog with the pack's own.
static func items(data: Dictionary) -> Dictionary:
	return data["items"]["catalog"]


## Magic by its kind, as tools/checklist.py sorts the two sheets: charges or a spell make a thing magic unless it is plain
## gear (a healer's kit, a disguise kit, v0.8.4.26.4).
static func is_magic(d: Dictionary) -> bool:
	var use: Variant = d.get("use")
	var spelled := _truthy(d.get("charges")) or (use is Dictionary and _truthy((use as Dictionary).get("spell")))
	return str(d.get("rarity", "common")) != "common" or _truthy(d.get("attunement")) or _truthy(d.get("caster")) \
		or str(d.get("item_type", "")) == "wondrous" or (spelled and str(d.get("item_type", "")) != "gear")


## A value as Python reads it for truth: tools/checklist.py sorts the sheets so.
static func _truthy(v: Variant) -> bool:
	if v is Dictionary or v is Array or v is String:
		return not v.is_empty()
	return v != null and bool(v)


# --- a row ----------------------------------------------------------------------------------------------------------


## A check: «✓ what» when `ok`, else «✗ what — got».
static func check(steps: Array[String], ok: bool, what: String, got: Variant = "") -> bool:
	steps.append(("✓ " if ok else "✗ ") + what + ("" if ok or str(got).is_empty() else " — " + str(got)))
	return ok


static func gap(steps: Array[String], what: String) -> void:
	steps.append("○ " + what)


static func master(steps: Array[String], what: String) -> void:
	steps.append("◇ " + what)


## The row of its steps: the worst mark's status; none — nothing to check.
static func result(steps: Array[String]) -> Dictionary:
	var status := PLAIN
	for st: String in steps:
		var mark := str(MARKS.get(st.left(1), ""))
		if not mark.is_empty() and WORST.find(mark) < WORST.find(status):
			status = mark
	return {"status": status, "steps": steps}


## A fresh game of the start pack: the first ready-made hero (a fighter: every weapon and armour is his), bare-handed
## and in nothing, without a fighting style (a thing's numbers read as its data says them), the weather off.
static func session(data: Dictionary, preset := 0, seed_value := 42) -> GameSession:
	var s := GameSession.create(seed_value, "2026-10-18T12:00:00", str(data["world"]["start_room"]),
		CharacterBuilder.build_preset(data["presets"][preset], data))
	s.world_id = "frontier"
	s.settings = WorldPack.default_settings(data["pack"])
	s.settings["weather"] = false
	var c := s.character
	c["features"] = (c.get("features", []) as Array).filter(func(f: Variant) -> bool: return not str(f).contains("fighting_style"))
	for slot: String in CharacterRules.SLOTS:
		c["equipped"][slot] = ""
	for slot: String in CharacterRules.stowed(c):
		CharacterRules.stowed(c)[slot] = ""
	CharacterRules.refresh(c, data, s.items)
	return s


## The ready-made hero who casts by the sheet first (a sorcerer): for a thing only a caster attunes to.
static func caster(data: Dictionary) -> int:
	for i in (data["presets"] as Array).size():
		if str(data["presets"][i].get("id", "")).begins_with("sorcerer"):
			return i
	return 0


## A fight with one foe beside the hero (`far` — 30 feet off) that will not fall from a probe: its HP 999.
static func fight(s: GameSession, data: Dictionary, monster: String, far := false, side := "enemy") -> Dictionary:
	var spec := {"monster": monster, "x": 46 if far else 41, "y": 30}
	if side == "ally":
		CombatRules.start(s, data, [{"monster": "commoner", "x": 60, "y": 30}], {"field": {"w": 80, "h": 60}, "allies": [spec]})
	else:
		CombatRules.start(s, data, [spec], {"field": {"w": 80, "h": 60}})
	var p := CombatRules.player(s)
	p["x"] = 40
	p["y"] = 30
	for id: String in s.combat["fighters"]:
		var f := CombatRules.fighter(s, id)
		if str(f.get("monster", "")) == monster and str(f.get("side", "")) == side:
			f["hp"] = 999
			f["max_hp"] = 999
			return f
	return {}


## The turn of `f` now, with its points fresh: what it does next is a probe, not the order of the fight.
static func turn(s: GameSession, data: Dictionary, f: Dictionary) -> void:
	s.combat["turn"] = maxi(0, (s.combat["order"] as Array).find(str(f["id"])))
	f["surprised"] = false
	f["points"] = CombatRules.fresh_points(s, data, f)


static func _hp(s: GameSession, data: Dictionary) -> int:
	return Sheet.hp(s, data, Sheet.HERO)


# --- items ----------------------------------------------------------------------------------------------------------


## A thing of the catalog: given, put on (attuned first) where it goes, then its weapon, armour, properties, use, food,
## water, light, tool and container, each by the engine; a description that promises a rule nothing of these keeps — a gap.
static func item(data: Dictionary, id: String) -> Dictionary:
	var steps: Array[String] = []
	var d := ItemRules.def_of(data["items"], {}, id)
	var s := session(data, caster(data) if _truthy(d.get("caster")) else 0)
	var c := s.character
	Gear.give(s, data, Being.HERO, id, 1)
	if Gear.count(s, data, Being.HERO, id) < 1:  # given: no mechanic yet, only the way in
		check(steps, false, "give", "нет в инвентаре")
		return result(steps)
	steps.append("· give: в инвентаре")
	var mech := 0
	if ItemRules.needs_attunement(d):
		var why := ItemRules.can_attune(c, data, s.items, id)
		if check(steps, why.is_empty(), "настройка", why):
			ItemRules.attune(c, data, s.items, id)
	var slot := CharacterRules.slot_for(d, data)
	if not slot.is_empty():
		var why := CharacterRules.can_equip(c, data, s.items, id, slot)
		if check(steps, why.is_empty(), "надевается: %s" % slot, why):
			for sl: String in CharacterRules.hands_freed(c, data, s.items, id, slot):
				c["equipped"][sl] = ""
			c["equipped"][slot] = id
			CharacterRules.refresh(c, data, s.items)
			check(steps, Sheet.working(s, data, Sheet.HERO).any(func(w: Dictionary) -> bool: return str(w.get("name", "")) == str(d.get("name", ""))),
				"работает надетой", "движок не считает её действующей")
	if d.has("weapon"):
		mech += 1
		_weapon(s, data, id, d, steps)
	if d.has("armor"):
		mech += 1
		_armor(s, data, id, d, steps)
	for p: Variant in d.get("properties", []):
		mech += 1 if _prop(s, data, id, d, str(p), steps) else 0
	if d.get("wear") is Dictionary:
		mech += 1
		_wear(s, data, id, d, steps)
	var use := ItemRules.consumable(data, id, s.items)
	if not use.is_empty():
		mech += 1
		_use(data, id, use, steps)
	if data["rules"]["hero_effects"]["camp"]["food"].has(id) and not use.has("meal"):
		mech += 1
		_food(data, id, steps)
	if LiquidRules.holds(data, id) > 0.0:
		mech += 1
		_vessel(data, id, steps)
	if not LiquidRules.ready(data, id).is_empty():
		mech += 1
		_liquid(data, id, steps)
	if data["rules"]["sight"]["lights"].has(id):
		mech += 1
		_light(data, id, steps)
	if data["rules"]["tools"].has(id) or _truthy(d.get("tool")):
		mech += 1
		_tool(data, id, steps)
	if data["rules"]["containers"]["kinds"].has(id):
		mech += 1
		_container(data, id, steps)
	if not _about_rows(data, id).is_empty():
		mech += 1
		_check_item(data, id, steps)
	if (data["rules"]["containers"]["own_locks"] as Dictionary).has(id):
		mech += 1
		_own_lock(data, id, steps)
	if not _bond_of(data, id).is_empty():
		mech += 1
		_bonds(data, id, steps)
	if (data["rules"]["weather"].get("sun_fire_items", []) as Array).has(id):
		mech += 1
		_sun_fire(data, id, steps)
	if ItemRules.charges_max(d) > 0:
		mech += 1
		_charges(data, id, d, steps)
	if mech == 0:
		mech += _roles(data, id, d, steps)
	if bool(d.get("master", false)):
		master(steps, "свойство только словами мастера (флаг master)")
	if mech == 0 and not bool(d.get("master", false)):
		var promised := _promised(str(d.get("description", "")))
		if not promised.is_empty():
			gap(steps, "описание обещает %s — у движка для вещи ничего нет" % ", ".join(promised))
	return result(steps)


## Rows of the rules that name a thing without giving it a use: demand, gifts, the master's lists, the town's goods.
const TRADE_ONLY: Array[String] = ["trade", "theft", "bonds", "prepare", "make", "shop", "world_gen", "quest_gen", "props", "reputation",
	"underworld", "jobs", "property", "festivals", "calendar", "family", "faith", "office", "study", "letters", "contests"]


## Places of the rules where the same word is not the thing: a save's tag («charm»), a door's state («lock»).
const WORDS_NOT_THINGS: Array[String] = ["hero_effects.save_tags", "spell_effects"]


## What else of the engine uses a thing with no mechanic of its own: ammunition of a weapon, a material of a recipe, a book
## that teaches, a thing of a quest, a row of the rules (a tent against the cold, tackle for fishing). How many it found.
static func _roles(data: Dictionary, id: String, d: Dictionary, steps: Array[String]) -> int:
	var n := 0
	var by := (ItemRules.cfg(data)["ammo"] as Dictionary).keys().filter(func(w: String) -> bool: return str(ItemRules.cfg(data)["ammo"][w]) == id)
	if not by.is_empty():
		n += 1
		check(steps, true, "боеприпас: %s" % ", ".join(by.slice(0, 4)))
	var used := 0
	var made := 0
	for rid: String in data["rules"]["craft"]["recipes"]:
		var rec: Variant = data["rules"]["craft"]["recipes"][rid]
		if rec is Dictionary:
			used += 1 if (rec.get("materials", {}) as Dictionary).has(id) else 0
			made += 1 if str(rec.get("output", "")) == id else 0
	if used > 0:
		n += 1
		check(steps, true, "материал ремесла: %d рецептов" % used)
	if d.has("teaches"):
		n += 1
		check(steps, true, "книга учит: %s" % JSON.stringify(d["teaches"]).left(80))
	if str(d.get("item_type", "")) == "quest":
		n += 1
		check(steps, true, "вещь задания пакета")
	if n == 0:
		var keys: Array[String] = []
		var sold: Array[String] = []
		for k: String in data["rules"]:
			var at := _path_of(data["rules"][k], id, k)
			if not k.begins_with("_") and not at.is_empty() and not at.contains(".adv_tag") \
					and not WORDS_NOT_THINGS.any(func(w: String) -> bool: return at.begins_with(w)):
				(sold if TRADE_ONLY.has(k) else keys).append(at)
		if not keys.is_empty():
			n += 1
			check(steps, true, "движок знает вещь: rules.%s" % ", rules.".join(keys.slice(0, 4)))
		elif not sold.is_empty():
			steps.append("· только в торговле, подарках, кражах, заготовках мастера: rules.%s" % ", rules.".join(sold.slice(0, 4)))
	if made > 0 and n == 0:
		steps.append("· делается ремеслом: %d рецептов" % made)
	return n


## Where in `v` the value `id` (or a key of an item-like table) stands: a dotted path, "" when nowhere. A field of the same
## name («lock» of a chest) is not the thing.
static func _path_of(v: Variant, id: String, at: String) -> String:
	if v is Dictionary:
		for k: Variant in v:
			if str(k) == id and v[k] is Dictionary and not str(k).begins_with("_"):
				return at + "." + id
			var deeper := _path_of(v[k], id, at + "." + str(k))
			if not deeper.is_empty():
				return deeper
	elif v is Array:
		for x: Variant in v:
			if x is String and x == id:
				return at
			var deeper := _path_of(x, id, at)
			if not deeper.is_empty():
				return deeper
	elif v is String and v == id:
		return at
	return ""


## What a description promises by its words (PROMISES), in their order.
static func _promised(text: String) -> Array[String]:
	var out: Array[String] = []
	for w: String in PROMISES:
		if text.contains(w) and not out.has(str(PROMISES[w])):
			out.append(str(PROMISES[w]))
	return out


## A weapon in the hands: its die and type, its properties on the blow, then a real blow at a foe until it lands.
static func _weapon(s: GameSession, data: Dictionary, id: String, d: Dictionary, steps: Array[String]) -> void:
	var c := s.character
	var w: Dictionary = d["weapon"]
	var props: Array = d.get("properties", [])
	if str(c["equipped"].get("main_hand", "")) != id:
		return
	var p := CombatRules.weapon_profile(c, data, s.items, id)
	var dice := str(w.get("versatile", w.get("damage", ""))) if w.has("versatile") else str(w.get("damage", ""))
	if dice.is_empty():  # a net: no blow of its own, it is thrown (its use)
		return
	check(steps, str(p["dice"]) == dice and str(p["type"]) == str(w.get("damage_type", "")),
		"удар %s %s" % [dice, w.get("damage_type", "")], "%s %s" % [p["dice"], p["type"]])
	if props.has("finesse"):
		c["abilities"]["str"] = 8
		c["abilities"]["dex"] = 16
		CharacterRules.refresh(c, data, s.items)
		var fp := CombatRules.weapon_profile(c, data, s.items, id)
		check(steps, int(fp["bonus"]) - ItemRules.plus(d, ["magic_plus"]) == 3, "фехтовальное: Лов 16 вместо Сил 8 → +3 к урону", fp["bonus"])
	if props.has("thrown"):
		check(steps, not (p["range"] as Array).is_empty(), "метательное: дистанция броска", "нет дистанции")
	if props.has("ammunition"):
		var ammo := str(p.get("ammo", ""))
		check(steps, not ammo.is_empty() and items(data).has(ammo), "боеприпас: %s" % ammo, "нет боеприпаса в rules.item_rules.ammo")
	if props.has("reach"):
		check(steps, bool(p.get("reach", false)), "досягаемость 10 фт", "не читается")
	if props.has("light"):
		check(steps, CharacterRules.slots_of(d, data).has("off_hand"), "лёгкое: во вторую руку", "не идёт во вторую руку")
	if props.has("heavy"):
		check(steps, bool(p.get("heavy", false)), "тяжёлое: помеха маленьким", "не читается")
	if props.has("two_handed"):
		Gear.give(s, data, Being.HERO, "shield", 1)
		c["equipped"]["shield"] = "shield"
		check(steps, CharacterRules.hands_freed(c, data, s.items, id, "main_hand").has("shield"), "двуручное: щит снимается", "щит остаётся")
		c["equipped"]["shield"] = ""
		CharacterRules.refresh(c, data, s.items)
	if props.has("loading"):
		gap(steps, "перезарядка (один выстрел за действие) — не читается")
	_blow(s, data, id, p, steps)


## The weapon strikes a foe by the attack act (a ranged one from 30 feet with its ammunition) until a blow lands.
static func _blow(s: GameSession, data: Dictionary, id: String, p: Dictionary, steps: Array[String]) -> void:
	var ranged := not bool(p["melee"])
	if not str(p.get("ammo", "")).is_empty():
		Gear.give(s, data, Being.HERO, str(p["ammo"]), 20)
	var t := fight(s, data, "goblin", ranged)
	t["ac"] = 1
	var hero := CombatRules.player(s)
	var act := Acts.one("attack")
	turn(s, data, hero)
	var why := act.can(s, data, hero, str(t["id"]), {})
	if not check(steps, why.is_empty(), "атака в бою", why):
		return
	var lines: Array[String] = []
	for i in 10:
		turn(s, data, hero)
		lines = act.go(s, data, hero, str(t["id"]), {})
		if int(t["hp"]) < 999:
			break
	var lo := CombatRules.dice_range(str(p["dice"]))[0] + int(p["bonus"])
	var hi := CombatRules.dice_range(str(p["dice"]))[1] * 2 + int(p["bonus"]) + 12
	var dealt := 999 - int(t["hp"])
	check(steps, dealt >= maxi(0, lo) and dealt <= hi, "удар по гоблину: −%d HP" % dealt, " ".join(lines).left(160))
	if not str(p.get("ammo", "")).is_empty():
		check(steps, Gear.count(s, data, Being.HERO, str(p["ammo"])) < 20, "выстрел тратит %s" % p["ammo"], "не тратит")


## Armour or a shield on: the AC by its numbers, the stealth it hampers, the Strength it asks.
static func _armor(s: GameSession, data: Dictionary, id: String, d: Dictionary, steps: Array[String]) -> void:
	var c := s.character
	var a: Dictionary = d["armor"]
	var slot := "shield" if str(a.get("category", "")) == "shield" else "armor"
	if str(c["equipped"].get(slot, "")) != id:
		return
	var plus := ItemRules.plus(d, ["magic_plus"]) + ItemRules.plus(d, ["ac_plus"])
	var dex := CharacterRules.mod(CharacterRules.ability(c, "dex"))
	var want := 0
	if slot == "shield":
		c["equipped"][slot] = ""
		CharacterRules.refresh(c, data, s.items)
		var bare := CharacterRules.armor_class(c, data, s.items)
		c["equipped"][slot] = id
		CharacterRules.refresh(c, data, s.items)
		want = bare + int(a.get("base", 2)) + plus
	else:
		want = CharacterRules.armored(a, dex) + plus
	var ac := CharacterRules.armor_class(c, data, s.items)
	check(steps, ac == want, "КД %d" % want, "КД %d" % ac)
	if bool(a.get("stealth_disadvantage", false)):
		var sit := CheckEngine.situation(s, data, Sheet.HERO, {"skill": "stealth"}, true)
		check(steps, not (sit["dis"] as Array).is_empty(), "помеха Скрытности", "помехи нет")
	if int(a.get("str_min", 0)) > 0:
		var strength := int(c["abilities"]["str"])
		c["abilities"]["str"] = int(a["str_min"]) - 2
		CharacterRules.refresh(c, data, s.items)
		var slow := CharacterRules.speed(c, data)
		c["equipped"]["armor"] = ""
		CharacterRules.refresh(c, data, s.items)
		var free := CharacterRules.speed(c, data)
		c["abilities"]["str"] = strength
		c["equipped"]["armor"] = id
		CharacterRules.refresh(c, data, s.items)
		if slow == free:
			gap(steps, "Сил %d: без нужной Силы скорость не падает на 10 фт — требование только в карточке" % int(a["str_min"]))
		else:
			check(steps, slow == free - 10, "Сил %d: скорость −10 фт без нужной Силы" % int(a["str_min"]), "скорость %d, без доспеха %d" % [slow, free])


## A property of a worn or carried thing, done by the engine. True when it is one the engine has a probe for.
static func _prop(s: GameSession, data: Dictionary, id: String, d: Dictionary, p: String, steps: Array[String]) -> bool:
	var c := s.character
	var names: Dictionary = data["rules"]["item_props"]["names"]
	var on := Sheet.prop(s, data, Sheet.HERO, p)
	var said := str(names.get(p, p))
	var weapon_own := ["finesse", "thrown", "ammunition", "reach", "light", "heavy", "two_handed", "versatile", "loading", "special"]
	if weapon_own.has(p):
		return false  # read with the weapon's blow
	if USE_SAYS.has(p) and not ItemRules.consumable(data, id, s.items).is_empty():
		return false  # it says what its use does: checked with the use
	if p.begins_with("resist_"):
		var dtype := p.trim_prefix("resist_")
		var left := Sheet.taken(s, data, Sheet.HERO, dtype, PROBE)
		return check(steps, left == LEFT["resist"], "%s: %d %s → %d" % [said, PROBE, dtype, LEFT["resist"]], left)
	match p:
		"magic_plus1", "ac_plus1":
			if d.has("weapon") or d.has("armor"):
				return true  # its numbers are checked with the weapon's blow or the armour's AC
			var bare := _without(s, data, id, func() -> int: return CharacterRules.armor_class(c, data, s.items))
			return check(steps, CharacterRules.armor_class(c, data, s.items) == bare + 1, "КД +1", "КД %d, без вещи %d" % [CharacterRules.armor_class(c, data, s.items), bare])
		"saves_plus1":
			var bare := _without(s, data, id, func() -> int: return Sheet.save_bonus(s, data, Sheet.HERO, "wis"))
			return check(steps, Sheet.save_bonus(s, data, Sheet.HERO, "wis") == bare + 1, "спасброски +1", "Мдр %d, без вещи %d" % [Sheet.save_bonus(s, data, Sheet.HERO, "wis"), bare])
		"checks_plus1":
			var bare := _without(s, data, id, func() -> int: return _skill_total(s, data, "history"))
			return check(steps, _skill_total(s, data, "history") == bare + 1, "проверки +1", "История %d, без вещи %d" % [_skill_total(s, data, "history"), bare])
		"stealth_advantage", "perception_advantage", "investigation_advantage":
			var skill := p.trim_suffix("_advantage")
			var sit := CheckEngine.situation(s, data, Sheet.HERO, {"skill": skill}, true)
			return check(steps, not (sit["adv"] as Array).is_empty(), "преимущество: %s" % skill, "нет преимущества")
		"darkvision":
			return check(steps, SightRules.dark_sight(s, data) > 0, "тёмное зрение", "герой не видит в темноте")
		"str_19", "int_19":
			var ab := p.get_slice("_", 0)
			c["abilities"][ab] = 10
			CharacterRules.refresh(c, data, s.items)
			var got := Sheet.ability(s, data, Sheet.HERO, ab)
			return check(steps, got == 19, "%s 19 при своих 10" % ab, got)
		"speed_30":
			c["race"] = "dwarf"
			CharacterRules.refresh(c, data, s.items)
			return check(steps, CharacterRules.speed(c, data) >= 30, "скорость не меньше 30 фт (дварф)", CharacterRules.speed(c, data))
		"carry_plus_500":
			var bare := _without(s, data, id, func() -> int: return CharacterRules.capacity(c, data))
			return check(steps, CharacterRules.capacity(c, data) == bare + 500, "грузоподъёмность +500 фунтов", "%d, без вещи %d" % [CharacterRules.capacity(c, data), bare])
		"light_source":
			var why := ItemRules.belt_why(c, data, s.items, id)
			if why.is_empty():
				ItemRules.belt_put(c, data, s.items, id)
			return check(steps, SightRules.light(s, data) > 0, "свет с пояса", "не светит" if why.is_empty() else why)
		"no_crit":
			return check(steps, on, "крит по герою — обычное попадание (Attack: no_crit)", "не действует")
		"immune_disease":
			return check(steps, not HeroDefense.immune(s, data, Sheet.HERO, "poisoned", "disease").is_empty(), "невосприимчивость к болезням", "не действует")
		"understand_all":
			return check(steps, LanguageRules.understands_all(c), "понимает все языки", "не действует")
		"spell_attack_plus1":
			var bare := _without(s, data, id, func() -> int: return int(c.get("spell_attack", 0)))
			return check(steps, int(c.get("spell_attack", 0)) == bare + 1, "атака заклинанием +1", "%d, без вещи %d" % [int(c.get("spell_attack", 0)), bare])
		"ranged_damage_plus2":
			Gear.give(s, data, Being.HERO, "longbow", 1)
			var with := int(CombatRules.weapon_profile(c, data, s.items, "longbow")["bonus"])
			var bare := _without(s, data, id, func() -> int: return int(CombatRules.weapon_profile(c, data, s.items, "longbow")["bonus"]))
			return check(steps, with == bare + 2, "урон длинного лука +2", "%d, без вещи %d" % [with, bare])
		"warm":
			return check(steps, not WeatherRules.guard(s, data, "cold", false).is_empty(), "греет: холодная ночь не страшна", "не греет")
		"water_source":
			var dry := _without(s, data, id, func() -> int: return 1 if NeedRules.water_here(s, data) else 0)
			return check(steps, NeedRules.water_here(s, data) and dry == 0, "вода где угодно: сосуд наполняется", "воды нет")
		"missile_snaring", "wound_closure":
			return check(steps, on, said, "не действует")
		"mithral":
			if d.has("armor"):
				var a: Dictionary = d["armor"]
				return check(steps, int(a.get("str_min", 0)) == 0 and not bool(a.get("stealth_disadvantage", false)), "мифрил: без Силы и помехи Скрытности", "остались")
			return false
		"silvered":
			return check(steps, bool(CombatRules.weapon_profile(c, data, s.items, id).get("silvered", false)), "посеребрённое", "не читается")
	if names.has(p):
		return check(steps, on, said, "не действует")
	gap(steps, "свойство %s — движок его не знает (нет в rules.item_props)" % p)
	return true


## What `read` says with the thing taken off its slot and out of the attunement, then put back.
static func _without(s: GameSession, data: Dictionary, id: String, read: Callable) -> int:
	var c := s.character
	var n := int(c["inventory"].get(id, 0))
	var eq: Dictionary = (c["equipped"] as Dictionary).duplicate()
	var bound: Array = (c.get("attuned", []) as Array).duplicate()
	c["inventory"].erase(id)
	for slot: String in CharacterRules.SLOTS:
		if str(c["equipped"].get(slot, "")) == id:
			c["equipped"][slot] = ""
	CharacterRules.refresh(c, data, s.items)
	var out := int(read.call())
	c["inventory"][id] = n
	c["equipped"] = eq
	c["attuned"] = bound
	CharacterRules.refresh(c, data, s.items)
	return out


## What a worn thing lays while it works (`wear`): a way of moving on the hero's speeds (Move), any other status on the hero and
## read by the engine; gone when the thing is taken off. A light lays its own lit on the belt.
static func _wear(s: GameSession, data: Dictionary, id: String, d: Dictionary, steps: Array[String]) -> void:
	var c := s.character
	if (d.get("properties", []) as Array).has("light_source") and ItemRules.belt_why(c, data, s.items, id).is_empty():
		ItemRules.belt_put(c, data, s.items, id)
	CharacterRules.refresh(c, data, s.items)
	var moves := Move.table(data)
	var spec := ItemRules.wear_spec(c, data, d)
	for k: String in spec:
		var way := ""
		for m: String in moves:
			if str(moves[m].get("status", "")) == k:
				way = m
		if not way.is_empty():
			var feet := func() -> int: return int(Move.speeds(s, data, Sheet.HERO).get(way, 0))
			var got: int = feet.call()
			check(steps, got >= int(spec[k]) and _without(s, data, id, feet) < int(spec[k]), "%s %d фт, пока надета" % [moves[way]["word"], int(spec[k])],
				"%d фт" % got)
		elif check(steps, not reads(k).is_empty(), "движок читает %s (%s)" % [k, ", ".join(reads(k))], "никто не читает"):
			var on := func() -> int: return 1 if SpellEffects.has(c, k) else 0
			check(steps, int(on.call()) == 1 and _without(s, data, id, on) == 0, "%s, пока работает" % k, "не лежит на герое")


static func _skill_total(s: GameSession, data: Dictionary, skill: String) -> int:
	return RollParts.sum(RollParts.skill(s, data, skill))


## A consumable used from the belt by the engine (a thrown one at a foe in a fight); what it lays is looked at.
static func _use(data: Dictionary, id: String, use: Dictionary, steps: Array[String]) -> void:
	var d := ItemRules.def_of(data["items"], {}, id)
	var s := session(data, caster(data) if _truthy(d.get("caster")) else 0)
	var c := s.character
	Gear.give(s, data, Being.HERO, id, 1)
	ItemRules.identify(c, data, s.items)
	if ItemRules.needs_attunement(d):
		ItemRules.attune(c, data, s.items, id)
	var slot := CharacterRules.slot_for(d, data)
	if not slot.is_empty():  # a worn thing is used where it is worn (ItemRules.at_hand)
		c["equipped"][slot] = id
	CharacterRules.refresh(c, data, s.items)
	if use.has("throw"):
		_throw(s, data, id, use, steps)
		return
	if not use.has("meal") and slot.is_empty() and ItemRules.belt_fits(data, s.items, id):
		ItemRules.belt_put(c, data, s.items, id)
	if use.has("recover_slot"):
		c["class"] = "wizard"
		Stock.spend(c, "slot_1")
	if use.has("heal") or use.has("spell") and data["spells"].get(str(use["spell"]), {}).has("heal_at_slot"):
		c["hp"] = 1
	if use.has("remove"):
		for cond: Variant in use["remove"]:
			ConditionRules.impose(s, data, {"condition": str(cond), "ends": {}, "source": {"kind": "dev", "name": "проба"}})
	if use.has("meal"):
		NeedRules.set_value(s, data, "food", 10.0)
	var ill := ""
	if (use.get("cure", []) as Array).has("disease"):
		ill = _disease(data, str(use.get("power", "magic")))
		DiseaseRules.contract(s, data, ill)
	var why := ItemRules.can_use(c, data, s.items, id)
	if not check(steps, why.is_empty(), "можно использовать с пояса", why):
		return
	var hp := _hp(s, data)
	var food := NeedRules.value(s, data, "food")
	var water := NeedRules.value(s, data, "water")
	var effects := ConditionRules.effects(c).size()
	var called := AllyRules.called(s).size()
	var lines := ItemRules.use(c, data, s.items, id, s.rng, s)
	var said := " ".join(lines).left(160)
	if ItemRules.charges_max(d) <= 0 and not bool(use.get("at_will", false)):
		check(steps, Gear.count(s, data, Being.HERO, id) == 0 or ItemRules.charges_max(d) > 0, "тратится", "осталась")
	if use.has("heal"):
		var h: Array = use["heal"]
		var lo := int(h[0]) + int(h[2])
		check(steps, _hp(s, data) - hp >= mini(lo, Sheet.max_hp(s, data, Sheet.HERO) - hp), "лечит %dк%d+%d" % [int(h[0]), int(h[1]), int(h[2])], said)
	if use.has("remove"):
		for cond: Variant in use["remove"]:
			check(steps, not ConditionRules.has(c, str(cond)), "снимает: %s" % ConditionRules.name_of(data, str(cond)), said)
	if use.has("meal"):
		check(steps, NeedRules.value(s, data, "food") > food, "еда: сытость растёт", said)
		if int((use["meal"] as Dictionary).get("water", 0)) > 0:
			check(steps, NeedRules.value(s, data, "water") >= water, "питьё в блюде", said)
		if int((use["meal"] as Dictionary).get("temp_hp", 0)) > 0:
			check(steps, int(c.get("temp_hp", 0)) > 0, "временные хиты", said)
	if use.has("cure") or use.has("invisible_minutes") or ConditionRules.BOONS.any(func(k: String) -> bool: return use.has(k)):
		check(steps, ConditionRules.effects(c).size() > effects or lines.size() > 1, "накладывает эффект", said)
		if use.has("resist"):
			for dtype: Variant in (use["resist"] if use["resist"] is Array else [use["resist"]]):
				if data["misc"]["damage_types"].has(str(dtype)):
					check(steps, Sheet.taken(s, data, Sheet.HERO, str(dtype), PROBE) == LEFT["resist"], "сопротивление %s" % dtype, Sheet.taken(s, data, Sheet.HERO, str(dtype), PROBE))
	if not ill.is_empty():
		check(steps, not DiseaseRules.sick(c, ill), "лечит болезнь: %s" % data["rules"]["diseases"]["catalog"][ill]["name"], said)
	if use.has("poison"):
		check(steps, _hp(s, data) < hp, "яд ранит", said)
	if use.has("coat"):  # a poison on the blade: the next hit of its damage types brings its dice with a save
		var co: Dictionary = use["coat"]
		var x := SpellEffects.hit_extras(c, {}, str((co["weapons"] as Array)[0]))
		check(steps, x.any(func(e: Dictionary) -> bool: return str(e.get("save", "")) == str(co["save"])),
			"яд на оружии: %s %s при попадании, спасбросок Сл %d" % [co["dice"], co["type"], int(co["dc"])], said)
	if use.has("check"):  # a kit lays its spell's effect with the DC of its user's check
		check(steps, int(Guise.of(c).get("dc", 0)) > 0, "облик «Маскировки», Сл разоблачения — проверка %s с набором (%d)" % [use["check"].get("skill", ""), int(Guise.of(c).get("dc", 0))], said)
	if SpellEffects.spec(data, str(use.get("spell", ""))).has("stabilize"):  # a healer's kit: a fallen ally stabilized in a fight
		var fs := session(data)
		Gear.give(fs, data, Being.HERO, id, 1)
		ItemRules.belt_put(fs.character, data, fs.items, id)
		var a := fight(fs, data, "goblin", false, "ally")
		a["hp"] = 0
		a["status"] = "down"
		var p := CombatRules.player(fs)
		turn(fs, data, p)
		var why2 := Acts.one("item_spell").can(fs, data, p, str(a["id"]), {"item": id})
		if check(steps, why2.is_empty(), "в бою на павшего союзника", why2):
			Acts.one("item_spell").go(fs, data, p, str(a["id"]), {"item": id})
			check(steps, bool(CombatRules.saves_of(fs, a).get("stable", false)) and ItemRules.charges_left(fs.character, d, id) == ItemRules.charges_max(d) - 1,
				"стабилизирован без проверки Медицины, применений: %d из %d" % [ItemRules.charges_left(fs.character, d, id), ItemRules.charges_max(d)], "не стабилизирован")
	if use.has("recover_slot"):
		check(steps, said.contains("восстановлена") or said.contains("целы"), "возвращает ячейку", said)
	if use.has("summon"):
		check(steps, AllyRules.called(s).size() > called, "призывает: %s" % said, "никто не пришёл")
	if bool(use.get("at_will", false)):
		check(steps, Gear.count(s, data, Being.HERO, id) == 1, "без ограничений: вещь не тратится", "потрачена")
	if use.has("spell"):
		var sp := str(use["spell"])
		if data["spells"].get(sp, {}).has("heal_at_slot"):
			check(steps, _hp(s, data) > hp, "лечит заклинанием %s" % sp, said)
		elif sp == "identify":
			check(steps, said.contains("неопознанных") or lines.size() > 1, "опознаёт", said)
		else:
			var name := str(data["spells"].get(sp, {}).get("name", sp))
			check(steps, said.contains(name) or said.contains("Магия"), "читается: %s" % name, said)
			var landed: Array[String] = []
			for i in lines.size():
				if lines[i].begins_with(name):
					landed = lines.slice(i + 1)  # past the spell's line: what the sheet's road did (SpellRules.cast)
					break
			if not landed.is_empty():
				check(steps, true, "вне боя: %s" % " · ".join(landed).left(120))
			elif not CombatRules.is_engine_spell(data, sp) and ActionRules.way(data, sp, true).is_empty():
				master(steps, "«%s» вне боя — рассказ мастера" % name)


## A disease of the rules that `power` cures: herbs take only the ones marked so, magic any.
static func _disease(data: Dictionary, power: String) -> String:
	var all: Dictionary = data["rules"]["diseases"]["catalog"]
	for id: String in all:
		if power != "herbs" or bool(all[id].get("herbs", false)):
			return id
	return ""


## A thrown flask, net or the like at a foe in a fight, by the throw act, until it lands.
static func _throw(s: GameSession, data: Dictionary, id: String, use: Dictionary, steps: Array[String]) -> void:
	var c := s.character
	Gear.give(s, data, Being.HERO, id, 9)
	if ItemRules.belt_fits(data, s.items, id):
		ItemRules.belt_put(c, data, s.items, id)
	if (use["throw"] as Dictionary).has("strew"):
		_strew(s, data, id, use["throw"], steps)
		return
	var types: Array = (use["throw"] as Dictionary).get("types", [])
	var far := bool(use["throw"].get("improvised", false)) or int(use["throw"].get("range", 15)) >= 30
	var t := fight(s, data, "skeleton" if types.has("undead") else "goblin", far)
	t["ac"] = 1
	var hero := CombatRules.player(s)
	var act := Acts.one("throw")
	var how := {"item": id}
	turn(s, data, hero)
	var why := act.can(s, data, hero, str(t["id"]), how)
	if not check(steps, why.is_empty(), "бросок в бою", why):
		return
	var said := ""
	for i in 8:
		turn(s, data, hero)
		said = " ".join(act.go(s, data, hero, str(t["id"]), how))
		if int(t["hp"]) < 999 or not LiquidRules.coat_on(s, t).is_empty() or ConditionRules.has(t, str(use["throw"].get("condition", "-"))):
			break
	var th: Dictionary = use["throw"]
	if th.has("damage"):
		check(steps, int(t["hp"]) < 999, "попадание: урон %s %s" % th["damage"], said.left(160))
	if LiquidRules.kind(data, str(th.get("liquid", ""))).has("coat"):  # what lies on it after (v0.8.4.28.2)
		check(steps, str(LiquidRules.coat_on(s, t).get("liquid", "")) == str(th["liquid"]), "цель облита: %s" % LiquidRules.name_of(data, str(th["liquid"])), said.left(160))
	if th.has("condition"):
		check(steps, ConditionRules.has(t, str(th["condition"])), "цель: %s" % ConditionRules.name_of(data, str(th["condition"])), said.left(160))


## Caltrops or ball bearings strewn on a square beside the hero: a foe walked onto it fails its save and gets what the
## row says.
static func _strew(s: GameSession, data: Dictionary, id: String, th: Dictionary, steps: Array[String]) -> void:
	var t := fight(s, data, "goblin", true)
	var hero := CombatRules.player(s)
	var at := Vector2i(41, 30)
	var how := {"item": id}
	turn(s, data, hero)
	var why := Acts.one("throw").can(s, data, hero, FightGrid.aim_id(at), how)
	if not check(steps, why.is_empty(), "рассыпать на клетку рядом", why):
		return
	Acts.one("throw").go(s, data, hero, FightGrid.aim_id(at), how)
	var row: Dictionary = FightGrid.cfg(data)["strewn"][str(th["strew"])]
	var lines: Array[String] = []
	for i in 12:
		turn(s, data, t)
		t["zoned"] = []
		FightGrid.put(t, at)
		FightField.stepped(s, data, t, lines)
		if int(t["hp"]) < 999 or CombatRules._has(t, "prone"):
			break
	if row.has("cond"):
		check(steps, CombatRules._has(t, str(row["cond"])), "вошедший: %s при провале Лов" % ConditionRules.name_of(data, str(row["cond"])), " ".join(lines).left(160))
	if (row.get("fail", {}) as Dictionary).has("dice"):
		check(steps, int(t["hp"]) < 999 and ConditionRules.sum(t, "speed") < 0 and int(t["points"]["move"]) <= 0,
			"вошедший: урон, остановка и скорость −10 при провале Лов", " ".join(lines).left(160))


## Camp food: eaten by the needs' «Поесть».
static func _food(data: Dictionary, id: String, steps: Array[String]) -> void:
	var s := session(data)
	s.character["inventory"].clear()
	Gear.give(s, data, Being.HERO, id, 3)
	NeedRules.set_value(s, data, "food", 10.0)
	var why := NeedRules.can_eat(s, data)
	if check(steps, why.is_empty(), "еда: «Поесть»", why):
		NeedRules.eat(s, data)
		check(steps, NeedRules.value(s, data, "food") > 10.0 and Gear.count(s, data, Being.HERO, id) < 3, "съедено, сытость растёт", NeedRules.value(s, data, "food"))


## A vessel of water: filled where water is, drunk from.
static func _vessel(data: Dictionary, id: String, steps: Array[String]) -> void:
	var s := session(data)
	s.character["inventory"].clear()
	Gear.give(s, data, Being.HERO, id, 1)
	check(steps, LiquidRules.holds(data, id) > 0.0, "вмещает %s пинт" % LiquidRules.num(LiquidRules.holds(data, id)))
	LiquidRules.drain(s.character)
	s.room_id = "brod-square"  # a well
	var only: Array = LiquidRules.cfg(data)["vessels"].get(id, {}).get("only", [])
	if not only.is_empty() and not only.has(LiquidRules.WATER):  # a lamp: only its oil (v0.8.4.28.3)
		check(steps, LiquidRules.to_fill(s.character, data, false).is_empty(), "воду не берёт: только %s" % ", ".join(only.map(func(l: String) -> String: return LiquidRules.name_of(data, l))))
		if LiquidRules.cfg(data)["vessels"][id].has("burns_hours"):
			check(steps, not LiquidRules.fuelled(s.character, data, id), "пустой не светит")
			Thing.nth(s.character, id, 0).merge({"liquid": str(only[0]), "pints": LiquidRules.holds(data, id)})
			check(steps, LiquidRules.fuelled(s.character, data, id), "с маслом светит %d ч" % int(LiquidRules.cfg(data)["vessels"][id]["burns_hours"]))
		return
	var why := NeedRules.can_fill(s, data)
	if why.is_empty():
		NeedRules.fill(s, data)
	check(steps, LiquidRules.pints(s.character, data) > 0.0, "наполняется водой", why)


## A liquid of rules.liquids (v0.8.4.28.3): poured into a vessel that takes it — by one with its tool if it `needs` one —,
## drunk or not, thrown, laid on one splashed with it, and what fire does to that; spilt on a square.
static func liquid(data: Dictionary, lid: String) -> Dictionary:
	var steps: Array[String] = []
	var s := session(data)
	var c := s.character
	c["inventory"].clear()
	c["tools"] = []
	LiquidRules.drain(c)
	var k := LiquidRules.kind(data, lid)
	var from := str(k.get("item", "jug_or_pitcher"))
	Gear.give(s, data, Being.HERO, from, 1)
	if not k.has("item"):
		Thing.nth(c, from, 0).merge({"liquid": lid, "pints": 2.0})
	var into := ""
	for id: String in LiquidRules.cfg(data)["vessels"]:
		if id != from and LiquidRules.takes({"only": LiquidRules.cfg(data)["vessels"][id].get("only", [])}, lid) and id != str(k.get("vessel", "")):
			into = id
			break
	Gear.give(s, data, Being.HERO, into, 1)
	var a := LiquidRules.first(c, data, from)
	var b := LiquidRules.first(c, data, into)
	var tool := LiquidRules.needs(data, lid)
	if not tool.is_empty():
		check(steps, LiquidRules.pour_why(c, data, a, b) == "LIQUID_NEEDS", "без набора не перелить: %s" % BackgroundRules.tool_name(data, tool), LiquidRules.pour_why(c, data, a, b))
		c["tools"] = [tool]
		Gear.give(s, data, Being.HERO, tool, 1)
	var why := LiquidRules.pour_why(c, data, a, b)
	if why.is_empty():
		LiquidRules.pour(c, data, a, b)
	check(steps, str(LiquidRules.first(c, data, into).get("liquid", "")) == lid, "переливается: %s → %s" % [from, into], why)
	if k.has("drink"):
		NeedRules.set_value(s, data, "water", 10.0)
		var said := LiquidRules.drink(s, data, Sheet.HERO, LiquidRules.first(c, data, into))
		check(steps, NeedRules.value(s, data, "water") > 10.0 or not k["drink"].has("water"), "пьётся", " · ".join(said))
	else:
		check(steps, LiquidRules.drink_why(data, LiquidRules.first(c, data, into)) == "LIQUID_NOT_DRINK", "это не пьют")
	if k.has("throw"):
		check(steps, str(ItemRules.consumable(data, from).get("throw", {}).get("liquid", "")) == lid, "бросается склянкой: %s" % from)
	if k.has("blade"):
		check(steps, ItemRules.consumable(data, from).has("coat"), "смазывает клинок: %s" % from)
	var g := fight(s, data, "goblin")
	if k.has("coat"):
		LiquidRules.coat(s, data, g, lid, LiquidRules.name_of(data, lid))
		check(steps, str(LiquidRules.coat_on(s, g).get("liquid", "")) == lid, "облитый: %s" % LiquidRules.name_of(data, lid))
		var co: Dictionary = k["coat"]
		if co.has("fire_plus"):
			g["hp"] = 100
			var lines: Array[String] = []
			Harm.typed(s, data, g, 1, "fire", lines, "огонь", false)
			check(steps, int(g["hp"]) <= 100 - 1 - int(co["fire_plus"]), "огонь сильнее на %d" % int(co["fire_plus"]), 100 - int(g["hp"]))
		if co.has("burns"):
			check(steps, LiquidRules.burning(s, g) == str(co["burns"]), "горит %s, пока не собьют" % co["burns"])
		if bool(co.get("douses", false)):
			check(steps, LiquidRules.douses(s, g), "гасит огонь, не загорается")
	if k.has("puddle"):
		var at := FightGrid.cell(g) + Vector2i(1, 0)
		var lines: Array[String] = []
		FightField.splash(s, data, at, {"liquid": lid}, LiquidRules.name_of(data, lid), lines)
		var pool: bool = (s.combat["fires"] as Dictionary).has(FightGrid.tag(at)) if bool(k["puddle"].get("fire", false)) \
			else SpellEffects.zones(s).any(func(z: Dictionary) -> bool: return str(z["spell"]) == "puddle:" + lid)
		check(steps, pool, "пролито на клетку: %s" % ("клетка горит" if bool(k["puddle"].get("fire", false)) else "лужа"), " · ".join(lines))
	return result(steps)


## A ready thing of a liquid (v0.8.4.28): a vessel with its liquid — drunk if it is a drink, poured out into its vessel.
static func _liquid(data: Dictionary, id: String, steps: Array[String]) -> void:
	var s := session(data)
	var c := s.character
	c["inventory"].clear()
	Gear.give(s, data, Being.HERO, id, 2)
	var r := LiquidRules.ready(data, id)
	var k := LiquidRules.kind(data, str(r["liquid"]))
	check(steps, LiquidRules.first(c, data, id)["liquid"] == r["liquid"], "%s в сосуде: %s" % [LiquidRules.name_of(data, str(r["liquid"])), r["vessel"]])
	if k.has("drink"):
		NeedRules.set_value(s, data, "water", 10.0)
		NeedRules.set_value(s, data, "food", 10.0)
		var said := LiquidRules.drink(s, data, Sheet.HERO, LiquidRules.first(c, data, id))
		check(steps, Gear.count(s, data, Being.HERO, id) == 1 and Gear.count(s, data, Being.HERO, str(r["vessel"])) == 1, "выпито, сосуд остался", " · ".join(said))
		if k["drink"].has("water"):
			check(steps, NeedRules.value(s, data, "water") > 10.0, "утоляет жажду", NeedRules.value(s, data, "water"))
		if k["drink"].has("food"):
			check(steps, NeedRules.value(s, data, "food") > 10.0, "немного сытит", NeedRules.value(s, data, "food"))
	else:
		check(steps, LiquidRules.drink_why(data, LiquidRules.first(c, data, id)) == "LIQUID_NOT_DRINK", "это не пьют")
	var before := Gear.count(s, data, Being.HERO, str(r["vessel"]))
	LiquidRules.pour_out(c, data, LiquidRules.first(c, data, id))
	check(steps, Gear.count(s, data, Being.HERO, str(r["vessel"])) == before + 1, "вылито, остался сосуд")


## A light: lit on the belt.
static func _light(data: Dictionary, id: String, steps: Array[String]) -> void:
	var s := session(data)
	var c := s.character
	Gear.give(s, data, Being.HERO, id, 1)
	var why := ItemRules.belt_why(c, data, s.items, id)
	if why.is_empty():
		ItemRules.belt_put(c, data, s.items, id)
	check(steps, SightRules.light(s, data) >= int(data["rules"]["sight"]["lights"][id]), "свет %d клеток с пояса" % int(data["rules"]["sight"]["lights"][id]), "свет %d; %s" % [SightRules.light(s, data), why])


## A tool in a check the master names: the proficiency bonus for one proficient, a required one fails without it.
static func _tool(data: Dictionary, id: String, steps: Array[String]) -> void:
	var s := session(data)
	var c := s.character
	var t: Dictionary = data["rules"]["tools"].get(id, {})
	var skill := str((t.get("skills", ["athletics"]) as Array)[0])
	if bool(t.get("required", false)):
		check(steps, not str(BackgroundRules.tool_check(c, data, id, skill)["auto_fail"]).is_empty(), "без инструмента — провал", "нет провала")
	Gear.give(s, data, Being.HERO, id, 1)
	c["tools"] = [id]
	c["skill_profs"] = []
	var r := BackgroundRules.tool_check(c, data, id, skill)
	check(steps, int(r["bonus"]) > 0, "владение инструментом: +%d к проверке" % int(r["bonus"]), "бонуса нет")
	var used := false
	if ContainerRules.ways(s, data, {"locked": true, "name": "сундук"}).has("pick"):  # thieves' tools: a lock of a chest or a door
		used = check(steps, str(ContainerRules.lock_check(data, {"lock_dc": 15}, "pick").get("tool", "")) == id, "взлом замка", "не тот инструмент")
	var recipes := 0
	for rid: String in data["rules"]["craft"]["recipes"]:
		var rec: Variant = data["rules"]["craft"]["recipes"][rid]
		if rec is Dictionary and str(rec.get("tool", "")) == id:
			recipes += 1
	if recipes > 0:
		used = check(steps, true, "ремесло: %d рецептов" % recipes)
	if bool(t.get("perform", false)):  # an instrument: the show's Performance with it (v0.8.4.26.4)
		var show := BackgroundRules.perform_check(s, data)
		used = check(steps, str(show.get("tool", "")) == id and int(BackgroundRules.tool_check(c, data, id, "performance")["bonus"]) > 0,
			"выступление на сцене: владение в проверке Выступления", "сцена берёт %s" % show.get("tool", "ничего"))
	for kid: String in ContestRules.kinds(data):
		var k := ContestRules.kind(data, kid)
		if str(k.get("tool", "")) == id:
			used = check(steps, str(ContestRules.hero_params(data, k, true).get("tool", "")) == id, "состязание «%s»: и в игре, и в шулерстве" % k["name"], "не в шулерстве")
	var way := LetterRules.way_by(data, "tool", id)
	if not way.is_empty():
		used = check(steps, LetterRules.ways(s, data, "").has(way) and LetterRules.forged(data, way), "подделка: рекомендация в чужую руку в окне письма", "способа письма нет")
	if bool(t.get("wayfinder", false)):
		var wild := ""
		for rid: String in data["world"]["rooms"]:
			if not WorldView.new(data["world"]).flag(rid, "lit"):
				wild = rid
				break
		used = check(steps, BackgroundRules.travel_minutes(s, data, 100, wild) < 100, "дорога вне поселений на четверть короче", "дорога та же")
	if not ItemRules.consumable(data, id, s.items).is_empty():
		used = true  # the kit's own use is probed by _use
	if not used:
		master(steps, "пользоваться — только словами: мастер называет инструмент в проверке, своей кнопки нет")


## A container of the rules: a bag the hero carries, what it holds and how many; a chest or a barrel (`load`) never a
## bag, lifted full only by a beast or a cart; a quiver's arrows at hand for a shot.
static func _container(data: Dictionary, id: String, steps: Array[String]) -> void:
	var k: Dictionary = data["rules"]["containers"]["kinds"][id]
	if str(k.get("size", "")).is_empty():
		gap(steps, "вместимость %d фунтов — только как сундук комнаты; герой не носит её сумкой" % int(k.get("capacity_lb", 0)))
		return
	var s := session(data)
	var c := s.character
	c["inventory"].clear()
	Gear.give(s, data, Being.HERO, id, 1)
	Gear.give(s, data, Being.HERO, "rope", 1)
	ContainerRules.sync_bags(c, data)
	if str(k["size"]) == "load":
		check(steps, ContainerRules.bags(c).is_empty(), "не сумка: герой её не носит", "стала сумкой")
		var full := {"name": "Это", "item_id": id, "container": id, "contents": {"rope": 1}}
		check(steps, not ContainerRules.load_why(data, full).is_empty(), "с вещами поднимет только вьючный зверь или телега", "герой поднимает полной")
		return
	if not check(steps, not ContainerRules.bags(c).is_empty(), "сумка героя: вещи в ней весят меньше", "не стала сумкой"):
		return
	var bag_id: String = ContainerRules.bags(c).keys()[0]
	var bag := ContainerRules.target(s, data, bag_id)
	if k.has("holds"):
		var g: Dictionary = k["holds"][0]
		var first := str(g["ids"][0]) if not (g.get("ids", []) as Array).is_empty() else ""
		if not first.is_empty():
			var n := ContainerRules.room_for(data, s.items, bag, first)
			check(steps, n == int(g["n"]), "вмещает: %s ×%d" % [first, int(g["n"])], n)
		check(steps, ContainerRules.room_for(data, s.items, bag, "rope") == 0, "другое не кладётся", "верёвка влезла")
	if bool(k.get("at_hand", false)):
		var ammo := str(k["holds"][0]["ids"][0])
		Gear.give(s, data, Being.HERO, ammo, 5)
		Thing.move(c, ContainerRules.bags(c)[bag_id], ammo, 5)
		check(steps, Gear.ammo_left(data, c, ammo) == 5, "выстрел берёт из неё: %s под рукой" % ammo, Gear.ammo_left(data, c, ammo))


## The rows of `rules.check_about` a carried thing gives (v0.8.4.27).
static func _about_rows(data: Dictionary, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: String in data["rules"]["check_about"]:
		var row: Variant = data["rules"]["check_about"][key]
		if row is Dictionary and str(row.get("item", "")) == id:
			out.append(row)
	return out


## A thing that helps a check about its subject: the check with it gets advantage or a bonus, without it not.
static func _check_item(data: Dictionary, id: String, steps: Array[String]) -> void:
	for row: Dictionary in _about_rows(data, id):
		var s := session(data)
		var skills: Array = row.get("skills", [])
		var skill := str(skills[0]) if not skills.is_empty() else ("athletics" if (row.get("abilities", []) as Array).has("str") else "")
		var spec := {"what": "проба", "skill": skill, "dc": 10, "about": str(row["about"][0])}
		var before := CheckEngine.situation(s, data, Sheet.HERO, spec, true)
		Gear.give(s, data, Being.HERO, id, 1)
		var after := CheckEngine.situation(s, data, Sheet.HERO, spec, true)
		var gave := (after["adv"] as Array).size() > (before["adv"] as Array).size() or (after["parts"] as Array).size() > (before["parts"] as Array).size()
		var what := "преимущество" if str(row["gives"]) == "advantage" else "+%d" % int(row.get("n", 0))
		check(steps, gave, "проверка «%s» (%s): %s" % [skill, row["about"][0], what], "ничего не дала")


## The hero's own lock: hung on a chest of the room, its key made, the chest opened by it.
static func _own_lock(data: Dictionary, id: String, steps: Array[String]) -> void:
	var s := session(data)
	Gear.give(s, data, Being.HERO, id, 1)
	var p := ContainerRules.lay_down(s, data, s.room_id, "chest", {})
	p["container"] = "chest"
	p["contents"] = {}
	if not check(steps, ContainerRules.lock_ways(s, data, p).has("hang"), "вешается на сундук", "нельзя повесить"):
		return
	ContainerRules.lock_up(s, data, p, "hang")
	check(steps, bool(p["locked"]) and int(p["lock_dc"]) > 0 and Gear.count(s, data, Being.HERO, id) == 0, "свой замок Сл %d, замок потрачен" % int(p["lock_dc"]), p)
	check(steps, ContainerRules.ways(s, data, p).has("key"), "свой ключ у героя открывает", "ключа нет")


## The row of `rules.encounters.bonds` that is this thing ("" — none).
static func _bond_of(data: Dictionary, id: String) -> String:
	for b: String in data["rules"]["encounters"]["bonds"]:
		var row: Variant = data["rules"]["encounters"]["bonds"][b]
		if row is Dictionary and str(row.get("item", "")) == id:
			return b
	return ""


## Bonds of a thing (manacles): harder to get out of than a rope; the hero binds a prisoner with them, they go back when
## it is let go.
static func _bonds(data: Dictionary, id: String, steps: Array[String]) -> void:
	var b := _bond_of(data, id)
	var s := session(data)
	Gear.give(s, data, Being.HERO, id, 1)
	var dc := EncounterRules.escape_dc(data, b, "escape_athletics")
	check(steps, dc > EncounterRules.escape_dc(data, "", "escape_athletics"), "вырваться — Сл %d, верёвка легче" % dc, dc)
	var cr := CreatureRules.add(s, s.room_id, {"name": "Гоблин", "monster": "goblin", "state": "surrendered", "bound": false, "led": false,
		"since": TimeRules.abs_minute(s)})
	CreatureRules.act(s, data, str(cr["id"]), "bind")
	var bound := CreatureRules.find(s, s.room_id, str(cr["id"]))
	check(steps, str(bound.get("bonds", "")) == b and Gear.count(s, data, Being.HERO, id) == 0, "пленник закован", "связан не ими")
	CreatureRules.act(s, data, str(cr["id"]), "free")
	check(steps, Gear.count(s, data, Being.HERO, id) == 1, "отпущен — вещь вернулась", "не вернулась")


## A thing that lights a fire by the sun: the camp's fire with it by day, not without it.
static func _sun_fire(data: Dictionary, id: String, steps: Array[String]) -> void:
	var s := session(data)
	s.character["inventory"].clear()
	var without := WeatherRules.camp_fire(s, data)
	Gear.give(s, data, Being.HERO, id, 1)
	check(steps, not without and WeatherRules.camp_fire(s, data), "разжигает костёр солнцем", "костёр не горит")


## Charges: spent by a use, back at dawn.
static func _charges(data: Dictionary, id: String, d: Dictionary, steps: Array[String]) -> void:
	var s := session(data)
	var c := s.character
	Gear.give(s, data, Being.HERO, id, 1)
	ItemRules.identify(c, data, s.items)
	var full := ItemRules.charges_left(c, d, id)
	check(steps, full == ItemRules.charges_max(d), "зарядов %d" % ItemRules.charges_max(d), full)
	ItemRules.spend_charge(c, data, s.items, id, s.rng)
	var after := ItemRules.charges_left(c, d, id)
	check(steps, after == full - 1, "заряд тратится", after)
	if not (d["charges"] as Dictionary).has("regain"):
		return
	ItemRules.dawn(c, data, s.items, s.rng)
	check(steps, ItemRules.charges_left(c, d, id) > after or Gear.count(s, data, Being.HERO, id) == 0, "заряды возвращаются на рассвете", ItemRules.charges_left(c, d, id))


# --- spells ---------------------------------------------------------------------------------------------------------


## What a spell does in the engine: cast by the sorcerer who knows it (StudyRules.learn_spell, the console's `slots`) in a
## fight at what it aims at — a foe, the hero, a square — until it lands, then out of a fight by the sheet's road. A change
## of the world is looked for: a foe's hit points or statuses, the hero's, the summoned, a zone, a step. A reaction spell is
## asked of its window; nothing in either — the master's words.
static func spell(data: Dictionary, id: String) -> Dictionary:
	var steps: Array[String] = []
	var sp: Dictionary = data["spells"][id]
	var fx := SpellEffects.spec(data, id)
	var slot := maxi(1, int(sp.get("level", 0))) if int(sp.get("level", 0)) > 0 else 0
	var in_fight := ""
	if SpellRules.by_master(data, id):
		steps.append("· в бою не колдуется: только через диалог с мастером")
	elif fx.has("reaction"):
		in_fight = _reaction(data, id, steps)
	elif SpellRules.long_cast(sp):
		steps.append("· в бою не колдуется: время накладывания — минуты")
	else:
		in_fight = _spell_fight(data, id, slot, steps)
	var outside := _spell_world(data, id, slot)
	if not outside.is_empty():
		check(steps, true, "вне боя: " + outside)
	elif in_fight.is_empty():
		if CombatRules.is_engine_spell(data, id) or not ActionRules.way(data, id, true).is_empty():
			check(steps, false, "движок знает заклинание, но проба ничего не изменила")
		elif SpellRules.by_master(data, id):
			master(steps, "только через диалог с мастером (rules.spellcasting.by_master), так и сказано в описании")
		else:
			check(steps, false, "движок не считает, а в rules.spellcasting.by_master его нет")
	else:
		steps.append("· вне боя — рассказ мастера")
	return result(steps)


## A caster of the start pack who knows `id`, every slot free: the sorcerer, the console's `slots` on.
static func caster_session(data: Dictionary, id: String, seed_value := 42) -> GameSession:
	var s := session(data, caster(data), seed_value)
	var c := s.character
	StudyRules.learn_spell(c, id)
	if not Cheats.on(c, "slots"):
		Cheats.toggle(c, "slots")
	CharacterRules.refresh(c, data, s.items)
	return s


## The spell in a fight: the first target it takes, cast until something changes (a missed attack, a save made). What it
## did, or "" when nothing.
static func _spell_fight(data: Dictionary, id: String, slot: int, steps: Array[String]) -> String:
	var last := ""
	var why := ""
	var far := int(data["spells"][id].get("range_ft", 0)) >= 30
	var act := Acts.one("cast")
	var fx := SpellEffects.spec(data, id)
	var side := "ally" if bool(fx.get("other", false)) else "enemy"  # Warding Bond, Spare the Dying: on another of the hero's side
	for attempt in 8:
		for to_kind in 4:
			var s := caster_session(data, id, 42 + attempt * 7 + to_kind)
			var g := fight(s, data, "goblin", far, side)
			g["ac"] = 1
			if attempt % 2 == 1:  # a pool of hit points (Sleep, Color Spray) takes a foe of its own hit points
				g["hp"] = int(Sheet.template(data, g).get("hp", 7))
				g["max_hp"] = g["hp"]
			if fx.has("stabilize"):  # an ally who fell, dying
				g["hp"] = 0
				g["status"] = "down"
			var hero := CombatRules.player(s)
			_prepare_cure(s, data, id)
			if bool(SpellEffects.spec(data, id).get("dispel", false)):  # something to dispel: a spell on the foe and on the hero
				for who: Dictionary in [g, s.character]:
					ConditionRules.add_effect(who, {"condition": "", "ac_plus": 2, "ends": {}, "source": {"kind": "spell", "id": "shield_of_faith", "name": "Щит веры"}})
			turn(s, data, hero)
			var targets := _spell_targets(data, id, g)
			if to_kind >= targets.size():
				break
			var to := targets[to_kind]
			why = act.can(s, data, hero, to, {"spell": id, "slot": slot})
			if not why.is_empty():
				continue
			var before := _world_now(s, data, g)
			var lines := act.go(s, data, hero, to, {"spell": id, "slot": slot})
			var did := _what_changed(data, before, _world_now(s, data, g))
			last = " ".join(lines).left(140)
			if not did.is_empty():
				check(steps, true, "в бою (%s): %s" % [_target_word(to, g), did])
				return did
	if last.is_empty():
		steps.append("· в бою не колдуется: %s" % why)
	else:
		steps.append("· в бою за 8 попыток ничего не изменилось: %s" % last)
	return ""


## What a cure spell lifts lies on the hero first, and the hero is hurt: there is something for it to do.
static func _prepare_cure(s: GameSession, data: Dictionary, id: String) -> void:
	var c := s.character
	c["hp"] = maxi(1, int(c["max_hp"]) / 2)
	var cure: Dictionary = data["rules"]["hero_effects"]["spell_cures"].get(id, {})
	for cond: Variant in cure.get("remove", []):
		ConditionRules.impose(s, data, {"condition": str(cond), "ends": {}, "source": Cheats.SOURCE.duplicate()})
	if (cure.get("cure", []) as Array).has("disease"):
		DiseaseRules.contract(s, data, _disease(data, "magic"))


## Where a spell may go, in the order to try: the hero first for a friendly one, a foe's square for an area, the foe.
static func _spell_targets(data: Dictionary, id: String, g: Dictionary) -> Array[String]:
	var square := FightGrid.aim_id(FightGrid.cell(g))
	var sp: Dictionary = data["spells"][id]
	if sp.has("heal_at_slot") or SpellEffects.picks_side(data, id) == "friend" or SpellEffects.self_spell(data, id):
		return ["", CombatRules.PLAYER, str(g["id"]), square]
	if not CombatRules.area_of(data, id).is_empty():
		return [square, str(g["id"]), ""]
	return [str(g["id"]), square, ""]


static func _target_word(to: String, g: Dictionary) -> String:
	if to.is_empty() or to == CombatRules.PLAYER:
		return "на себя"
	return "по клетке" if FightGrid.is_aim(to) else ("на союзника %s" if str(g.get("side")) == "ally" else "по %s") % g.get("name", "врагу")


## What a probe looks at in a fight: the foe's and the hero's hit points and statuses, the fighters, the zones, the squares.
static func _world_now(s: GameSession, data: Dictionary, g: Dictionary) -> Dictionary:
	var h := s.character
	var hero := CombatRules.player(s)
	return {"g_hp": int(g.get("hp", 0)), "g_fx": _fx_names(data, g), "h_hp": int(h.get("hp", 0)), "h_temp": int(h.get("temp_hp", 0)),
		"h_fx": _fx_names(data, h) + _fx_names(data, hero), "fighters": (s.combat["fighters"] as Array).size(), "zones": (s.combat.get("zones", []) as Array).size(),
		"at": FightGrid.cell(hero), "g_at": FightGrid.cell(g), "g_status": str(g.get("status", "")), "ac": int(h.get("ac", 0)),
		"light": SightRules.light(s, data), "unseen": ConditionRules.invisible(h, data), "flags": (g.keys() as Array).filter(func(k: String) -> bool: return k in FLAGS),
		"g_stable": bool(g.get("death_saves", {}).get("stable", false))}


## Flags a spell leaves on a fighter beside its statuses: a mark, a hex, a sanctuary, a cover of fire.
const FLAGS: Array[String] = ["marked", "hexed", "sanctuary", "outlined", "hidden", "frightened_by", "turned", "charmed_by"]


static func _fx_names(data: Dictionary, h: Dictionary) -> Array:
	var out: Array = []
	for e: Dictionary in ConditionRules.effects(h):
		var name := str(e.get("condition", ""))
		out.append(ConditionRules.name_of(data, name) if not name.is_empty() else str(e.get("source", {}).get("name", "эффект")))
	return out


## What changed between two looks, in words ("" — nothing).
static func _what_changed(_data: Dictionary, a: Dictionary, b: Dictionary) -> String:
	var out: Array[String] = []
	if int(b["g_hp"]) < int(a["g_hp"]):
		out.append("урон врагу −%d" % (int(a["g_hp"]) - int(b["g_hp"])))
	for n: Variant in b["g_fx"]:
		if not (a["g_fx"] as Array).has(n):
			out.append("на враге: %s" % n)
	if str(b["g_status"]) != str(a["g_status"]):
		out.append("враг: %s" % b["g_status"])
	if int(b["h_hp"]) > int(a["h_hp"]):
		out.append("лечит +%d" % (int(b["h_hp"]) - int(a["h_hp"])))
	if int(b["h_temp"]) > int(a["h_temp"]):
		out.append("временные хиты +%d" % (int(b["h_temp"]) - int(a["h_temp"])))
	for n: Variant in b["h_fx"]:
		if not (a["h_fx"] as Array).has(n):
			out.append("на герое: %s" % n)
	if int(b["ac"]) != int(a["ac"]):
		out.append("КД %d → %d" % [a["ac"], b["ac"]])
	if int(b["fighters"]) > int(a["fighters"]):
		out.append("призвано: %d" % (int(b["fighters"]) - int(a["fighters"])))
	if int(b["zones"]) > int(a["zones"]):
		out.append("зона на поле")
	if b["at"] != a["at"]:
		out.append("перенос героя")
	if b["g_at"] != a["g_at"]:
		out.append("враг сдвинут")
	if int(b["light"]) > int(a["light"]):
		out.append("свет")
	if bool(b["unseen"]) and not bool(a["unseen"]):
		out.append("герой невидим")
	for k: Variant in b["flags"]:
		if not (a["flags"] as Array).has(k):
			out.append("метка: %s" % k)
	if bool(b["g_stable"]) and not bool(a["g_stable"]):
		out.append("стабилизирован")
	return ", ".join(out)


## A reaction spell: the window the engine opens for it in a foe's turn (Acts.react's offers).
static func _reaction(data: Dictionary, id: String, steps: Array[String]) -> String:
	var s := caster_session(data, id)
	var g := fight(s, data, "goblin")
	var when := str(SpellEffects.spec(data, id).get("reaction", ""))
	var ok := false
	if when == "fall":  # Feather Fall: a fall of 20 hurts nothing (v0.8.4.26.2)
		var hp := int(s.character["hp"])
		var lines: Array[String] = []
		CombatRules.fall(s, data, CombatRules.player(s), "20", "падает", {"kind": "engine", "name": "падение"}, lines)
		ok = check(steps, int(s.character["hp"]) == hp, "реакция на падение: %s" % ", ".join(lines).left(90), hp - int(s.character["hp"]))
	elif when == "spell":
		ok = check(steps, not SpellEffects.counter_option(s, data, g, "magic_missile").is_empty(), "реакция: окно на заклинание врага", "окна нет")
	else:
		var ac := int(s.character.get("ac", 10))
		var offers := SpellEffects.hit_reactions(s, data, {"total": ac + 1, "ac": ac, "nat20": false, "dmg": 5})
		ok = check(steps, offers.any(func(o: Dictionary) -> bool: return str(o["id"]) == "spell_" + id), "реакция: окно «%s» на удар врага" % when, "окна нет")
	return "реакция" if ok else ""


## The spell out of a fight by the sheet's road (SpellRules.cast on oneself, the summoned): what the engine did beside the
## line of the cast, or "".
static func _spell_world(data: Dictionary, id: String, slot: int) -> String:
	var s := caster_session(data, id)
	var c := s.character
	if not LetterRules.way_by(data, "spell", id).is_empty():
		return _spell_letter(s, data, id)
	_prepare_cure(s, data, id)  # something to cure, to know, to fill and to clean (v0.8.4.26.2)
	ItemRules.found(c, data, s.items, "ring_of_warmth")  # comes unidentified
	LiquidRules.drain(c)
	var chk := SpellRules.check(c, data, id, slot)
	if chk.has("reason"):
		return ""
	var light := SightRules.light(s, data)
	var lines := SpellRules.cast(c, data, str(chk["spell_id"]), int(chk["slot"]), s, true)
	lines.append_array(AllyRules.summon(s, data, str(chk["spell_id"])))
	var did: Array[String] = []
	for l: String in lines.slice(1):
		if l != "концентрация" and not l.begins_with("концентрация на"):
			did.append(l)
	if SightRules.light(s, data) > light:
		did.append("свет")
	if did.is_empty() and bool(SpellEffects.spec(data, str(chk["spell_id"])).get("npc_save", false)):
		did.append(_spell_npc(s, data, str(chk["spell_id"])))
	return "; ".join(did).left(160)


## A spell that carries a word (Sending, v0.8.4.26.3): a letter to one met in another room, sent by the hero itself.
static func _spell_letter(s: GameSession, data: Dictionary, id: String) -> String:
	for rid: String in data["world"]["rooms"]:
		if rid != s.room_id and not (data["world"]["rooms"][rid].get("npcs", []) as Array).is_empty():
			s.visited.append(rid)
			break
	var to := LetterRules.recipients(s, data)
	if to.is_empty():
		return ""
	var way := LetterRules.way_by(data, "spell", id)
	var why := LetterRules.send_why(s, data, "", to[0], "ties", "Жив, здоров, иду к вам.", way)
	return why if not why.is_empty() else "; ".join(LetterRules.send(s, data, "", to[0], "ties", "Жив, здоров, иду к вам.", way)).left(160)


## A spell on a person out of a fight (Zone of Truth): its save by the engine, what holds stays on it.
static func _spell_npc(s: GameSession, data: Dictionary, id: String) -> String:
	var here := s.npcs_here(data["world"], s.room_id)
	if here.is_empty():
		return ""
	var r := SpellEffects.npc_save(s, data, id, here[0])
	if bool(r.get("ok", false)):
		SpellEffects.charm_npc(s, data, id, here[0])
	return str(r.get("line", ""))


# --- monsters -------------------------------------------------------------------------------------------------------


## A monster of the SRD in a fight against the hero who cannot fall (the console's `god`): its hit points and AC by the data,
## each action struck at the hero by the attack act until it lands, the rest asked of the AI's offers; its traits and
## reactions read by the engine or only in its text; its spells cast.
static func monster(data: Dictionary, mid: String) -> Dictionary:
	var steps: Array[String] = []
	var m: Dictionary = data["monsters"][mid]
	var s := _monster_fight(data, mid)
	var f := _monster_in(s, mid)
	if not check(steps, not f.is_empty(), "встаёт в бой", "нет бойца"):
		return result(steps)
	check(steps, int(f.get("max_hp", 0)) == int(m.get("hp", 0)), "хиты %d" % int(m.get("hp", 0)), f.get("max_hp"))
	check(steps, CombatRules.ac_of(f) >= int(m.get("ac", 0)), "КД %d" % int(m.get("ac", 0)), CombatRules.ac_of(f))
	var offered := _offered(s, data, f)
	for a: Dictionary in m.get("actions", []):
		_monster_action(data, mid, a, offered, steps)
	for t: Dictionary in m.get("traits", []):
		var tid := str(t.get("id", ""))
		if tid.is_empty() or m.has(str(t.get("into", ""))):  # read into its `spellcasting`: checked by its spells below
			continue
		if BY_ACT.has(tid):
			if Acts.one(str(BY_ACT[tid])).shown(s, data, f):
				check(steps, true, "черта «%s» — в движке: %s" % [t.get("name", tid), Acts.one(str(BY_ACT[tid])).title()])
			else:
				gap(steps, "черта «%s» — только текст" % t.get("name", tid))
		elif t.has("check"):  # told apart by a check whose DC the trait gives (CheckEngine.trait_dc)
			check(steps, true, "черта «%s» — проверка Сл %d в движке" % [t.get("name", tid), int(t["check"]["dc"])])
		elif _known(data, tid):
			check(steps, true, "черта «%s» — в движке" % t.get("name", tid))
		else:
			gap(steps, "черта «%s» — только текст" % t.get("name", tid))
	for r: Dictionary in m.get("reactions", []):
		var rid := str(r.get("id", str(r.get("name_en", "")).to_snake_case()))
		if _known(data, rid) or offered.has(str(r.get("name_en", ""))) or Acts.all().any(func(x: Act) -> bool: return x.id == rid):
			check(steps, true, "реакция «%s» — в движке" % r.get("name", rid))
		else:
			gap(steps, "реакция «%s» — только текст" % r.get("name", rid))
	if m.has("spellcasting"):
		_monster_spells(data, mid, steps)
	return result(steps)


static func _monster_fight(data: Dictionary, mid: String, seed_value := 42) -> GameSession:
	var s := session(data, 0, seed_value)
	Cheats.toggle(s.character, "god")
	CombatRules.start(s, data, [{"monster": mid, "x": 41, "y": 30}], {"field": {"w": 80, "h": 60}})
	var p := CombatRules.player(s)
	p["x"] = 40
	p["y"] = 30
	return s


static func _monster_in(s: GameSession, mid: String) -> Dictionary:
	for id: String in s.combat["fighters"]:
		var f := CombatRules.fighter(s, id)
		if str(f.get("monster", "")) == mid:
			return f
	return {}


## The actions the AI's acts offer it now, by their SRD names.
static func _offered(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	turn(s, data, f)
	var targets: Array[Dictionary] = [CombatRules.player(s)]
	for a: Act in Acts.all():
		for o: Dictionary in a.offers(s, data, f, targets):
			var how: Dictionary = o.get("how", {})
			for k: String in ["action", "name", "id", "spell", "item"]:
				if how.has(k):
					out.append(str(how[k]))
			out.append(str(o.get("kind", "")))
	return out


## One action of a monster at the hero: an attack or a save it forces, until it hurts or lays something; one with neither,
## offered by the AI or only in the text.
static func _monster_action(data: Dictionary, mid: String, a: Dictionary, offered: Array[String], steps: Array[String]) -> void:
	var name_en := str(a.get("name_en", ""))
	var name := str(a.get("name", name_en))
	var probe := _monster_fight(data, mid)
	var f := _monster_in(probe, mid)
	if Attack.way(probe, data, f, {"action": name_en}).is_empty():
		if offered.has(name_en) or offered.has(name):
			check(steps, true, "«%s» — ИИ им пользуется" % name)
		elif a.has("recharge") or a.has("effect"):
			check(steps, _known(data, name_en.to_snake_case()) or not (a.get("effect", {}) as Dictionary).is_empty(), "«%s» — эффект в данных" % name, "не разобран")
		else:
			gap(steps, "«%s» — только текст" % name)
		return
	var last := ""
	for attempt in 8:
		var s := _monster_fight(data, mid, 42 + attempt * 13)
		var m := _monster_in(s, mid)
		s.character["ac"] = 1
		if int(Attack.way(s, data, m, {"action": name_en}).get("reach", 1)) == 0:  # a swarm's 0 ft: in the hero's own square
			FightGrid.put(m, FightGrid.cell(CombatRules.player(s)))
		var before := _world_now(s, data, m)
		turn(s, data, m)
		var why := Acts.one("attack").can(s, data, m, CombatRules.PLAYER, {"action": name_en})
		if not why.is_empty():
			steps.append("· «%s»: %s" % [name, why])
			return
		var lines := Acts.one("attack").go(s, data, m, CombatRules.PLAYER, {"action": name_en})
		var now := _world_now(s, data, m)
		last = " ".join(lines).left(120)
		if int(now["h_hp"]) < int(before["h_hp"]) or (now["h_fx"] as Array).size() > (before["h_fx"] as Array).size():
			check(steps, true, "«%s» по герою: %s" % [name, _hero_hurt(before, now)])
			return
	check(steps, false, "«%s» по герою" % name, "за 8 попыток ни урона, ни эффекта: " + last)


static func _hero_hurt(a: Dictionary, b: Dictionary) -> String:
	var out: Array[String] = []
	if int(b["h_hp"]) < int(a["h_hp"]):
		out.append("−%d HP" % (int(a["h_hp"]) - int(b["h_hp"])))
	for n: Variant in b["h_fx"]:
		if not (a["h_fx"] as Array).has(n):
			out.append(str(n))
	return ", ".join(out)


## The spells of a caster monster: each it can cast (MonsterRules.castable) cast once at the hero or itself.
static func _monster_spells(data: Dictionary, mid: String, steps: Array[String]) -> void:
	var listed: Array = (data["monsters"][mid]["spellcasting"].get("spells", []) as Array).map(func(x: Variant) -> String: return str(x.get("id", "")) if x is Dictionary else str(x))
	var s := _monster_fight(data, mid)
	var f := _monster_in(s, mid)
	var can: Array = MonsterRules.castable(data, f).map(func(o: Dictionary) -> String: return str(o["id"]))
	var missing := listed.filter(func(id: String) -> bool: return not data["spells"].has(id))
	if not missing.is_empty():
		steps.append("· заклинаний нет в игре, у него их нет: %s" % ", ".join(missing))
	check(steps, not can.is_empty(), "колдует в бою: %d из %d" % [can.size(), listed.size()], "ничего")
	var worked: Array[String] = []
	var idle: Array[String] = []
	for o: Dictionary in MonsterRules.castable(data, f):
		var s2 := _monster_fight(data, mid)
		var f2 := _monster_in(s2, mid)
		var before := _world_now(s2, data, f2)
		turn(s2, data, f2)
		var how := {"spell": str(o["id"])}
		how.merge(o)
		var to := CombatRules.PLAYER
		if not Acts.one("cast").can(s2, data, f2, to, how).is_empty():
			to = ""
		Acts.one("cast").go(s2, data, f2, to, how)
		var did := _what_changed(data, before, _world_now(s2, data, f2))
		var hurt := _hero_hurt(before, _world_now(s2, data, f2))
		(worked if not did.is_empty() or not hurt.is_empty() else idle).append(str(data["spells"][str(o["id"])]["name"]))
	if not worked.is_empty():
		check(steps, true, "заклинания действуют: %s" % ", ".join(worked))
	if not idle.is_empty():
		steps.append("· без видимого эффекта с первой попытки: %s" % ", ".join(idle))


## A trait, a reaction or an action id the engine knows: named in core/ or a key of the rules or the riders.
static func _known(data: Dictionary, id: String) -> bool:
	return not reads(id).is_empty() or _rules_text(data).contains("\"%s\"" % id)


static var _rules_json := ""


static func _rules_text(data: Dictionary) -> String:
	if _rules_json.is_empty():
		_rules_json = JSON.stringify(data["rules"])
	return _rules_json


# --- abilities ------------------------------------------------------------------------------------------------------


## A class feature on the hero (as the console's `feature` puts it): its actions of rules.feature_actions done in a fight,
## its uses of rules.resources, else what reads it — the engine's code or a row of the rules; nothing — the master's words
## (the sheet's «feature_note»).
static func feature(data: Dictionary, fid: String) -> Dictionary:
	return _ability(data, fid, "features")


## A race trait on the hero, as a feature.
static func race_trait(data: Dictionary, tid: String) -> Dictionary:
	return _ability(data, tid, "traits")


static func _ability(data: Dictionary, id: String, list: String) -> Dictionary:
	var steps: Array[String] = []
	var d: Dictionary = data["classes"]["features"].get(id, {}) if list == "features" else data["races"]["traits"].get(id, {})
	for aid: String in data["rules"]["feature_actions"]:
		var row: Variant = data["rules"]["feature_actions"][aid]
		if row is Dictionary and ((row.get("features", []) as Array).has(id) or str(row.get("feature", "")) == id or str(row.get("trait", "")) == id):
			_feature_act(data, id, list, aid, steps)
	for rid: String in Stock.table(data):
		var row: Variant = Stock.table(data)[rid]
		if row is Dictionary and (row.get("features", []) as Array).has(id):
			_feature_stock(data, id, list, rid, steps)
	if d.has("skill"):  # a skill proficiency of a feature, read by «skill_prof_» + the skill
		var s := session(data)
		var skill := str(d["skill"])
		s.character["skill_profs"] = (s.character.get("skill_profs", []) as Array).filter(func(x: Variant) -> bool: return str(x) != skill)
		CharacterRules.refresh(s.character, data, s.items)
		var bare := Sheet.skill(s, data, Sheet.HERO, skill)
		var with := Sheet.skill(_ability_session(data, id, list, s), data, Sheet.HERO, skill)
		check(steps, with > bare, "навык %s: %+d → %+d" % [skill, bare, with], with)
	if id.begins_with("extra_attack"):  # the class table's attacks, read by CharacterRules.extra_attacks
		var s := _ability_session(data, id, list)
		check(steps, CharacterRules.extra_attacks(s.character, data) > 0, "дополнительная атака: %d" % CharacterRules.extra_attacks(s.character, data), 0)
	_roads(data, id, d, list, steps)
	if steps.any(func(st: String) -> bool: return st.begins_with("✓") or st.begins_with("✗")):
		return result(steps)
	var why := _read_by(data, id, d, list)
	if not why.is_empty():
		check(steps, true, why)
	else:
		master(steps, "движок не знает: на листе как умение для мастера (по описанию)")
	return result(steps)


## The engine's roads of a feature or a trait by the rows that name it (v0.8.4.26.1): spells always prepared, a check by its
## subject, a language, what it lays for good, a fall slowed, a foe walked through, a course made cheaper, a turn that
## destroys, Flexible Casting — each done on a hero that has it.
static func _roads(data: Dictionary, id: String, d: Dictionary, list: String, steps: Array[String]) -> void:
	var rules: Dictionary = data["rules"]
	var parent := str(d.get("parent", ""))
	if rules["spellcasting"].get("feature_always", {}).has(id):
		var s := _ability_session(data, id, list)
		var want: Array[String] = []
		for lv: String in rules["spellcasting"]["feature_always"][id]:
			for sp: Variant in rules["spellcasting"]["feature_always"][id][lv]:
				want.append(str(sp))
		var got := LevelUp.always(s.character, data, 5)
		check(steps, want.all(func(x: String) -> bool: return got.has(x)), "всегда подготовлены к 5 уровню: %s" % ", ".join(want.map(func(x: String) -> String: return str(data["spells"][x]["name"]))), got)
	for key: String in rules.get("check_about", {}):
		var row: Variant = rules["check_about"][key]
		if row is Dictionary and (str(row.get("trait", "")) == id or (not parent.is_empty() and str(row.get("parent", "")) == parent)):
			_about(data, id, d, list, row, steps)
	for key: String in [id, parent]:
		for lang: Variant in rules["languages"].get("by_feature", {}).get(key, []):
			var s := _ability_session(data, id, list)
			check(steps, LanguageRules.hero(s.character, data).has(str(lang)), "язык: %s" % LanguageRules.name_of(data, str(lang)))
	if rules.get("feature_wear", {}).has(id):
		var s := _ability_session(data, id, list)
		var e: Array = ConditionRules.effects(s.character).filter(func(x: Dictionary) -> bool: return str(x["source"].get("id", "")) == id)
		check(steps, not e.is_empty(), "своё навсегда: %s" % SpellEffects.text(data, e[0] if not e.is_empty() else {}), "не легло")
		if rules["feature_wear"][id].has("climb_speed"):
			check(steps, Move.speeds(s, data, Sheet.HERO).has("climb"), "лазание %d фт" % int(Move.speeds(s, data, Sheet.HERO).get("climb", 0)))
	if FightGrid.cfg(data).get("slow_fall", {}).has(id):
		var s := _ability_session(data, id, list)
		fight(s, data, "goblin", true)
		var hp := int(s.character["hp"])
		var lines: Array[String] = []
		CombatRules.fall(s, data, CombatRules.player(s), "10", "падает", {"kind": "engine", "name": "падение"}, lines)
		check(steps, int(s.character["hp"]) > hp - 10, "падение 10: %s" % ", ".join(lines).left(90), hp - int(s.character["hp"]))
	if FightGrid.cfg(data).get("pass_foe", {}).get("larger_by", {}).has(id):
		var s := _ability_session(data, id, list)
		s.character["race"] = "halfling"
		var foe := fight(s, data, "bandit")
		var p := CombatRules.player(s)
		check(steps, FightGrid.passable(s, data, p, int(Move.opts(s, data, p)["larger_by"])).has(FightGrid.cell(foe)), "проходит сквозь клетку большего врага (разбойник)")
	if StudyRules.cfg(data).get("savant", {}).has(id):
		_savant(data, id, list, StudyRules.cfg(data)["savant"][id], steps)
	for aid: String in rules["feature_actions"]:
		var fa: Variant = rules["feature_actions"][aid]
		for fx: Variant in fa.get("effects", []) if fa is Dictionary else []:
			if fx is Dictionary and (fx.get("destroy", []) as Array).has(id):
				var s := _ability_session(data, id, list)
				var cr := float(CharacterRules.level_row(s.character, data).get("class_specific", {}).get("destroy_undead_cr", 0))
				check(steps, cr > 0.0, "«%s» уничтожает нежить с опасностью до %s (таблица класса)" % [fa.get("name", aid), cr], cr)
	var font: Dictionary = FeatureRules.cfg(data).get("font_of_magic", {})
	if id in [str(font.get("create_with", "")), str(font.get("convert_with", ""))]:
		var s := _ability_session(data, "font_of_magic", list)
		var c := s.character
		Stock.spend(c, "slot_1")
		if id == str(font.get("convert_with", "")):  # a slot to points needs points spent; points to a slot needs them left
			Stock.spend(c, "sorcery_points")
		var bare := FeatureRules.font_options(c, data).size()
		(c["features"] as Array).append(id)
		check(steps, FeatureRules.font_options(c, data).size() > bare, "источник магии: %d → %d вариантов" % [bare, FeatureRules.font_options(c, data).size()])


## A check by its subject on the hero with the feature or the trait: advantage, or the proficiency twice.
static func _about(data: Dictionary, id: String, d: Dictionary, list: String, row: Dictionary, steps: Array[String]) -> void:
	var s := _ability_session(data, id, list)
	var about := str(d.get("creature_type", "")) if str(row.get("about", "")) == "creature_type" else str((row["about"] as Array)[0])
	var spec := {"about": about}
	if not (row.get("skills", []) as Array).is_empty():
		spec["skill"] = str(row["skills"][0])
	else:
		spec["ability"] = str(row["abilities"][0])
	var what := str(spec.get("skill", spec.get("ability", "")))
	if str(row["gives"]) == "advantage":
		var with := CheckEngine.situation(s, data, Sheet.HERO, spec)
		var bare := CheckEngine.situation(s, data, Sheet.HERO, spec.merged({"about": "nothing"}, true))
		check(steps, (with["adv"] as Array).size() > (bare["adv"] as Array).size(), "проверка «%s» о «%s»: преимущество" % [what, about])
		return
	if spec.has("skill"):
		s.character["skill_profs"] = (s.character.get("skill_profs", []) as Array) + [spec["skill"]]
	else:  # a bare ability: Charisma checks by a proficient skill of it (Persuasion)
		spec.erase("ability")
		spec["skill"] = "persuasion"
		s.character["skill_profs"] = (s.character.get("skill_profs", []) as Array) + ["persuasion"]
	CharacterRules.refresh(s.character, data, s.items)
	var more := RollParts.sum(CheckEngine.situation(s, data, Sheet.HERO, spec)["parts"]) - RollParts.sum(CheckEngine.situation(s, data, Sheet.HERO, spec.merged({"about": "nothing"}, true))["parts"])
	check(steps, more > 0, "проверка «%s» о «%s»: мастерство дважды (+%d)" % [str(spec["skill"]), about, more], more)


## A spell course of the savant's school costs less: the pack's spell course, its spell swapped for one of the school.
static func _savant(data: Dictionary, id: String, list: String, row: Dictionary, steps: Array[String]) -> void:
	var course := ""
	var spell := ""
	for cid: String in data["world"].get("courses", {}):
		if str(data["world"]["courses"][cid].get("teaches", {}).get("kind", "")) == "spell":
			course = cid
	for sid: String in data["spells"]:
		if str(data["spells"][sid].get("school_id", "")) == str(row["school_id"]) and int(data["spells"][sid].get("level", 0)) > 0:
			spell = sid
			break
	if not check(steps, not course.is_empty() and not spell.is_empty(), "курс заклинания в пакете", "нет"):
		return
	var teaches: Dictionary = data["world"]["courses"][course]["teaches"]
	var was := str(teaches["id"])
	teaches["id"] = spell
	var fee := StudyRules.fee(session(data), data, course)
	var now := StudyRules.fee(_ability_session(data, id, list), data, course)
	teaches["id"] = was
	check(steps, now < fee, "курс «%s»: плата %s → %s" % [data["spells"][spell]["name"], Money.format(fee), Money.format(now)], now)


## The fields of a feature or a trait the character's building reads (CharacterBuilder, LevelUp): a choice, a grant.
const GRANTS: Array[String] = ["weapons", "skills", "tools", "skill_choice", "language_choice", "spell_choice", "tool_choice", "options",
	"expertise", "damage_type", "languages", "spells"]
## A numbered id of the SRD (extra_attack_1, song_of_rest_d6): the engine reads its stem.
static var NUMBERED := RegEx.create_from_string("_d?\\d+$")
## The name of a feature that is the choice of a subclass at its level (an archetype, a path, a domain…).
static var SUBCLASS_WORDS := RegEx.create_from_string("Archetype|Path|Tradition|Oath|College|Domain$|Circle$|Origin|Patron")
## Prefixes of ids the engine reads by their tail: a fighting style by `CharacterRules.style`, a metamagic by its name.
const TAILS: Array[String] = ["fighter_fighting_style_", "ranger_fighting_style_", "paladin_fighting_style_", "fighting_style_", "metamagic_",
	"draconic_ancestry_", "natural_explorer_"]


## What of the engine reads a feature that has no action and no stock: words, or "" when nothing.
static func _read_by(data: Dictionary, id: String, d: Dictionary, list: String) -> String:
	var files := reads(id)
	if not files.is_empty():
		return "движок читает (код): %s" % ", ".join(files.slice(0, 4))
	var stem := NUMBERED.sub(id, "")
	if stem != id and not reads(stem).is_empty():
		return "движок читает «%s» (%s)" % [stem, ", ".join(reads(stem).slice(0, 3))]
	for pre: String in TAILS:
		if id.begins_with(pre):
			var by := reads(id.trim_prefix(pre)) + reads(pre)
			if not by.is_empty():
				return "движок читает по имени «%s» (%s)" % [id.trim_prefix(pre), ", ".join(by.slice(0, 3))]
	var build := _builder_code()
	for g: String in GRANTS:
		if d.has(g) and build.contains("\"%s\"" % g):
			return "при создании или повышении: «%s» (CharacterBuilder / LevelUp)" % g
	if id.contains("ability_score_improvement"):
		return "увеличение характеристик при повышении (LevelUp)"
	var cls: Dictionary = data["classes"]["classes"].get(str(d.get("class", "")), {})
	if list == "features" and not d.has("subclass") and int(cls.get("subclass_level", 0)) == int(d.get("level", -1)) \
			and SUBCLASS_WORDS.search(str(d.get("name_en", ""))) != null and not id.contains("spells"):
		return "выбор подкласса на %d уровне (LevelUp)" % int(d.get("level", 0))
	if list == "features" and str(d.get("name_en", "")).ends_with(" feature") and (cls.get("subclasses", []) as Array).any(func(x: Variant) -> bool:
			return not (data["classes"]["subclasses"].get(str(x), {}).get("features", {}).get(str(int(d.get("level", 0))), []) as Array).is_empty()):
		return "особенность подкласса на %d уровне: умения подкласса этого уровня (LevelUp.features_at)" % int(d.get("level", 0))
	if id.begins_with("spellcasting_") and cls.has("spellcasting"):
		return "заклинания класса: ячейки и списки по таблице класса"
	if id.contains("spells") and (cls.get("subclasses", []) as Array).any(func(x: Variant) -> bool: return data["classes"]["subclasses"].get(str(x), {}).has("spells")):
		return "заклинания подкласса всегда готовы (LevelUp: subclass_spells)"
	if _rules_text(data).contains("\"%s\"" % id):
		return "есть в правилах (rules.json)"
	return ""


static var _build_src := ""


static func _builder_code() -> String:
	if _build_src.is_empty():
		for f: String in ["res://core/character/character_builder.gd", "res://core/character/level_up.gd"]:
			_build_src += FileAccess.get_file_as_string(f)
	return _build_src


## The hero with the feature or the trait put on as the console's `feature` / `trait` does, of the feature's class and level
## (a stock grows with them); `s` — a game to put it into, a fresh one by default.
static func _ability_session(data: Dictionary, id: String, list: String, s: GameSession = null) -> GameSession:
	if s == null:
		s = session(data)
	var c := s.character
	var d: Dictionary = data["classes"]["features"].get(id, {}) if list == "features" else {}
	if not str(d.get("class", "")).is_empty():
		c["class"] = str(d["class"])
		c["level"] = maxi(int(c.get("level", 1)), int(d.get("level", 1)))
		if d.has("subclass"):
			c["subclass"] = str(d["subclass"])
	var have: Array = c.get(list, [])
	if not have.has(id):
		have.append(id)
	c[list] = have
	CharacterRules.refresh(c, data, s.items)
	return s


## A feature action in a fight at the goblin or on the hero: allowed and done, or why not.
static func _feature_act(data: Dictionary, id: String, list: String, aid: String, steps: Array[String]) -> void:
	var s := _ability_session(data, id, list)
	var g := fight(s, data, "goblin")
	var hero := CombatRules.player(s)
	turn(s, data, hero)
	if bool(data["rules"]["feature_actions"][aid].get("dark", false)):  # in a dark room of the pack, no light in hand
		for r: String in data["world"]["rooms"]:
			if WorldView.new(data["world"]).flag(r, "dark"):
				s.room_id = r
				break
		s.character["belt"] = ["", "", "", "", ""]
	var act := Acts.one("feature")
	var name := str(data["rules"]["feature_actions"][aid].get("name", aid))
	for to: String in [str(g["id"]), ""]:
		var why := act.can(s, data, hero, to, {"id": aid})
		if why.is_empty():
			var before := _world_now(s, data, g)
			var lines := act.go(s, data, hero, to, {"id": aid})
			var did := _what_changed(data, before, _world_now(s, data, g))
			check(steps, not lines.is_empty(), "действие «%s» в бою%s" % [name, ": " + did if not did.is_empty() else ""], "ничего не сказало")
			return
	steps.append("· действие «%s»: %s (нужны условия пробы)" % [name, act.can(s, data, hero, str(g["id"]), {"id": aid})])
	check(steps, true, "действие «%s» есть (rules.feature_actions)" % name)


## A use of a feature's stock: as many as the rules say, spent by a press.
static func _feature_stock(data: Dictionary, id: String, list: String, rid: String, steps: Array[String]) -> void:
	var s := _ability_session(data, id, list)
	var c := s.character
	var n := Stock.max_uses(c, data, rid)
	if not check(steps, n > 0, "запас «%s»: %d" % [Stock.display_name(c, data, rid), n], "0 — не выдан"):
		return
	var spell := str(Stock.table(data)[rid].get("spell", ""))
	if not spell.is_empty():  # the charges of a feature's spell: spent by casting it at will (v0.8.4.26.1)
		var chk := SpellRules.check(c, data, spell, 0)
		if check(steps, int(chk.get("slot", -1)) == 0, "«%s» без ячейки" % data["spells"][spell]["name"], chk.get("reason", "")):
			SpellRules.cast(c, data, spell, 0, s)
			check(steps, Stock.left(c, data, rid) == n - 1 and SpellRules.check(c, data, spell, 0).has("reason"), "сотворено: заряд потрачен, до долгого отдыха нельзя", Stock.left(c, data, rid))
		return
	var why := Stock.can_use(c, data, rid, 1)
	if why.is_empty():
		var lines := Stock.use(c, data, rid, 1, s.rng, s)
		check(steps, Stock.left(c, data, rid) == n - 1, "трата: %s" % ", ".join(lines).left(100), Stock.left(c, data, rid))
	else:
		steps.append("· трата «%s»: %s" % [rid, why])


# --- conditions -----------------------------------------------------------------------------------------------------


## A status laid by the console's road (ConditionRules.impose) on the hero and on a goblin of a fight, then each field of its
## row of rules.condition_effects done by the engine: checks, saves, senses, attacks by it and at it, speed, resistance, a
## critical hit; the SRD conditions without a row (charmed, incapacitated, invisible, exhaustion) by their own rules.
static func condition(data: Dictionary, id: String) -> Dictionary:
	var steps: Array[String] = []
	var s := session(data)
	var g := fight(s, data, "goblin")
	var hero := CombatRules.player(s)
	var h := s.character
	var blow := Cheats.blow(_spec(false))
	var by_me := Attack.mods(s, data, hero, g, blow)
	var at_me := Attack.mods(s, data, g, hero, blow)
	if id == "exhaustion":
		_exhaustion(s, data, g, steps)
		return result(steps)
	var e := {"condition": id, "ends": {}, "source": Cheats.SOURCE.duplicate()}
	if id == "charmed":
		e["by"] = str(g["id"])
	ConditionRules.impose(s, data, e)
	if not check(steps, ConditionRules.has(h, id), "ложится на героя", "не легло"):
		return result(steps)
	ConditionRules.impose(s, data, e.duplicate(), g)
	check(steps, ConditionRules.has(g, id), "ложится на врага", "не легло")
	var row: Dictionary = data["rules"]["condition_effects"].get(id, {})
	var known := false
	for key: String in ["checks", "skills", "senses"]:
		if not row.has(key):
			continue
		known = true
		var asks: Dictionary = {"athletics": row[key]} if key == "checks" else row[key]
		for what: String in asks:
			var spec := {"skill": what} if key != "senses" else {"skill": "perception", "sense": what}
			var sit := CheckEngine.situation(s, data, Sheet.HERO, spec, true)
			var mode := str(asks[what])
			check(steps, not (sit["fail" if mode == "auto_fail" else "dis"] as Array).is_empty(), "%s %s: %s" % [key, what, MODE_WORDS.get(mode, mode)], "нет")
	for ab: String in row.get("saves", {}):
		known = true
		var mode := str(row["saves"][ab])
		var odds := Sheet.save_odds(s, data, Sheet.HERO, ab)
		check(steps, bool(odds["failed"]) if mode == "auto_fail" else bool(odds["dis"]), "спасбросок %s: %s" % [ab, MODE_WORDS.get(mode, mode)], "нет")
	var now_me := Attack.mods(s, data, hero, g, blow)
	var now_at := Attack.mods(s, data, g, hero, blow)
	if row.has("attack"):
		known = true
		var k := "adv" if str(row["attack"]) == "advantage" else "dis"
		check(steps, (now_me[k] as Array).size() > (by_me[k] as Array).size(), "его атаки: %s" % MODE_WORDS[str(row["attack"])], now_me)
	for key: String in ["attacked", "attacked_near"]:
		if row.has(key):
			known = true
			var k := "adv" if str(row[key]) == "advantage" else "dis"
			check(steps, (now_at[k] as Array).size() > (at_me[k] as Array).size(), "атаки по нему вблизи: %s" % MODE_WORDS[str(row[key])], now_at)
	if row.has("attacked_far"):
		known = true
		g["x"] = 52
		var far := Attack.mods(s, data, g, hero, Cheats.blow(_spec(true)))
		check(steps, (far["dis" if str(row["attacked_far"]) == "disadvantage" else "adv"] as Array).size() > 0, "атаки по нему издали: %s" % MODE_WORDS[str(row["attacked_far"])], far)
		g["x"] = 41
	if bool(row.get("crit_near", false)):
		known = true
		check(steps, bool(now_at["crit"]), "удар вплотную — крит", "нет")
	if bool(row.get("no_move", false)):
		known = true
		check(steps, CharacterRules.speed(h, data) == 0 and Sheet.speed(s, data, g) == 0, "скорость 0", "%d / %d" % [CharacterRules.speed(h, data), Sheet.speed(s, data, g)])
	if bool(row.get("resist_all", false)):
		known = true
		check(steps, Sheet.taken(s, data, Sheet.HERO, "fire", PROBE) == LEFT["resist"], "сопротивление всему урону", Sheet.taken(s, data, Sheet.HERO, "fire", PROBE))
	if bool(row.get("no_threat", false)):
		known = true
		check(steps, ConditionRules.does(h, data, "no_threat"), "не грозит атакой по возможности", "грозит")
	if ConditionRules.INCAPACITATING.has(id):
		known = true
		turn(s, data, hero)
		check(steps, ConditionRules.incapacitated(h) and not CombatRules.can_act(s, hero), "недееспособен: ход пропускается", "может действовать")
	match id:
		"charmed":
			known = true
			turn(s, data, hero)
			var why := Acts.one("attack").can(s, data, hero, str(g["id"]))
			check(steps, why == "COMBAT_CHARMED", "не нападает на очаровавшего", why)
		"invisible":
			known = true
			check(steps, (now_me["adv"] as Array).size() > (by_me["adv"] as Array).size() and (now_at["dis"] as Array).size() > (at_me["dis"] as Array).size(),
				"невидим: его атаки с преимуществом, по нему с помехой", "%s / %s" % [now_me, now_at])
		"slowed_spell":
			known = true
			check(steps, Sheet.speed(s, data, g) < int(Sheet.template(data, g).get("speed", 30)), "скорость вдвое", Sheet.speed(s, data, g))
	if not known:
		var files := reads(id)
		if files.is_empty():
			gap(steps, "у состояния нет ни строки правил, ни кода — только название")
		else:
			check(steps, true, "что делает — в коде: %s" % ", ".join(files))
	return result(steps)


const MODE_WORDS := {"advantage": "преимущество", "disadvantage": "помеха", "auto_fail": "автопровал"}


## The console's blow for Attack.mods: a melee one or a shot.
static func _spec(ranged: bool) -> Dictionary:
	return {"dice": "1d1", "type": "bludgeoning", "to_hit": 0, "adv": false, "dis": false, "crit": false, "magical": false,
		"silvered": false, "ranged": ranged}


## The levels of exhaustion by 5e, one by one on the hero.
static func _exhaustion(s: GameSession, data: Dictionary, g: Dictionary, steps: Array[String]) -> void:
	var h := s.character
	var speed := CharacterRules.speed(h, data)
	var max_hp := int(h["max_hp"])
	var level := func(n: int) -> void:
		ConditionRules.add_exhaustion(s, data, n, "проба")
		CharacterRules.refresh(h, data, s.items)
	level.call(1)
	check(steps, not (CheckEngine.situation(s, data, Sheet.HERO, {"skill": "athletics"}, true)["dis"] as Array).is_empty(), "1: помеха проверкам", "нет")
	level.call(1)
	check(steps, CharacterRules.speed(h, data) == speed / 2, "2: скорость вдвое", CharacterRules.speed(h, data))
	level.call(1)
	var atk := Attack.mods(s, data, CombatRules.player(s), g, Cheats.blow(_spec(false)))
	check(steps, not (atk["dis"] as Array).is_empty() and bool(Sheet.save_odds(s, data, Sheet.HERO, "dex")["dis"]), "3: помеха атакам и спасброскам", atk)
	level.call(1)
	check(steps, int(h["max_hp"]) == max_hp / 2, "4: максимум хитов вдвое", h["max_hp"])
	level.call(1)
	check(steps, CharacterRules.speed(h, data) == 0, "5: скорость 0", CharacterRules.speed(h, data))
	level.call(1)
	check(steps, ConditionRules.dead(h), "6: смерть", "жив")


## The files of core/ that name `id` in quotes: a rule that lives in code, not in a table.
static func reads(id: String) -> Array[String]:
	var out: Array[String] = []
	var code := _code()
	for path: String in code:
		if (code[path] as String).contains("\"%s\"" % id):
			out.append(path.get_file().get_basename())
	return out


static var _sources := {}


static func _code() -> Dictionary:
	if _sources.is_empty():
		_scan("res://core", _sources)
	return _sources


static func _scan(dir: String, out: Dictionary) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") and f != "checklist_probe.gd":
			out[dir.path_join(f)] = FileAccess.get_file_as_string(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)


# --- defenses and damage types --------------------------------------------------------------------------------------


## A defense of the console on the hero and on a foe: the probe's 8 comes out as 5e says; a monster of the SRD with it in its
## data — by its own template.
static func defense(data: Dictionary, kind: String, dtype: String) -> Dictionary:
	var steps: Array[String] = []
	var s := session(data)
	var g := fight(s, data, "goblin")
	var want := int(LEFT[kind])
	Cheats.defense(s, data, Being.HERO, kind, dtype, true)
	var lines: Array[String] = []
	var left := Harm.typed(s, data, Sheet.HERO, PROBE, dtype, lines)
	check(steps, left == want, "герой: %d %s → %d" % [PROBE, dtype, want], left)
	Cheats.defense(s, data, str(g["id"]), kind, dtype, true)
	check(steps, Sheet.taken(s, data, g, dtype, PROBE) == want, "враг: %d → %d" % [PROBE, want], Sheet.taken(s, data, g, dtype, PROBE))
	Cheats.defense(s, data, Being.HERO, kind, dtype, false)
	check(steps, Sheet.taken(s, data, Sheet.HERO, dtype, PROBE) == PROBE, "снимается: снова %d" % PROBE, Sheet.taken(s, data, Sheet.HERO, dtype, PROBE))
	var key: String = {"resist": "resistances", "immune": "immunities", "vulnerable": "vulnerabilities"}[kind]
	for mid: String in data["monsters"]:
		if (data["monsters"][mid].get(key, []) as Array).map(func(x: Variant) -> String: return str(x)).has(dtype):
			var s2 := session(data)
			var m := fight(s2, data, mid)
			check(steps, Sheet.taken(s2, data, m, dtype, PROBE) == want, "по данным монстра %s: %d → %d" % [mid, PROBE, want], Sheet.taken(s2, data, m, dtype, PROBE))
			break
	return result(steps)


## The first monster of the SRD immune to `cond` ("" — none).
static func immune_to(data: Dictionary, cond: String) -> String:
	for mid: String in data["monsters"]:
		if (data["monsters"][mid].get("condition_immunities", []) as Array).map(func(x: Variant) -> String: return str(x)).has(cond):
			return mid
	return ""


## A status laid on a monster immune to it by its data does not take; on a goblin beside it does.
static func condition_immunity(data: Dictionary, cond: String, mid: String) -> Dictionary:
	var steps: Array[String] = []
	var s := session(data)
	var m := fight(s, data, mid)
	ConditionRules.impose(s, data, {"condition": cond, "ends": {}, "source": Cheats.SOURCE.duplicate()}, m)
	check(steps, not ConditionRules.has(m, cond), "%s: не ложится" % mid, "легло")
	var s2 := session(data)
	var g := fight(s2, data, "goblin")
	ConditionRules.impose(s2, data, {"condition": cond, "ends": {}, "source": Cheats.SOURCE.duplicate()}, g)
	check(steps, ConditionRules.has(g, cond) or cond == "exhaustion", "гоблину без иммунитета — ложится", "не легло")
	return result(steps)


## A damage type on the one road of damage with no roll: its name in the line, the hit points it takes, a critical's dice
## twice, a foe hurt alike.
static func damage_type(data: Dictionary, dtype: String) -> Dictionary:
	var steps: Array[String] = []
	var s := session(data)
	var g := fight(s, data, "commoner")
	var hp := _hp(s, data)
	var lines: Array[String] = []
	Harm.typed(s, data, Sheet.HERO, 3, dtype, lines)
	check(steps, _hp(s, data) == hp - 3, "герою: −3 HP", _hp(s, data) - hp)
	check(steps, " ".join(lines).contains(str(data["misc"]["damage_types"][dtype])), "строка называет тип: %s" % data["misc"]["damage_types"][dtype], " ".join(lines))
	check(steps, CombatRules.roll_dice(s.rng, "4d1", true) == PROBE, "крит: кости дважды (4к1 → 8)", CombatRules.roll_dice(s.rng, "4d1", true))
	var before := int(g["hp"])
	Harm.typed(s, data, g, 3, dtype, lines)
	check(steps, int(g["hp"]) == before - 3, "врагу: −3 HP", before - int(g["hp"]))
	return result(steps)
