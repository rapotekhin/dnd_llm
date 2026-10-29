extends "res://tools/playtest/playtest_base.gd"
## The master's places and upgrades (python tools/godot_playtest.py --scenario property_made), v0.7.39.8: a fishing pier
## of the master's own kind on sale at the innkeeper, bought by the button, its boat and nets ordered in «Имущество», a
## fisher hired, the catch collected; at the river house a jeweler's bench asked by words, ordered and built.


const PIER := {"name": "рыбацкий причал", "income_cp_day": 20, "skill": "survival", "hours": 8,
	"staff": [{"role": "рыбак", "wage_cp_day": 10, "max": 2}],
	"upgrades": [
		{"name": "Лодка", "text": "Улов каждый день", "gives": {"produce": [{"item_id": "fresh_fish", "qty": 4}]}},
		{"name": "Коптильня", "text": "Коптить рыбу", "gives": {"station_new": {"name": "Коптильня", "tools": ["cooks_utensils"]}}},
		{"name": "Сети", "text": "Улов больше", "gives": {"produce_pct": 50}}]}


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
	var fx: EffectEngine = gs.effects
	c["gold_cp"] = 200000
	s.settings["needs"] = false
	s.minute = 12 * 60
	s.room_id = "brod-tavern-hall"

	var r := fx.validate(s, data, "pm-1", {"kind": "property", "site_id": "brod-tavern", "seller_id": "npc_innkeeper", "new_kind": PIER, "price_cp": 12000})
	if not step("the master's pier on sale", bool(r["accepted"]), str(r.get("summary", r.get("reason", "")))):
		return
	fx.apply(s, "pm-1", [r["effect_id"]])
	node("EventBus").state_changed.emit()
	await frames(3)
	await open_row("More_npc_innkeeper")
	var sale: Button = find(screen(), "PropertySale_npc_innkeeper")
	if not step("«Имущество» at the innkeeper", sale != null and not sale.disabled):
		await shot("no_sale")
		return
	await press(sale)
	await frames(4)
	var win: Control = find(screen(), "PropertyView")
	var id: String = PropertyRules.of_seller(s, data, "npc_innkeeper")[0]
	await shot("pier_on_sale")
	await press(find(win, "PropertyBuy_" + id))
	await frames(4)
	if not step("the pier bought", PropertyRules.owned(c, id)):
		return
	PropertyRules.state(c)[id]["deed"] = true
	win.visible = false
	s.room_id = PropertyRules.main_room(s, data, id)
	node("EventBus").state_changed.emit()
	await frames(3)
	await press(find(screen(), "PropertyButton"))
	await frames(4)
	var boat := _up(s, data, id, "Лодка")
	var nets := _up(s, data, id, "Сети")
	step("the pier's own upgrades in the window", find(win, "PropertyUpgrade_" + boat) != null and find(win, "PropertyUpgrade_" + nets) != null
		and find(win, "PropertyUpgrade_" + _up(s, data, id, "Коптильня")) != null)
	await shot("pier_upgrades")
	await press(find(win, "PropertyUpgrade_" + boat))
	await frames(3)
	await press(find(win, "PropertyUpgrade_" + nets))
	await frames(3)
	step("the boat and the nets ordered", not PropertyRules.pending(c, id, boat).is_empty() and not PropertyRules.pending(c, id, nets).is_empty())
	win.visible = false
	PropertyRules.hire_worker(s, data, id)
	_days(s, data, 3)
	PropertyRules.state(c)[id]["stock"] = {}
	_days(s, data, 1)
	step("a day's catch: 4 fish × 1.5", int(PropertyRules.state(c)[id]["stock"].get("fresh_fish", 0)) == 6, str(PropertyRules.state(c)[id]["stock"]))
	await press(find(screen(), "PropertyButton"))
	await frames(4)
	var take: Button = find(win, "PropertyCollect_" + id)
	if step("«Забрать» the catch", take != null and not take.disabled):
		await press(take)
		await frames(3)
	step("the fish in the bag", int(c["inventory"].get("fresh_fish", 0)) >= 6, str(c["inventory"].get("fresh_fish", 0)))
	await shot("catch_collected")
	win.visible = false

	s.room_id = "brod-townhall"
	PropertyRules.buy(s, data, "river_house")
	PropertyRules.state(c)["river_house"]["deed"] = true
	s.room_id = PropertyRules.main_room(s, data, "river_house")
	var a := fx.validate(s, data, "pm-2", {"kind": "upgrade", "name": "Станок ювелира", "text": "Кольца и подвески своими руками", "indoor": true,
		"gives": {"station_new": {"name": "Станок ювелира", "tools": ["jewelers_tools"]}}})
	if not step("a jeweler's bench asked at home", bool(a["accepted"]), str(a.get("summary", a.get("reason", "")))):
		return
	fx.apply(s, "pm-2", [a["effect_id"]])
	node("EventBus").state_changed.emit()
	await frames(3)
	await press(find(screen(), "PropertyButton"))
	await frames(4)
	var bench := _up(s, data, "river_house", "Станок ювелира")
	var ob: Button = find(win, "PropertyUpgrade_" + bench)
	if step("the bench offered in «Имущество»", ob != null and not ob.disabled):
		await shot("bench_offered")
		await press(ob)
		await frames(3)
	win.visible = false
	_days(s, data, int(PropertyRules.ups(data)[bench]["days"]))
	var station := str(PropertyRules.ups(data)[bench]["gives"]["station"])
	step("the bench built: a jeweler's station at home", PropertyRules.has_upgrade(c, "river_house", bench) and CraftRules.station_here(s, data, station))
	await press(find(screen(), "PropertyButton"))
	await frames(4)
	await shot("bench_ready")


func _up(s: GameSession, data: Dictionary, id: String, name: String) -> String:
	for up: String in PropertyRules.upgrades_for(s, data, id):
		if str(PropertyRules.ups(data)[up]["name"]) == name:
			return up
	return ""


func _days(s: GameSession, data: Dictionary, n: int) -> void:
	s.rested_at = TimeRules.abs_minute(s) + n * 1440
	s.chat.append(GameSession.effect_entry(TimeRules.advance(s, data, n * 1440)))
	node("EventBus").state_changed.emit()
