extends GdUnitTestSuite
## A probe of the author's question (2026-11-08): can the master make an artifact with an aura of blindness around the
## hero (30 ft) that works on everybody but the hero? Three steps of one road: the master's thing with the aura is
## accepted, the worn thing lays its aura on the field of a fight, the field's aura blinds all within 30 ft but its owner.

var data: Dictionary
var s: GameSession
var fx: EffectEngine

const AURA := {"ft": 30, "on": ["start"], "save": "con", "dc": 40, "tag": "", "cond": "blinded", "for": {"rounds": 1}}
const NAME := "Амулет слепящего сияния"


func before_test() -> void:
	data = TestUtils.data()
	s = ChecklistProbe.session(data)
	s.character["level"] = 9
	fx = EffectEngine.new()


## The master's `move_item:world>hero` with a new thing (as test_made_wear_v084287); its id or the engine's refusal.
func _give(item: Dictionary) -> Dictionary:
	fx.searched["t-1"] = true
	fx._won["t-1"] = ["perception"]
	var r := fx.validate(s, data, "t-1", {"kind": "move_item", "source": "world", "target": "hero", "item": item, "qty": 1, "reason": "находка"})
	if not bool(r["accepted"]):
		return {"reason": str(r.get("reason", ""))}
	fx.apply(s, "t-1", [r["effect_id"]])
	for id: String in s.items:
		if str(s.items[id].get("name", "")) == NAME:
			return {"id": id}
	return {"reason": "не найдено"}


func _amulet() -> Dictionary:
	return {"name": NAME, "item_type": "wondrous", "rarity": "rare", "value_cp": 500000, "description": "Камень на цепочке, режет глаза светом.",
		"wear": {"aura": {"ft": 30, "cond": "blinded", "save": "con", "rounds": 1}}}


## A fight: a goblin 25 ft from the hero, one 50 ft away, an ally commoner 10 ft away. [near, far, ally].
func _fight() -> Array[Dictionary]:
	TestUtils.fight(s, data, [{"monster": "goblin"}, {"monster": "goblin"}], {"allies": [{"monster": "commoner"}]})
	var p := CombatRules.player(s)
	FightGrid.put(p, Vector2i(40, 30))
	var foes: Array[Dictionary] = []
	for id: String in CombatRules.enemies(s):
		foes.append(CombatRules.fighter(s, id))
	var ally := {}
	for id: String in s.combat["fighters"]:
		var f := CombatRules.fighter(s, id)
		if str(f.get("side", "")) == "ally":
			ally = f
	FightGrid.put(foes[0], Vector2i(45, 30))
	FightGrid.put(foes[1], Vector2i(50, 30))
	FightGrid.put(ally, Vector2i(40, 32))
	return [foes[0], foes[1], ally]


func _blind(f: Dictionary) -> bool:
	return ConditionRules.has(Sheet.holder(s, f), "blinded")


## Step 1: the master may give such a thing — its `wear` carries the aura, the engine sets its DC and its rarity: blinding
## everybody within 30 ft is a legendary thing (1 + 3 for 30 ft + 6 for blindness = 10 points), not for a 9th-level hero.
func test_step_one_the_master_gives_a_thing_with_a_blinding_aura() -> void:
	assert_str(str(_give(_amulet()).get("reason", ""))).contains("недоступен")
	s.character["level"] = 17
	var got := _give(_amulet())
	assert_bool(got.has("id")).override_failure_message("мастер не может выдать вещь с аурой: %s" % got.get("reason", "")).is_true()
	var d: Dictionary = s.items[got["id"]]
	assert_str(str(d["rarity"])).is_equal("legendary")
	assert_int(int(d["wear"]["aura"]["dc"])).is_equal(15)
	assert_str(str(d["wear"]["aura"]["cond"])).is_equal("blinded")
	var less := _amulet()
	less["wear"]["aura"]["cond"] = "nope"
	assert_str(str(_give(less).get("reason", ""))).contains("wear.aura.cond")


## Step 2: worn, the thing lays its aura on the field around the hero when a fight starts.
func test_step_two_a_worn_aura_goes_onto_the_field_around_the_hero() -> void:
	var id := "gen_blind_amulet"
	s.items[id] = _amulet().merged({"generated": true, "wear": {"aura": AURA.duplicate(true)}})  # the road of a worn thing alone
	ItemRules.add(s.character, id, 1)
	s.character["equipped"]["neck"] = id
	CharacterRules.refresh(s.character, data, s.items)
	_fight()
	var auras := SpellEffects.zones(s).filter(func(z: Dictionary) -> bool: return str(z.get("by", "")) == str(CombatRules.player(s)["id"]) and bool(z.get("follow", false)))
	assert_int(auras.size()).override_failure_message("надетая вещь не кладёт ауру на поле боя вокруг героя").is_equal(1)


## Step 3: the field itself — an aura that follows the hero blinds the foe and the ally within 30 ft, not the far foe, not
## the hero.
func test_step_three_the_field_blinds_everyone_within_30_ft_but_the_hero() -> void:
	var who := _fight()
	var p := CombatRules.player(s)
	SpellEffects.add_zone(s, FightField.zone_of("aura:blind_amulet", AURA.merged({"name": NAME, "follow": true,
		"shape": {"type": "sphere", "size": 30}, "by": str(p["id"]), "side": "player"}), []))
	for f: Dictionary in [who[0], who[1], who[2], p]:
		SpellEffects.zone_tick(s, data, f, "start")
	assert_bool(_blind(who[0])).override_failure_message("гоблин в 25 фт не ослеп").is_true()
	assert_bool(_blind(who[2])).override_failure_message("союзник в 10 фт не ослеп (аура — на всех, кроме героя)").is_true()
	assert_bool(_blind(who[1])).override_failure_message("гоблин в 50 фт ослеп — аура дальше 30 фт").is_false()
	assert_bool(_blind(p)).override_failure_message("ослеп сам герой").is_false()
	FightGrid.put(p, Vector2i(52, 30))  # the aura follows the hero: now the far goblin is near
	ConditionRules.remove(Sheet.holder(s, who[1]), "blinded")
	SpellEffects.zone_tick(s, data, who[1], "start")
	assert_bool(_blind(who[1])).override_failure_message("аура не идёт за героем").is_true()


## The whole road: the master's amulet given, worn, a fight — the goblin beside goes blind by the engine's own save against
## DC 15, the hero never; taken off, the aura is gone.
func test_the_whole_road_from_the_masters_word_to_a_blind_goblin() -> void:
	s.character["level"] = 17
	var got := _give(_amulet())
	var c := s.character
	var slot := CharacterRules.slot_for(ItemRules.def_of(data["items"], s.items, str(got["id"])), data)
	assert_str(slot).is_not_empty()
	c["equipped"][slot] = str(got["id"])
	CharacterRules.refresh(c, data, s.items)
	var who := _fight()
	var p := CombatRules.player(s)
	var blinded := false
	for i in 40:
		ConditionRules.remove(Sheet.holder(s, who[0]), "blinded")
		SpellEffects.zone_tick(s, data, who[0], "start")
		SpellEffects.zone_tick(s, data, p, "start")
		blinded = blinded or _blind(who[0])
	assert_bool(blinded).override_failure_message("гоблин рядом так и не ослеп").is_true()
	assert_bool(_blind(p)).is_false()
	c["equipped"][slot] = ""
	CharacterRules.refresh(c, data, s.items)
	ConditionRules.remove(Sheet.holder(s, who[0]), "blinded")
	for i in 20:
		SpellEffects.zone_tick(s, data, who[0], "start")
	assert_bool(_blind(who[0])).override_failure_message("амулет снят, а аура слепит").is_false()
