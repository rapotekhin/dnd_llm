extends "res://tools/playtest/playtest_base.gd"
## Mounts and vehicles (python tools/godot_playtest.py --scenario mounts), v0.7.42: the master puts a camel at Ostap's;
## a mule bought, a horse rented for days, a cart hitched to the mule; the mule's pack loaded from the panel; the beasts
## wait at the mine's gallery and come along again at the entrance; the cart stops where the forest road ends.

const GATE := "brod-gate"


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
	node("Catalog").data["rules"]["mounts"]["steal_pct_day"] = 0  # the ways of the beasts are checked here, not a thief's luck
	var data: Dictionary = node("Catalog").data
	var c := s.character
	c["gold_cp"] = 100000
	s.settings["needs"] = false
	s.room_id = GATE
	s.minute = 10 * 60
	s.encounters_done.append_array(["trail_wolves", "gallery_kobolds"])  # not a combat test
	for r: String in ["brod-square", GATE]:
		if not s.visited.has(r):
			s.visited.append(r)
	node("EventBus").state_changed.emit()
	await frames(3)

	# The master's `stock` with `animal`: a camel the engine derives.
	var fx: EffectEngine = gs.effects
	var r := fx.validate(s, data, "mt-1", {"kind": "create", "what": "stock", "npc_id": "npc_drover", "animal": "camel", "reason": "караван из степи оставил верблюда"})
	if step("the master's camel accepted", bool(r["accepted"]), str(r.get("summary", r.get("reason", "")))):
		fx.apply(s, "mt-1", [r["effect_id"]])

	await open_row("More_npc_drover")
	var animals: Button = find(screen(), "Animals_npc_drover")
	if not step("«Животные» at the dealer", animals != null):
		await shot("no_animals")
		return
	await press(animals)
	await frames(4)
	var win: Control = find(screen(), "PropertyView")
	step("the camel on sale, a rent and the carts", find(win, "AnimalBuy_camel") != null and find(win, "AnimalRent_riding_horse") != null
		and find(win, "VehicleBuy_cart") != null)
	step("a cart needs a beast first", (find(win, "VehicleBuy_cart") as Button).disabled)
	await shot("dealer")

	await press(find(win, "AnimalBuy_mule"))
	await frames(4)
	var mule: Dictionary = PropertyRules.animals(s).back() if not PropertyRules.animals(s).is_empty() else {}
	step("a mule bought", str(mule.get("monster", "")) == "mule", _last_effects(s))
	await press(find(win, "RentPlus"))
	await frames(2)
	var days: Label = find(win, "RentDaysLabel")
	step("rent days by «+»", days != null and days.text.contains("4"), days.text if days != null else "")
	await press(find(win, "AnimalRent_riding_horse"))
	await frames(4)
	var horse: Dictionary = PropertyRules.animals(s).back()
	step("a horse rented till a day", str(horse.get("monster", "")) == "riding_horse" and horse.has("rent_day"), _last_effects(s))
	await press(find(win, "VehicleBuy_cart"))
	await frames(4)
	var hitched := PropertyRules.animals(s).filter(func(cr: Dictionary) -> bool: return cr.get("cart") is Dictionary)
	step("a cart hitched", hitched.size() == 1, _last_effects(s))
	step("the mule offered for sale", find(win, "AnimalSell_" + str(mule.get("id", ""))) != null)
	await shot("bought")
	win.visible = false

	# The mule's pack from the panel.
	c["inventory"]["iron_ore"] = 6
	node("EventBus").state_changed.emit()
	await frames(3)
	var mid := str(mule["id"])
	await open_row("CreatureMore_" + mid)
	var pack: Button = find(screen(), "Mount_pack" + mid)
	if step("«Вьюк» among the mule's acts", pack != null):
		await press(pack)
		await frames(3)
		var view: Control = find(screen(), "ContainerView")
		step("the pack's window", view != null and view.visible)
		await drag(find(view, "Mine_iron_ore"), find(view, "BoxGrid"), true)  # v0.8.4.43.6: Shift + a drag onto the pack's grid
		var spin: SpinBox = find(view, "QtySpin")
		if step("how many of six", spin != null and int(spin.max_value) == 6):
			spin.value = 3
			await press(find(view, "QtyOk"))
			await frames(3)
		step("ore in the pack", int(mule.get("pack", {}).get("iron_ore", 0)) == 3, str(mule.get("pack", {})))
		await shot("pack")
		view.visible = false

	# The mine: the beasts wait at the gallery's mouth.
	await _go(gs, "mine-entrance")
	step("the beasts at the mine's entrance", PropertyRules.room_of(s, mid) == "mine-entrance")
	await _go(gs, "mine-gallery")
	step("they wait at the entrance", PropertyRules.room_of(s, mid) == "mine-entrance" and bool(mule.get("waiting", false)), _last_effects(s))
	await shot("waiting")
	await _go(gs, "mine-entrance")
	step("and come along again", bool(mule.get("led", false)) and not bool(mule.get("waiting", false)), _last_effects(s))
	await _go(gs, GATE)

	# The forest: the road ends at the trail, the cart stays, the horse goes on.
	await _go(gs, "pushcha-edge")
	await _go(gs, "pushcha-trail")
	WeatherRules._state(s)["by_loc"]["pushcha"] = "clear"  # a downpour of the day shuts the ford (v0.7.46)
	WeatherRules._flags(s, data)
	await _go(gs, "pushcha-glade")
	step("the cart stops off the road", PropertyRules.room_of(s, mid) == "pushcha-trail", _last_effects(s))
	step("the horse goes on", PropertyRules.room_of(s, str(horse["id"])) == "pushcha-glade")
	await shot("no_road")


func _go(gs: Node, to: String) -> void:
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	var ok: bool = gs.go(to)
	step("walked to %s" % to, ok)
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(3)


func _last_effects(s: GameSession) -> String:
	for i in range(s.chat.size() - 1, -1, -1):
		if str(s.chat[i].get("kind", "")) == GameSession.KIND_EFFECT:
			return " · ".join(s.chat[i]["lines"])
	return ""
