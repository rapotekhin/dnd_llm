extends "res://tools/playtest/playtest_base.gd"
## Leading a companion as in BG3 (python tools/godot_playtest.py --scenario lead), v0.8.4.44.12, the author: «клик на
## портрет союзника должен … давать управление союзником … а не начинать диалог». On the square of Brod with a mercenary:
## a click on its portrait leads it — the token is its face, the bar its own, the hero walks after it; a click on the map
## walks the mercenary; its portrait again opens its sheet; the hero's portrait takes the hero back. v0.8.4.44.13: the
## mercenary's potion drunk by it from its bar, the priestess led heals the hero with her own Cure Wounds, the mercenary
## forges a dagger at the smithy with its own tools.


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 60.0)):
		return
	var s: GameSession = gs.session
	var data: Dictionary = node("Catalog").data
	s.room_id = "brod-square"
	Being.follow(s, "npc_mercenary")
	ItemRules.add(Gear.of(s, data, "npc_mercenary"), "healing_potion", 2)
	if ItemRules.belt_why(Gear.of(s, data, "npc_mercenary"), data, s.items, "healing_potion").is_empty():
		ItemRules.belt_put(Gear.of(s, data, "npc_mercenary"), data, s.items, "healing_potion")
	node("EventBus").state_changed.emit()
	await frames(4)
	var field: Control = find(screen(), "Field")
	var bar := screen().get_tree().get_first_node_in_group("hotbar") as Control
	await shot("hero_leads")

	var merc: Control = find(screen(), "Portrait_npc_mercenary")
	if not step("the mercenary's portrait in the party", merc != null):
		return
	var merc_cell := MapSpots.square_of(s, data, "npc_mercenary")
	await press(merc)
	await frames(4)
	step("a click on its portrait leads it, no talk", PartyLead.of(s) == "npc_mercenary" and not s.in_conversation())
	step("the token stands where the mercenary stood", field.call("hero_cell") == merc_cell, "%s / %s" % [field.call("hero_cell"), merc_cell])
	step("the token's face is the mercenary's", str(field.get("hero_face")) == PortraitRules.of_id(s, data, "npc_mercenary"))
	step("its portrait lit in the party", bool(find(screen(), "Portrait_npc_mercenary").get("picked")))
	step("the bar is the mercenary's", str((bar.get("who") as Dictionary).get("id", "")) == "npc_mercenary")
	step("its belt's potion on the bar, once", find(bar, "Pin_item_healing_potion") != null
		and bar.find_children("Pin_item_*", "", true, false).size() == 1)
	step("the hero walks with the rest", MapSpots.walkers(s, data).any(func(t: Dictionary) -> bool: return str(t["kind"]) == "hero"))
	await shot("mercenary_leads")

	var map: Dictionary = field.get("map")
	var from: Vector2i = field.call("hero_cell")
	var to := Vector2i(-1, -1)
	for c: Vector2i in WalkRules.around(map, data["layouts"], from, 40):
		if WalkRules.distance(c, from) >= 3 and WalkRules.room_of(map, c) == s.room_id and WalkRules.passable(map, data["layouts"], c) \
				and str(field.call("ref_at", c)).is_empty():
			to = c
	if step("a free square a few steps off", to.x >= 0):
		field.emit_signal("cell_clicked", to)
		await wait_until(func() -> bool: return not field.call("walking"), 20.0)
		await frames(6)
		step("the mercenary walked there", WalkRules.settle(s, data, WalkRules.view(s, data)) == to and field.call("hero_cell") == to)
		step("the hero came after it", WalkRules.distance(MapSpots.square_of(s, data, Being.HERO), to) <= 3,
			str(MapSpots.square_of(s, data, Being.HERO)))
		await shot("mercenary_walked")

	await press(find(screen(), "Portrait_npc_mercenary"))
	await frames(4)
	var sheet := screen().get_tree().root.find_child("CharacterSheet", true, false) as Control
	step("its portrait again opens its sheet", sheet != null and sheet.visible and str(sheet.get("who")) == "npc_mercenary")
	await shot("mercenary_sheet")
	if sheet != null:
		sheet.visible = false
		await frames(2)

	# v0.8.4.44.13: the one led acts on the hero's road — its potion pinned and drunk by it, not by the hero
	var potions := int(Gear.of(s, data, "npc_mercenary")["inventory"].get("healing_potion", 0))
	var hero_potions := int(s.character.get("inventory", {}).get("healing_potion", 0))
	Being.of(s, "npc_mercenary")["hp"] = 2
	node("EventBus").state_changed.emit()
	await frames(3)
	var pin := find(bar, "Pin_item_healing_potion") as BaseButton
	pin.button_pressed = true  # a toggle, as a player pins it
	await press(pin)
	await frames(2)
	step("its potion pinned as its own", str(gs.attached.get("who", "")) == "npc_mercenary", str(gs.attached))
	step("drunk by it: the pin sent alone", bool(gs.submit("")))
	await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
	step("the mercenary's potion went, the hero's stayed", int(Gear.of(s, data, "npc_mercenary")["inventory"].get("healing_potion", 0)) == potions - 1
		and int(s.character.get("inventory", {}).get("healing_potion", 0)) == hero_potions)
	step("the mercenary healed", Sheet.hp(s, data, Sheet.who(s, data, "npc_mercenary")) > 2)

	await press(find(screen(), "Portrait_hero"))
	await frames(4)
	step("the hero's portrait takes the hero back", PartyLead.of(s) == Being.HERO and str(field.get("hero_face")) == PortraitRules.of(s, data, Sheet.HERO))
	step("the bar is the hero's again", Sheet.is_hero(bar.get("who")))
	await shot("hero_back")

	# a caster led: the priestess's own spells on the bar, Cure Wounds on the hero from her slot
	Being.follow(s, "npc_priestess")
	s.character["hp"] = 3
	node("EventBus").state_changed.emit()
	await frames(4)
	await press(find(screen(), "Portrait_npc_priestess"))
	await frames(4)
	step("the priestess led", PartyLead.of(s) == "npc_priestess")
	var cure: Control = find(bar, "Pin_spell_cure_wounds")
	step("her Cure Wounds on the bar", cure != null)
	await shot("priestess_bar")
	if cure != null:
		(cure as BaseButton).button_pressed = true
		await press(cure as BaseButton)
		await frames(2)
		step("pinned as hers", str(gs.attached.get("who", "")) == "npc_priestess")
		step("aimed at the hero's portrait", str(gs.aim_attached(Being.HERO)).is_empty())
		step("cast", str(gs.cast_attached()).is_empty(), str(gs.attached))
		await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
		step("the hero healed by her", int(s.character["hp"]) > 3, str(s.character["hp"]))
		step("her slot spent, not the hero's", SpellRules.slots_left(Sheet.own(s, "npc_priestess"), 1) == 2)
		await shot("priestess_healed")

	# «Ремесло» by the one led (v0.8.4.44.13): the mercenary forges a dagger at the smithy with its own tools and iron
	var smith := Life.of(s, "npc_mercenary", data)
	smith["tools"] = ["smiths_tools"]
	ItemRules.add(smith, "smiths_tools", 1)
	ItemRules.add(smith, "iron_bar", 2)
	Ledger.purse(smith, 1000)
	s.room_id = "brod-smithy"
	s.minute = 9 * 60
	gs.lead("npc_mercenary")
	node("EventBus").state_changed.emit()
	await frames(4)
	var craft_btn: Button = find(screen(), "CraftButton")
	step("«Ремесло» on the mercenary's panel", craft_btn != null)
	if craft_btn == null:
		return
	await press(craft_btn)
	await frames(4)
	var win: Control = find(screen(), "CraftView")
	step("its recipes: the dagger", win != null and win.visible and find(win, "Recipe_dagger") != null)
	await shot("mercenary_craft")
	await press(find(win, "CraftStart_dagger"))
	await frames(3)
	step("its work begun, its iron spent", not CraftRules.project(smith).is_empty() and int(smith["inventory"].get("iron_bar", 0)) == 1
		and CraftRules.project(s.character).is_empty())
	await press(find(win, "CraftWork_8"))
	await frames(4)
	step("a dagger in its things", (smith["inventory"] as Dictionary).keys().any(func(id: String) -> bool:
		return ItemRules.plain_of(data["items"], s.items, id) == "dagger"), str(smith["inventory"]))
	await shot("mercenary_forged")
