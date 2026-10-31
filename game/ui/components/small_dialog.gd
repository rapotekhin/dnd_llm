class_name SmallDialog
extends Control
## Small overlays of v0.6.0 over the game screen: the short rest (how many hit dice to spend), the prepared
## spells of the day and (v0.7.8) the long rest — a room at the inn, or a camp with food picked from the pack.
## Rules are ExplorationRules / SpellRules; the dialog only collects the choice. One window template since
## v0.7.22.29 (ModalFrame, С4): the short rest «−/+» with the expected healing (О1), the preparation by circle with
## a counter and the spell's text on the right (О2). v0.7.41: hunting or fishing — the hours by «−/+» with the ground's
## stock, the check and the gear.

const SHORT_REST := "short_rest"
const PREPARE := "prepare"
const LONG_REST := "long_rest"
const WILDS := "wilds"

var kind: String
var picks: Array = []
## The food picked for a camp: {item_id: qty}.
var supplies: Dictionary = {}
## Hit dice to spend on a short rest.
var dice: int = 0
## The ground of a hunt or a fishing (rules.wilds.kinds) and its hours.
var ground: String = ""
var hours: int = 2
var confirm: Button
var frame: ModalFrame
var _box: VBoxContainer
var _details: DetailsPanel


func _init(dialog_kind: String) -> void:
	kind = dialog_kind


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.make("", {SHORT_REST: 600.0, LONG_REST: 720.0, WILDS: 600.0}.get(kind, 1100.0))
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	_box = frame.body
	if kind == PREPARE:
		var split := HBoxContainer.new()
		split.add_theme_constant_override("separation", 16)
		frame.body.add_child(split)
		_box = VBoxContainer.new()
		_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_box.add_theme_constant_override("separation", 10)
		split.add_child(_box)
		_details = DetailsPanel.new(Vector2(400, 320))
		_details.name = "PrepDetails"
		_details.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		split.add_child(_details)
	frame.add_button("BTN_CANCEL", func() -> void: visible = false)
	confirm = frame.add_button({SHORT_REST: "BTN_REST_CONFIRM", LONG_REST: "BTN_CAMP_CONFIRM", WILDS: "BTN_WILDS_CONFIRM"}.get(kind, "BTN_PREP_CONFIRM"), _on_confirm, true)
	confirm.name = "DialogConfirm"
	visibility_changed.connect(func() -> void:
		if visible and GameState.has_session():
			var c := GameState.session.character
			picks = (c.get("spells", {}).get("prepared", []) as Array).duplicate() if kind == PREPARE else []
			if kind == LONG_REST:
				supplies = ExplorationRules.camp_default(c, Catalog.data)
			if kind == SHORT_REST:
				dice = mini(ExplorationRules.hit_dice_left(c), 1) if int(c["hp"]) < int(c["max_hp"]) else 0
		_rebuild())


func open() -> void:
	visible = true


func _text(text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	_box.add_child(l)
	return l


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	for ch in _box.get_children():
		_box.remove_child(ch)
		ch.queue_free()
	frame.set_note("")
	var s := GameState.session
	var c := s.character
	var data := Catalog.data
	if kind == SHORT_REST:
		_short_rest(s, c, data)
	elif kind == WILDS:
		_wilds(s, data)
	elif kind == LONG_REST:
		_long_rest(s, data)
	else:
		_prepare(s, c, data)


## The short rest (О1): «−/+» over the hit dice with the expected healing; at full HP only the features come back.
func _short_rest(s: GameSession, c: Dictionary, data: Dictionary) -> void:
	frame.title.text = tr("SHORT_REST_TITLE")
	_text(tr("SIDE_HP_AC").format({"hp": c["hp"], "max": c["max_hp"], "ac": c["ac"]}))
	var left := ExplorationRules.hit_dice_left(c)
	var die := int(CharacterRules.class_def(c, data).get("hit_die", 8))
	if int(c["hp"]) >= int(c["max_hp"]):
		dice = 0
		_text(tr("SHORT_REST_FULL"), UiTheme.MUTED_LABEL)
	else:
		_text(tr("SHORT_REST_DICE").format({"die": die, "left": left}))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_box.add_child(row)
		row.add_child(_step_button("DiceMinus", "−", dice <= 0, func() -> void: dice = maxi(0, dice - 1)))
		var count := Label.new()
		count.name = "HitDice"
		count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		count.theme_type_variation = UiTheme.HEADING
		count.custom_minimum_size = Vector2(48, 0)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.text = str(dice)
		row.add_child(count)
		row.add_child(_step_button("DicePlus", "+", dice >= left, func() -> void: dice = mini(left, dice + 1)))
		var con := CharacterRules.mod(CharacterRules.ability(c, "con"))
		var mult := 2 if CharacterRules.item_prop(c, "wound_closure") else 1
		var expect := mini(int(c["max_hp"]) - int(c["hp"]), roundi(dice * maxf(0.0, die / 2.0 + 0.5 + con) * mult))
		var heal := Label.new()
		heal.name = "DiceHeal"
		heal.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		heal.text = tr("SHORT_REST_EXPECT").format({"hp": expect}) if dice > 0 else ""
		heal.add_theme_color_override("font_color", UiTheme.OK)
		row.add_child(heal)
	_text(tr("SHORT_REST_UNTIL").format({"clock": TimeRules.clock_after(s, int(TimeRules.cfg(data)["short_rest_minutes"]))}))
	_text(tr("SHORT_REST_HINT").format({"left": int(data["rules"]["rest"]["short_rests_per_day"]) - s.short_rests}), UiTheme.MUTED_LABEL)
	confirm.disabled = GameState.is_busy()


## Hunting or fishing (v0.7.41): «−/+» over the hours, the stock left, the check and what the gear gives.
func _wilds(s: GameSession, data: Dictionary) -> void:
	var d := WildsRules.kind(data, ground)
	frame.title.text = str(d.get("name", ""))
	if d.is_empty():
		confirm.disabled = true
		return
	var span: Array = d["hours"]
	hours = clampi(hours, int(span[0]), int(span[1]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_box.add_child(row)
	row.add_child(_step_button("HoursMinus", "−", hours <= int(span[0]), func() -> void: hours = maxi(int(span[0]), hours - 1)))
	var count := Label.new()
	count.name = "WildsHours"
	count.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	count.theme_type_variation = UiTheme.HEADING
	count.custom_minimum_size = Vector2(96, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.text = TimeRules.span(hours * 60)
	row.add_child(count)
	row.add_child(_step_button("HoursPlus", "+", hours >= int(span[1]), func() -> void: hours = mini(int(span[1]), hours + 1)))
	_text(tr("WILDS_CHECK").format({"skill": CraftRules.tr_skill(data, str(d["skill"])), "dc": int(d["dc"]),
		"bonus": "%+d" % (int(s.character.get("skills", {}).get(str(d["skill"]), 0)) + DifficultyRules.bonus(s, data))}))
	var g := WildsRules.gear(s, data, ground)
	if not str(g["adv"]).is_empty():
		_text(tr("WILDS_ADV").format({"item": g["adv"]}), UiTheme.MUTED_LABEL)
	if not str(g["dis"]).is_empty():
		_text(tr("WILDS_DIS"), UiTheme.MUTED_LABEL)
	_text(tr("WILDS_STOCK").format({"n": WildsRules.stock(s, data, ground), "max": int(d["stock"])}))
	if WildsRules.poaching(s, data):
		_text(tr("WILDS_POACH").format({"owner": BondRules.npc_name(s, data, WildsRules.owner(s, data))}), UiTheme.MUTED_LABEL)
	_text(tr("WILDS_UNTIL").format({"clock": TimeRules.clock_after(s, hours * 60)}))
	var why := WildsRules.why_not(s, data, ground)
	frame.set_note(why)
	confirm.disabled = not why.is_empty() or GameState.is_busy()


func _step_button(node_name: String, text: String, off: bool, change: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.custom_minimum_size = Vector2(52, 52)
	b.disabled = off
	b.pressed.connect(func() -> void:
		change.call()
		_rebuild())
	return b


## The spells of the day (О2): «Выбрано 2 из 4», the pool by circle, the spell's text on the right.
func _prepare(s: GameSession, c: Dictionary, data: Dictionary) -> void:
	var p := SpellRules.prepare_pool(c, data)
	var n := mini(int(p["count"]), (p["pool"] as Array).size())
	picks = picks.filter(func(id: Variant) -> bool: return (p["pool"] as Array).has(id))
	frame.title.text = tr("PREP_TITLE").format({"n": n})
	var count := _text(tr("PREP_COUNT").format({"picked": picks.size(), "n": n}), UiTheme.HEADING)
	count.name = "PrepCount"
	count.add_theme_color_override("font_color", UiTheme.OK if picks.size() == n else UiTheme.ACCENT_BRIGHT)
	var by_level := {}
	for id: Variant in p["pool"]:
		var lv := int(data["spells"].get(str(id), {}).get("level", 1))
		if not by_level.has(lv):
			by_level[lv] = []
		by_level[lv].append(str(id))
	var levels := by_level.keys()
	levels.sort()
	for lv: Variant in levels:
		_text(tr("DETAILS_CIRCLE").format({"n": int(lv)}), UiTheme.MUTED_LABEL)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 12)
		flow.add_theme_constant_override("v_separation", 8)
		_box.add_child(flow)
		for id: String in by_level[lv]:
			flow.add_child(_prep_box(id, n, data))
	var err := SpellRules.prepare_error(c, data, s.day, picks)
	frame.set_note(tr(err) if not err.is_empty() and picks.size() == n else "")
	confirm.disabled = not err.is_empty() or GameState.is_busy()


func _prep_box(id: String, n: int, data: Dictionary) -> CheckBox:
	var sp: Dictionary = data["spells"].get(id, {})
	var cb := CheckBox.new()
	cb.name = "Prep_" + id
	cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cb.text = str(sp.get("name", id))
	cb.button_pressed = picks.has(id)
	cb.disabled = not picks.has(id) and picks.size() >= n
	_details.hook(cb, str(sp.get("name", id)), DetailsPanel.spell_text(data, id))
	cb.toggled.connect(func(on: bool) -> void:
		if on and not picks.has(id) and picks.size() < n:
			picks.append(id)
		elif not on:
			picks.erase(id)
		_rebuild.call_deferred())
	return cb


## The long rest (v0.7.8): an inn's room for its price when there is one here; a camp for food from the pack.
func _long_rest(s: GameSession, data: Dictionary) -> void:
	var c := s.character
	frame.title.text = tr("LONG_REST_TITLE")
	_text(tr("LONG_REST_GIVES").format({"clock": "%02d:00" % (int(TimeRules.cfg(data)["wake_minute"]) / 60)}), UiTheme.MUTED_LABEL)
	var place := ExplorationRules.rest_place(data["world"], s.room_id, s, data)
	if not place.is_empty():
		var cost := int(place["cost_cp"])
		var inn := Button.new()
		inn.name = "RestInn"
		inn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		inn.text = tr("BTN_LONG_REST_COST").format({"cost": Money.format(cost)}) if cost > 0 \
			else tr("BTN_OWN_BED") if bool(place.get("own", false)) \
			else tr("BTN_LONG_REST_FREE") if bool(place.get("free", false)) else tr("BTN_LONG_REST")
		inn.custom_minimum_size = Vector2(0, 56)
		inn.theme_type_variation = UiTheme.ACCENT_BUTTON
		var why := ExplorationRules.can_rest(s, data["world"], data)
		inn.disabled = GameState.is_busy() or not why.is_empty()
		inn.tooltip_text = tr(why) if not why.is_empty() else ""
		inn.pressed.connect(func() -> void: _done(GameState.long_rest()))
		_box.add_child(inn)
	_text(tr("LONG_REST_CAMP").format({"need": ExplorationRules.camp_need(data)}), UiTheme.HEADING)
	if BackgroundRules.can_forage(s, data):  # an outlander finds food (v0.7.11)
		var forage := Button.new()
		forage.name = "RestForage"
		forage.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		forage.text = tr("LONG_REST_FORAGE")
		forage.custom_minimum_size = Vector2(0, 48)
		forage.disabled = GameState.is_busy() or not ExplorationRules.can_camp(s, data).is_empty()
		forage.pressed.connect(func() -> void: _done(GameState.long_rest({"forage": 1})))
		_box.add_child(forage)
	var have := ExplorationRules.camp_food(c, data)
	var food: Dictionary = data["rules"]["hero_effects"]["camp"]["food"]
	if have.is_empty():
		_text(tr("LONG_REST_NO_FOOD"), UiTheme.MUTED_LABEL)
	for id: String in have:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_box.add_child(row)
		var l := Label.new()
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = tr("LONG_REST_FOOD").format({"item": ItemRules.display_name(data["items"], s.items, id), "have": int(have[id]), "points": int(food[id])})
		row.add_child(l)
		var spin := SpinBox.new()
		spin.name = "Supply_" + id
		spin.min_value = 0
		spin.max_value = int(have[id])
		spin.value = int(supplies.get(id, 0))
		spin.value_changed.connect(func(v: float) -> void:
			supplies[id] = int(v)
			_rebuild.call_deferred())
		row.add_child(spin)
	_text(tr("LONG_REST_POINTS").format({"have": ExplorationRules.camp_points(data, supplies), "need": ExplorationRules.camp_need(data)}))
	var err := ExplorationRules.camp_error(s, data, supplies)
	frame.set_note(tr(err) if not err.is_empty() else "")
	confirm.disabled = not err.is_empty() or GameState.is_busy()


func _done(err: String) -> void:
	if err.is_empty():
		visible = false
	else:
		frame.set_note(tr(err))


func _on_confirm() -> void:
	if kind == LONG_REST:
		_done(GameState.long_rest(supplies))
	elif kind == SHORT_REST:
		_done(GameState.short_rest(dice))
	elif kind == WILDS:
		_done(GameState.wilds_act(ground, hours))
	else:
		_done(GameState.prepare_spells(picks))
