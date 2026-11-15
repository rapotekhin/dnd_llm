extends "res://tools/playtest/playtest_base.gd"
## Chests, bodies and prisoners without the master (python tools/godot_playtest.py --scenario no_master), v0.8.4.44.3:
## the tavern's hall is given a chest of the pack with coins, an empty crate, a smuggler's body and a bound carter; the
## chest's window takes the coins, the crate holds what the engine laid, the body is searched, «Развязать» frees the
## carter — a rescue, he goes along.

const CELLAR := "brod-tavern-hall"  # the start room: seeded at the game's start


func run() -> void:
	var gs := node("GameState")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	var data: Dictionary = node("Catalog").data
	var room: Dictionary = data["world"]["rooms"][CELLAR]
	room["props"] = [
		{"id": "strongbox", "name": "Окованный сундук", "description": "Сундук контрабандистов у стены.", "container": "chest",
			"contents": {"healing_potion": 2, "rope": 1}, "coins_cp": 2500, "body": "chest"},
		{"id": "crate", "name": "Ящик", "description": "Ящик у стены.", "container": "crate", "body": "crate"}]
	room["creatures"] = [
		{"id": "smuggler", "monster": "bandit", "name": "Контрабандист", "state": "dead", "coins_cp": 40},
		{"id": "carter", "monster": "commoner", "name": "Пленный возчик", "state": "bound", "joins": true}]
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var s: GameSession = gs.session
	await frames(4)
	var tokens := MapSpots.of(s, data, WalkRules.view(s, data))
	var refs := tokens.map(func(t: Dictionary) -> String: return str(t["ref"]))
	step("the chest stands on the map as a chest", tokens.any(func(t: Dictionary) -> bool: return str(t["ref"]) == "prop:f_strongbox" and str(t.get("body", "")) == "chest"), ", ".join(refs))
	var crate := PropRules.find(s, CELLAR, "f_crate")
	step("the crate holds what the engine laid", not (crate.get("contents", {}) as Dictionary).is_empty(), ContainerRules.contents_text(data, s.items, crate.get("contents", {})))
	var here := CreatureRules.here(s, CELLAR)
	var body: Dictionary = here.filter(func(c: Dictionary) -> bool: return str(c.get("pack", "")) == "smuggler")[0] if not here.is_empty() else {}
	var carter: Dictionary = here.filter(func(c: Dictionary) -> bool: return str(c.get("pack", "")) == "carter")[0] if here.size() > 1 else {}
	step("the smuggler lies here, the carter is bound", str(body.get("state", "")) == CreatureRules.DEAD and CreatureRules.held(carter), str(here.map(func(c: Dictionary) -> String: return str(c["name"]))))
	await shot("cellar")

	var place: Button = find(screen(), "PlaceButton")
	if step("the place button", place != null and not place.disabled):
		await press(place)
		await frames(3)
		var open: Button = find(screen(), "Container_f_strongbox")
		if step("the place window offers the chest", open != null and not open.disabled):
			await press(open)
			await frames(3)
			var view: Control = find(screen(), "ContainerView")
			var take: Button = find(view, "TakeCoins") if view != null else null
			step("the chest's window shows its coins", take != null and not take.disabled)
			await shot("chest_coins")
			if take != null:
				var gold := Ledger.balance(s)
				await press(take)
				await wait_until(func() -> bool: return not gs.is_busy(), 30.0)
				await frames(3)
				step("the coins are in the purse", Ledger.balance(s) - gold == 2500, "%d" % (Ledger.balance(s) - gold))
			await press(find(view, "CloseContainerButton"))
			await frames(3)

	var gold2 := Ledger.balance(s)
	step("the body searched like one after a fight", gs.creature_act(str(body.get("id", "")), "search").is_empty() and Ledger.balance(s) - gold2 == 40,
		"%d" % (Ledger.balance(s) - gold2))
	var whats := CreatureRules.acts(s, data, carter).map(func(a: Array) -> String: return str(a[0]))
	step("the carter is untied, not let go", whats.has("untie") and not whats.has("free"), ", ".join(whats))
	var crimes := s.crimes.size()
	step("«Развязать»", gs.creature_act(str(carter.get("id", "")), "untie").is_empty())
	await wait_until(func() -> bool: return not gs.is_busy(), 60.0)
	await frames(4)
	step("a rescue: free, along with the hero, no crime", not bool(carter.get("bound", true)) and bool(carter.get("ally", false)) and s.crimes.size() == crimes,
		"%s" % carter)
	await shot("rescued")
