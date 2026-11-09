class_name TestUtils
extends RefCounted
## Shared helpers for gdUnit4 suites: game data without autoloads.

## Ids of the start pack (data/worlds/frontier) that the tests rely on.
const INNKEEPER := "npc_innkeeper"
const SERVING := "npc_serving"
const COOK := "npc_cook"
const START_ROOM := "brod-tavern-hall"
const KITCHEN := "brod-tavern-kitchen"
const FAR_ROOM := "mine-deep"


static func rules() -> Dictionary:
	return _json("res://data/rules.json")


static var _data: Dictionary = {}


## All game data with the start pack applied (a fresh deep copy: tests may change it).
static func data() -> Dictionary:
	if _data.is_empty():
		var base: Dictionary = preload("res://autoload/catalog.gd").load_all()
		_data = WorldPack.apply_rules(base, WorldPack.load_bundle("res://data/worlds/frontier", "builtin"))
	return _data.duplicate(true)


static func base() -> Dictionary:
	return preload("res://autoload/catalog.gd").load_all()


## A record out of the game (rules.off, v0.8.4.28.4) as its file keeps it: a test of a road that stays in the engine.
static func uncut(kind: String, id: String) -> Dictionary:
	var raw: Dictionary = preload("res://autoload/catalog.gd").load_json(preload("res://autoload/catalog.gd").FILES[kind])
	return raw.get(id, {})


## A system out of the game (rules.off.systems, v0.8.4.39) back in `d` as rules.json keeps it: its own tests run
## while the player and the master never meet it.
static func system_on(d: Dictionary, id: String) -> Dictionary:
	d["rules"][id] = rules()[id]
	return d


## A part out of the game (rules.off.parts, v0.8.4.42.9: "property.staff", "property.income") back in `d`.
static func part_on(d: Dictionary, part: String) -> Dictionary:
	(d["rules"]["off"]["parts"] as Dictionary).erase(part)
	return d


## Property as it was before v0.8.4.42.9: hiring, income and one's own trade back in `d`, for their own tests.
static func trade_on(d: Dictionary) -> Dictionary:
	return part_on(part_on(system_on(d, "shop"), "property.staff"), "property.income")

## The start pack's first ready-made character (Айра, fighter 1).
static func preset_choices() -> Dictionary:
	return CharacterBuilder.preset_choices(data()["presets"][0])


static func character() -> Dictionary:
	var d := data()
	return CharacterBuilder.build_preset(d["presets"][0], d)


static func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## The n-th foe to join the running fight, from 1.
static func foe(s: GameSession, n: int) -> String:
	return (s.combat["fighters"] as Array).filter(func(id: String) -> bool: return CombatRules.fighter(s, id).get("side") == "enemy")[n - 1]


static func new_session(seed_value: int = 42) -> GameSession:
	var d := data()
	var s := GameSession.create(seed_value, "2026-10-18T12:00:00", str(d["world"]["start_room"]), CharacterBuilder.build_preset(d["presets"][0], d))
	s.world_id = "frontier"
	s.settings = WorldPack.default_settings(d["pack"])
	s.settings["weather"] = false  # the day's weather would move old numbers (v0.7.46); its own tests turn it on
	return s


static func session_with_chat() -> GameSession:
	var s := new_session()
	s.append(GameSession.dm_entry("Таверна «Пьяный гусь».", s.next_turn_id()))
	s.append(GameSession.player_entry("осматриваюсь"))
	s.append(GameSession.check_entry({"skill": "perception"}, {"check_id": s.next_check_id(), "rolls": [12], "bonus": 0,
		"total": 12, "dc": 15, "success": false, "nat": 12, "blocked": false}))
	s.append(GameSession.dm_entry("Ничего необычного.", s.next_turn_id()))
	s.options = ["Подойти к стойке"]
	return s


## A fight on an open field, with the old way of saying where a foe stands: `col` 0 — beside the hero, n — n × 6 squares
## (30 ft) to the side. The tests of the rules do not care for the map (v0.8.4).
static func fight(s: GameSession, d: Dictionary, foes: Array, source: Dictionary = {}) -> Array[String]:
	var src := source.duplicate()
	if not src.has("field"):
		src["field"] = {"w": 80, "h": 60}
	var room := {"near": 0}
	if src.has("allies"):  # without a col an ally stands by the hero, as the engine puts it
		var placed: Array = (src["allies"] as Array).filter(func(a: Dictionary) -> bool: return a.has("col"))
		var free: Array = (src["allies"] as Array).filter(func(a: Dictionary) -> bool: return not a.has("col"))
		src["allies"] = _spots(d, placed, room) + free
	return CombatRules.start(s, d, _spots(d, foes, room), src)


## The specs with squares in place of old columns: each body of a count on a square of its own.
static func _spots(d: Dictionary, foes: Array, room: Dictionary) -> Array:
	var specs: Array = []
	var hero := Vector2i(40, 30)
	for spec: Dictionary in foes:
		var one := spec.duplicate(true)
		var col := int(one.get("col", 1))
		var n := int(one.get("count", 1))
		one.erase("col")
		one.erase("count")
		for i: int in n:
			var two := one.duplicate(true)
			if n > 1 and not one.has("name"):  # as the engine numbers a count
				two["base"] = str(d["monsters"].get(str(one["monster"]), {}).get("name", ""))
				two["name"] = "%s %d" % [two["base"], i + 1]
			if col == 0:
				var at: Vector2i = hero + FightGrid.CIRCLE[int(room["near"]) % 8]
				room["near"] = int(room["near"]) + 1
				two["x"] = at.x
				two["y"] = at.y
			else:
				two["x"] = hero.x + col * 6
				two["y"] = hero.y + int(room.get(col, 0))
				room[col] = int(room.get(col, 0)) + 1
			specs.append(two)
	return specs


## The hero walks one old column (30 ft) to a side.
static func walk(s: GameSession, d: Dictionary, dir: int) -> Array[String]:
	return Acts.one("walk").go(s, d, CombatRules.player(s), FightGrid.aim_id(FightGrid.cell(CombatRules.player(s)) + Vector2i(6 * dir, 0)))


## A foe's whole turn out of the order of the fight: its turn is made current, its points fresh.
static func enemy_turn(s: GameSession, d: Dictionary, f: Dictionary, lines: Array[String]) -> void:
	var turn: int = s.combat["turn"]
	s.combat["turn"] = (s.combat["order"] as Array).find(str(f["id"]))
	CombatRules._begin_turn(s, d, lines)  # the start of its turn as the fight's own loop: fire, Help, riders
	CombatRules._enemy_turn(s, d, f, lines)
	s.combat["turn"] = turn


static func beside(s: GameSession, f: Dictionary) -> void:
	FightGrid.put(f, FightGrid.free_near(s, data(), FightGrid.cell(CombatRules.player(s)) + Vector2i(1, 0), int(f.get("span", 1))))
	if FightGrid.dist(f, CombatRules.player(s)) > 1:
		FightGrid.put(f, FightGrid.cell(CombatRules.player(s)) + Vector2i(0, -1))


static func same_col(f: Dictionary, o: Dictionary) -> void:
	FightGrid.put(f, FightGrid.cell(o) + Vector2i(0, 1))


static func to_col(f: Dictionary, col: int) -> void:
	FightGrid.put(f, Vector2i(40 + col * 6, int(f.get("y", 30))))


## The old column of a fighter: 0 — the hero's start.
static func col_of(f: Dictionary) -> int:
	return roundi((int(f.get("x", 40)) - 40) / 6.0)


## The names of the zones over a fighter.
static func zones_on(s: GameSession, f: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for z: Dictionary in SpellEffects.zone_view(s, data()):
		if FightGrid.in_cells(f, z["cells"]):
			out.append(str(z["name"]))
	return out


## The zones on one square, by name.
static func zones_on_cell(s: GameSession, at: Vector2i) -> Array[String]:
	var out: Array[String] = []
	for z: Dictionary in SpellEffects.zone_view(s, data()):
		if (z["cells"] as Array).has(at):
			out.append(str(z["name"]))
	return out


## The zones slow a fighter down where it stands.
static func slowed(s: GameSession, f: Dictionary) -> bool:
	return FightGrid.slow_cells(s, data(), f).has(FightGrid.cell(f))


## Old columns between two fighters: 0 — within reach.
static func cols(a: Dictionary, b: Dictionary) -> int:
	return 0 if FightGrid.dist(a, b) <= 1 else ceili(FightGrid.dist(a, b) / 6.0)
