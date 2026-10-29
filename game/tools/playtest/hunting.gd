extends "res://tools/playtest/playtest_base.gd"
## Hunting and fishing (python tools/godot_playtest.py --scenario hunting), v0.7.41: «Рыбачить» at the river yard
## without tackle and with it, the hours window, the fish in the bag and the stock down; «Охотиться» at the Pushcha
## edge — meat or a beast to fight (last: a fight ends the script); the innkeeper wants the catch; the master empties the
## river and the button greys.

const RIVER := "brod-river-yard"
const FOREST := "pushcha-edge"


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	var c := s.character
	s.settings["needs"] = false
	s.minute = 8 * 60
	s.room_id = RIVER
	c["skills"]["survival"] = 12
	node("EventBus").state_changed.emit()
	await frames(3)

	var fish: Button = find(screen(), "Wilds_fish")
	if not step("«Рыбачить» at the river yard", fish != null and not fish.disabled, fish.tooltip_text if fish != null else "нет кнопки"):
		await shot("no_fish_button")
		return
	await press(fish)
	await frames(3)
	var win: Control = find(screen(), "WildsView")
	step("the window warns of no tackle", win.visible and _has_text(win, "Без снастей"))
	await shot("fish_no_tackle")
	win.visible = false

	c["inventory"]["fishing_tackle"] = 1
	node("EventBus").state_changed.emit()
	await frames(2)
	await press(find(screen(), "Wilds_fish"))
	await frames(3)
	await press(find(win, "HoursPlus"))
	await press(find(win, "HoursPlus"))
	await frames(2)
	var hours: Label = find(win, "WildsHours")
	step("hours picked by «+»", hours != null and hours.text.begins_with("4"), hours.text if hours != null else "")
	await shot("fish_hours")
	var stock0 := WildsRules.stock(s, data, "fish")
	var minute0 := s.day * 1440 + s.minute
	await press(find(win, "DialogConfirm"))
	await frames(4)
	var caught := int(c["inventory"].get("fresh_fish", 0))
	step("fish in the bag, the stock down", caught > 0 and WildsRules.stock(s, data, "fish") == stock0 - caught,
		"рыбы %d, запас %d → %d" % [caught, stock0, WildsRules.stock(s, data, "fish")])
	step("four hours passed", s.day * 1440 + s.minute - minute0 == 240, str(s.day * 1440 + s.minute - minute0))
	step("the chat shows the check and the catch", s.chat.any(func(e: Dictionary) -> bool: return e["kind"] == GameSession.KIND_EFFECT and str(e.get("lines", [])).contains("Рыбалка")))
	await shot("fish_caught")

	# The innkeeper's trade kind wants the catch.
	var wants := TradeRules.wants(data, "npc_innkeeper")
	step("the innkeeper buys the catch gladly", wants.has("catch"), str(wants))

	# The master empties the river: the button greys with the reason.
	var fx: EffectEngine = gs.effects
	var r := fx.validate(s, data, "hw-1", {"kind": "wilds", "ground": "fish", "op": "deplete", "cause": "мельник выше по реке потравил рыбу"})
	if step("the master's `wilds` accepted", bool(r["accepted"]), str(r.get("summary", r.get("reason", "")))):
		fx.apply(s, "hw-1", [r["effect_id"]])
		node("EventBus").state_changed.emit()
		await frames(3)
		fish = find(screen(), "Wilds_fish")
		step("«Рыбачить» grey: the river is empty", fish != null and fish.disabled and fish.tooltip_text.contains("выбито"),
			fish.tooltip_text if fish != null else "")
		await shot("river_empty")

	# The hunt at the Pushcha edge.
	s.room_id = FOREST
	c["skills"]["survival"] = 20
	node("EventBus").state_changed.emit()
	await frames(3)
	var hunt: Button = find(screen(), "Wilds_game")
	if step("«Охотиться» at the Pushcha edge", hunt != null and not hunt.disabled, hunt.tooltip_text if hunt != null else "нет кнопки"):
		await press(hunt)
		await frames(3)
		await press(find(win, "DialogConfirm"))
		await frames(6)
		var fought := CombatRules.active(s)
		step("the hunt gave meat or a beast to fight", int(c["inventory"].get("raw_meat", 0)) > 0 or fought,
			"мясо %d, бой %s" % [int(c["inventory"].get("raw_meat", 0)), fought])
		await shot("hunt_done")


func _has_text(root: Node, text: String) -> bool:
	if root is Label and (root as Label).text.contains(text):
		return true
	for ch in root.get_children():
		if _has_text(ch, text):
			return true
	return false
