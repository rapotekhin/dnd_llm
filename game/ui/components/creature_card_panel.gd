class_name CreatureCardPanel
extends ModalFrame
## The card of any creature (v0.8.4.41, the author: as in BG3 and Pathfinder) — a person, a monster, a follower, a summoned
## ally, in a fight and out of it: opened by «Осмотреть» on the side panel and from a foe's menu in a fight. It only draws
## `CreatureCard.of`: the numbers and what it does when its kind is known, else «?» and «Присмотреться» — the one knowledge
## check (`GameState.inspect`: a bonus action in a fight, once a creature out of it); always its statuses with their
## source and time and what it wears.

const SCENE := "res://ui/components/creature_card_panel.tscn"
const ICON := 44  ## a feature's, a spell's, a defense's and a status's icon (v0.8.4.43.49)
const NAMED := 88  ## the width of its name under it

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
	var pic := Portrait.square(str(c.get("portrait", "")), 128.0)
	if pic != null:  # its face is seen before its numbers are known (v0.8.4.43.5.2)
		pic.name = "CardPortrait"
		pic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(pic)
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
		_icons(box, "CardFeatures", (c["features"] as Array).map(func(f: Dictionary) -> Array:
			return [str(f.get("icon", "")), str(f["name"]), str(f["text"]), CardInfo.feature(Catalog.data, str(f["id"])) if f.has("id") else {}]))
		if not (c["resources"] as Array).is_empty():
			UiParts.label(box, _t("CARD_RESOURCES").format({"list": ", ".join((c["resources"] as Array).map(func(r: Dictionary) -> String:
				return "%s %d/%d" % [r["name"], int(r["left"]), int(r["max"])]))}))
	var sp: Dictionary = c["spells"]
	if not (sp["list"] as Array).is_empty() or not (sp["slots"] as Array).is_empty():
		UiParts.heading(box, _t("CARD_SPELLS"))
		if int(sp["dc"]) > 0:
			UiParts.label(box, _t("CARD_SPELL_DC").format({"dc": int(sp["dc"])}), UiTheme.MUTED_LABEL)
		var ids: Array = sp.get("ids", [])
		if not ids.is_empty():
			var rows: Array = []
			for i in ids.size():
				rows.append([IconRules.ref("spells", str(ids[i])), str(sp["list"][i]), "", CardInfo.spell(Catalog.data, str(ids[i]))])
			_icons(box, "CardSpells", rows)
		if not (sp["slots"] as Array).is_empty():
			UiParts.label(box, _t("CARD_SLOTS").format({"list": " · ".join((sp["slots"] as Array).map(func(x: Dictionary) -> String:
				return _t("CARD_SLOT").format({"n": int(x["circle"]), "left": int(x["left"]), "max": int(x["max"])})))}))
	if not (c["defenses"] as Array).is_empty():
		UiParts.heading(box, _t("CARD_DEFENSES"))
		var rows: Array = []
		for d: Dictionary in c["defenses"]:  # each type or condition its own icon, its word and source on the card
			var names: Array = d.get("names", [])
			var icons: Array = d.get("icons", [])
			for i in mini(names.size(), icons.size()):
				rows.append([str(icons[i]), "%s: %s" % [d["word"], names[i]], _t("CARD_SOURCE").format({"source": d["source"]})])
		_icons(box, "CardDefenses", rows)


static func _statuses(box: VBoxContainer, c: Dictionary) -> void:
	UiParts.heading(box, _t("CARD_STATUSES"))
	var list: Array = c["statuses"]
	if list.is_empty():
		UiParts.label(box, _t("CARD_NO_STATUSES"), UiTheme.MUTED_LABEL)
	var rows: Array = []
	for e: Dictionary in list:  # an icon each, as on the party's portraits: its time under it, its card (`CardInfo.status`) at the cursor
		var card := CardInfo.status(Catalog.data, e, GameState.session.items if GameState.has_session() else {})
		rows.append([str(e.get("icon", IconRules.ref("conditions", str(e["condition"])))), "%s · %s" % [e["name"], e["left"]], CardInfo.plain(card), card])
	var flow := _icons(box, "CardStatuses", rows)
	for i in list.size():
		flow.get_child(i).name = "CardStatus_" + str(list[i]["name"]).validate_node_name()
		(flow.get_child(i).get_child(0) as IconSlot).tooltip_text = str(list[i]["name"])  # the time is on the card


## A row of icons with their names under them (the author, 2026-11-13: «в описании мобов и NPC указывать заклинания,
## способности, устойчивости нашими иконками»): [[ref, name, body, card]] — the card of `CardInfo` when there is one, else
## the name and `body` at the cursor; the right button pins it.
static func _icons(box: VBoxContainer, node_name: String, rows: Array) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = node_name
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 6)
	box.add_child(flow)
	for r: Array in rows:
		var cell := IconSlot.make(str(r[0]), str(r[1]), ICON)
		cell.tip_title = str(r[1])
		cell.tip_body = str(r[2])
		if r.size() > 3 and not (r[3] as Dictionary).is_empty():
			cell.set_card(r[3])
		cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var named := VBoxContainer.new()
		named.custom_minimum_size = Vector2(NAMED, 0)
		named.add_theme_constant_override("separation", 2)
		flow.add_child(named)
		named.add_child(cell)
		UiParts.caption(named, str(r[1]), NAMED, UiTheme.SIZE_SMALL, UiTheme.MUTED_LABEL)
	return flow


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
