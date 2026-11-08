extends "res://tools/playtest/playtest_base.gd"
## Services (python tools/godot_playtest.py --scenario services), v0.8.4.35: the hermit Мох, no trader, has «Услуги»
## under his row; the master's create:service lays a ward of the road at him — bought by its button, the status on the
## hero; the smith silvers the sword in the hand — the same sword, its copy marked, the blow silvered.

const GLADE := "pushcha-glade"
const HERMIT := "npc_hermit"
const SMITHY := "brod-smithy"
const SMITH := "npc_smith"


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
	var data: Dictionary = node("Catalog").data  # the game's own, merged at the start
	s.settings["needs"] = false
	still_sky(s)
	s.minute = 12 * 60
	s.character["gold_cp"] = 50000
	s.character["level"] = 3
	CharacterRules.refresh(s.character, data, s.items)

	step("to the glade", gs.teleport(GLADE).is_empty())
	await wait_until(func() -> bool: return not gs.is_busy() and s.room_id == GLADE, 60.0)
	await frames(4)
	var fx := EffectEngine.new()
	var ward := {"kind": "make", "what": "status", "key": "ward", "name": "Оберег путника", "text": "Тропа бережёт.",
		"parts": [{"part": "save_adv", "value": "con"}]}
	var made := {"kind": "create", "what": "service", "npc_id": HERMIT, "op": "status", "name": "Наложить оберег путника",
		"done": "оберег наложен", "status": "new:ward", "hours": 8}
	var ids: Array = []
	for e: Dictionary in [ward, made]:
		var r := fx.validate(s, data, "t-1", e)
		step("the master's %s accepted" % e["what"], bool(r["accepted"]), str(r.get("reason", r.get("summary", ""))))
		ids.append(r.get("effect_id", ""))
	fx.apply(s, "t-1", ids)
	step("the hermit offers it now", ServiceRules.of(s, data, HERMIT).size() == 2)
	node("EventBus").state_changed.emit()
	await frames(4)
	await open_row("More_" + HERMIT)
	await open_row("More_" + HERMIT)
	var fold: Button = find(screen(), "Fold_services_" + HERMIT)
	if fold != null:
		await press(fold)
		await frames(2)
	await shot("hermit_services")
	var sid := ""
	for x: Variant in ServiceRules.ids_of(data, HERMIT):
		if str(ServiceRules.def_of(data, str(x)).get("name", "")) == "Наложить оберег путника":
			sid = str(x)
	var b: Button = find(screen(), "Service_%s_%s" % [sid, HERMIT])
	if step("«Услуги» at the hermit, no trader", b != null and not b.disabled, b.text if b != null else "no button"):
		var gold := Ledger.balance(s)
		await press(b)
		await frames(4)
		step("the ward bought: coins off, the status on the hero", Ledger.balance(s) < gold and ConditionRules.effects(s.character).any(
			func(e: Dictionary) -> bool: return str(e.get("source", {}).get("id", "")) == sid))
		await open_row("More_" + HERMIT)
		if find(screen(), "Fold_services_" + HERMIT) != null:
			await press(find(screen(), "Fold_services_" + HERMIT))
			await frames(2)
		b = find(screen(), "Service_%s_%s" % [sid, HERMIT])
		step("not twice at once", b != null and b.disabled, b.tooltip_text if b != null else "")
		await shot("ward_bought")

	step("to the smithy", gs.teleport(SMITHY).is_empty())
	await wait_until(func() -> bool: return not gs.is_busy() and s.room_id == SMITHY, 60.0)
	await frames(4)
	var c := s.character
	var sword := str(c["equipped"]["main_hand"])
	await open_row("More_" + SMITH)
	var fold2: Button = find(screen(), "Fold_services_" + SMITH)
	if fold2 != null:
		await press(fold2)
		await frames(2)
	var silver: Button = find(screen(), "Service_silver_" + SMITH)
	if silver == null:
		silver = find(screen(), "Service_silver_%s_%s" % [SMITH, sword])  # one button per thing when several fit
	await shot("smith_services")
	if step("silver on the smith's side panel", silver != null and not silver.disabled, silver.text if silver != null else "no button"):
		await press(silver)
		await frames(4)
		step("the same sword in the hand, its copy marked", str(c["equipped"]["main_hand"]) == sword and ItemRules.marks(c, sword).has("silvered"))
		step("the blow is silvered", bool(CombatRules.weapon_profile(c, data, s.items, sword)["silvered"]))
		step("the sword's card says so", ItemInfo.lines(c, data, s.items, sword).any(func(l: String) -> bool: return l.contains("посеребрено")),
			" | ".join(ItemInfo.lines(c, data, s.items, sword)))
		await shot("silvered")
