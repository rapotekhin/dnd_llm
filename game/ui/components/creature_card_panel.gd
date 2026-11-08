class_name CreatureCardPanel
extends ModalFrame
## The card of any creature (v0.8.4.41, the author: as in BG3 and Pathfinder) — a person, a monster, a follower, a summoned
## ally, in a fight and out of it: opened by «Осмотреть» on the side panel and from a foe's menu in a fight. It only draws
## `CreatureCard.of`: the numbers and what it does when its kind is known, else «?» and «Присмотреться» — the one knowledge
## check (`GameState.inspect`: a bonus action in a fight, once a creature out of it); always its statuses with their
## source and time and what it wears.

const SCENE := "res://ui/components/creature_card_panel.tscn"

var who := ""
var _box: VBoxContainer


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseCardButton"
	_box = body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open(id: String) -> void:
	who = id
	visible = true
	_rebuild()


func _rebuild() -> void:
	if not visible or not GameState.has_session():
		return
	clear_body()
	var w := GameState.creature_who(who)
	if w.is_empty():
		visible = false
		return
	var c := CreatureCard.of(GameState.session, Catalog.data, w)
	title.text = str(c["name"])
	fill(_box, c)
	if not bool(c["known"]):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		_box.add_child(row)
		var why := GameState.inspect_why(who)
		var b := UiParts.act_button(row, "CardLook", tr("BTN_FOE_INSPECT"), why, GameState.inspect.bind(who))
		if why.is_empty():
			b.tooltip_text = tr("BTN_CARD_LOOK_FIGHT_TIP" if CombatRules.active(GameState.session) else "BTN_FOE_INSPECT_TIP")


## The card's sections into `box`: one drawing for every place that shows a creature.
static func fill(box: VBoxContainer, c: Dictionary) -> void:
	var known := bool(c["known"])
	var kind := "%s %s" % [_t("SIZE_" + str(c["size"]).to_upper()), _t("CREATURE_TYPE_" + str(c["type"]).to_upper()).to_lower()]
	if known and c.get("cr") != null:
		kind += " · " + _t("CARD_CR").format({"cr": _cr(c["cr"])})
	UiParts.label(box, "%s · %s" % [kind, _t(str(c["health"]))], UiTheme.MUTED_LABEL)
	var hp := "%d/%d%s" % [int(c["hp"]), int(c["max_hp"]), (" +%d" % int(c["temp_hp"])) if int(c["temp_hp"]) > 0 else ""] if known else CreatureCard.HIDDEN
	UiParts.label(box, _t("CARD_NUMBERS").format({"ac": str(c["ac"]) if known else CreatureCard.HIDDEN, "hp": hp,
		"speed": CreatureCard.speed_text(c) if known else CreatureCard.HIDDEN})).name = "CardNumbers"
	if not known:
		UiParts.label(box, _t("CARD_HIDDEN").format({"skill": _t("SKILL_" + str(c["lore"]["skill"]).to_upper()), "dc": int(c["lore"]["dc"])}),
			UiTheme.MUTED_LABEL).name = "CardHidden"
	else:
		_numbers(box, c)
		_acts(box, c)
	_statuses(box, c)
	_worn(box, c)


static func _numbers(box: VBoxContainer, c: Dictionary) -> void:
	UiParts.label(box, _t("CARD_PASSIVE").format({"n": int(c["passive"]), "prof": int(c["prof"])}), UiTheme.MUTED_LABEL)
	UiParts.label(box, " · ".join((c["abilities"] as Array).map(func(a: Dictionary) -> String:
		return "%s %d (%+d)" % [CombatRules.ab_name(str(a["id"])), int(a["score"]), int(a["mod"])]))).name = "CardAbilities"
	UiParts.label(box, _t("CARD_SAVES").format({"list": ", ".join((c["saves"] as Array).map(func(v: Dictionary) -> String:
		return "%s %+d%s" % [CombatRules.ab_name(str(v["id"])), int(v["bonus"]), _mode(v)]))}))
	if not (c["skills"] as Array).is_empty():
		UiParts.label(box, _t("CARD_SKILLS").format({"list": ", ".join((c["skills"] as Array).map(func(k: Dictionary) -> String:
			return "%s %+d" % [_t("SKILL_" + str(k["id"]).to_upper()), int(k["bonus"])]))}))
	var langs: Array = c["languages"]
	UiParts.label(box, _t("CARD_LANGUAGES").format({"list": ", ".join(langs) if not langs.is_empty() else _t("CARD_NO_LANGUAGES")}), UiTheme.MUTED_LABEL)


static func _acts(box: VBoxContainer, c: Dictionary) -> void:
	if not (c["blows"] as Array).is_empty() or not (c["reactions"] as Array).is_empty():
		UiParts.heading(box, _t("CARD_BLOWS"))
		for b: Dictionary in c["blows"]:
			UiParts.label(box, "%s: %s" % [b["name"], b["text"]], UiTheme.MUTED_LABEL if bool(b["stowed"]) else "")
		for r: String in c["reactions"]:
			UiParts.label(box, _t("CARD_REACTION").format({"what": r}))
	if not (c["features"] as Array).is_empty() or not (c["resources"] as Array).is_empty():
		UiParts.heading(box, _t("CARD_FEATURES"))
		for f: Dictionary in c["features"]:
			var l := UiParts.label(box, "%s — %s" % [f["name"], str(f["text"]).left(220)] if not str(f["text"]).is_empty() else str(f["name"]))
			l.tooltip_text = str(f["text"])
			l.mouse_filter = Control.MOUSE_FILTER_PASS
		if not (c["resources"] as Array).is_empty():
			UiParts.label(box, _t("CARD_RESOURCES").format({"list": ", ".join((c["resources"] as Array).map(func(r: Dictionary) -> String:
				return "%s %d/%d" % [r["name"], int(r["left"]), int(r["max"])]))}))
	var sp: Dictionary = c["spells"]
	if not (sp["list"] as Array).is_empty() or not (sp["slots"] as Array).is_empty():
		UiParts.heading(box, _t("CARD_SPELLS"))
		if int(sp["dc"]) > 0:
			UiParts.label(box, _t("CARD_SPELL_DC").format({"dc": int(sp["dc"])}), UiTheme.MUTED_LABEL)
		if not (sp["list"] as Array).is_empty():
			UiParts.label(box, ", ".join(sp["list"]))
		if not (sp["slots"] as Array).is_empty():
			UiParts.label(box, _t("CARD_SLOTS").format({"list": " · ".join((sp["slots"] as Array).map(func(x: Dictionary) -> String:
				return _t("CARD_SLOT").format({"n": int(x["circle"]), "left": int(x["left"]), "max": int(x["max"])})))}))
	if not (c["defenses"] as Array).is_empty():
		UiParts.heading(box, _t("CARD_DEFENSES"))
		for d: Dictionary in c["defenses"]:
			UiParts.label(box, "%s: %s (%s)" % [d["word"], d["what"], d["source"]])


static func _statuses(box: VBoxContainer, c: Dictionary) -> void:
	UiParts.heading(box, _t("CARD_STATUSES"))
	var list: Array = c["statuses"]
	if list.is_empty():
		UiParts.label(box, _t("CARD_NO_STATUSES"), UiTheme.MUTED_LABEL)
	for e: Dictionary in list:
		var src := str(e["source"])
		var l := UiParts.label(box, "%s — %s%s" % [e["name"], e["left"], (" · " + _t("CARD_SOURCE").format({"source": src})) if not src.is_empty() else ""])
		l.name = "CardStatus_" + str(e["name"]).validate_node_name()
		var does := str(e.get("does", ""))
		if not does.is_empty():
			UiParts.label(box, does, UiTheme.MUTED_LABEL)
		l.tooltip_text = str(e["text"])
		l.mouse_filter = Control.MOUSE_FILTER_PASS


static func _worn(box: VBoxContainer, c: Dictionary) -> void:
	UiParts.heading(box, _t("CARD_WORN"))
	var list: Array = c["worn"]
	if list.is_empty():
		UiParts.label(box, _t("GEAR_NONE"), UiTheme.MUTED_LABEL)
	var s := GameState.session
	for w: Dictionary in list:
		var l := UiParts.label(box, _t("GEAR_SLOT_LINE").format({"slot": _t("SLOT_" + str(w["slot"]).to_upper()), "item": w["name"]}) +
			(" · " + str(w["kind"]) if not str(w["kind"]).is_empty() else "") + (" · " + _t("CARD_SPARE") if bool(w["spare"]) else ""))
		l.name = "CardWorn_" + str(w["item"]).validate_node_name()
		l.tooltip_text = "\n".join(ItemInfo.lines({}, Catalog.data, s.items, str(w["item"]))) if s != null else ""
		l.mouse_filter = Control.MOUSE_FILTER_PASS


static func _mode(v: Dictionary) -> String:
	if bool(v.get("failed", false)):
		return " (%s)" % _t("CARD_FAIL")
	if bool(v["adv"]) and not bool(v["dis"]):
		return " (%s)" % _t("CARD_ADV")
	if bool(v["dis"]) and not bool(v["adv"]):
		return " (%s)" % _t("CARD_DIS")
	return ""


static func _cr(cr: Variant) -> String:
	var v := float(cr)
	return {0.125: "1/8", 0.25: "1/4", 0.5: "1/2"}.get(v, str(int(v)))


static func _t(key: String) -> String:
	return str(TranslationServer.translate(key))
