class_name PartyColumn
extends VBoxContainer
## The hero and its party as portraits, as in BG3 — one column in a fight and out of it (v0.8.4.43.4; the same in a fight
## since v0.8.4.43.10, the author: «в бою эта панель должна быть идентична вне боевой … только союзников»). Who is in it is
## `AllyRules.party`: the hero, its followers, its beasts, the summoned — in a fight their fighters, never a foe nor an ally
## of the encounter. Each is a portrait (its ring of HP, its AC, a level waiting, its death saves), its name, a bar of HP,
## its statuses and what the fight lays on it as icons; the needs under the hero. The column only draws and tells: a click,
## the right button and the mouse over a portrait go out as `clicked`, `context` and `pointed` with the member's ref; the
## side panel answers them out of a fight, FightUi in it. `dress` (Callable(Portrait, ref)) lays the moment's look on a
## portrait: a target of the picked act.

signal clicked(ref: String)
signal context(ref: String)
signal pointed(ref: String)  ## "-" — the mouse left it

const HERO_SIDE := 96
const SIDE := 60
const HERO_ICON := 42  ## the hero's needs and statuses (v0.8.4.43.10, the author: «иконки … маленькие и неудобные»)
const ICON := 34
## What the fight lays on one (CombatRules.marks) → [icon, title, what it does].
const MARKS := {"hidden": ["acts/hide", "COMBAT_HIDDEN_MARK", "COMBAT_HIDDEN"], "surprised": ["conditions/surprised", "COMBAT_SURPRISED", "COMBAT_SURPRISED_TIP"],
	"raging": ["features/rage", "COMBAT_RAGING", "COMBAT_RAGING_TIP"], "reckless": ["features/reckless_attack", "COMBAT_RECKLESS_MARK", "COMBAT_RECKLESS"],
	"dodging": ["acts/dodge", "COMBAT_DODGING", "COMBAT_DODGING_TIP"], "shape": ["features/wild_shape", "COMBAT_SHAPE_MARK", ""]}

var now := ""  ## the ref of the one whose turn it is: its portrait lit (a fight)


func _init() -> void:
	name = "Party"
	add_theme_constant_override("separation", 8)


## Draws the party again; `dress` styles each portrait (Callable(Portrait, ref)).
func refresh(dress: Callable = Callable()) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if not GameState.has_session():
		return
	var s := GameState.session
	for m: Dictionary in AllyRules.party(s, Catalog.data):
		_member(s, m, dress)


## One of the party: its portrait, its name, a bar of HP, the hero's needs, its statuses and marks as icons.
func _member(s: GameSession, m: Dictionary, dress: Callable) -> void:
	var data := Catalog.data
	var who: Dictionary = m["who"]
	var ref := str(m["ref"])
	var hero := Sheet.is_hero(who)
	var key := "hero" if hero else ref.get_slice(":", ref.get_slice_count(":") - 1)
	var title := str(m["name"])
	var row := HBoxContainer.new()
	row.name = "Member_" + key
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var p := Portrait.of(title, HERO_SIDE if hero else SIDE)
	p.name = "Portrait_" + key
	p.show_of(s, data, who, title)
	p.picked = not now.is_empty() and now == ref
	row.add_child(p)
	if (CombatRules.marks(s, who) as Array).has("hidden"):
		CombatFx.look(p, "hidden")
	if dress.is_valid():
		dress.call(p, ref)
	p.mouse_entered.connect(pointed.emit.bind(ref))
	p.mouse_exited.connect(pointed.emit.bind("-"))
	p.pressed.connect(clicked.emit.bind(ref))
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			p.accept_event()
			context.emit(ref))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	var name_l := UiParts.label(info, title, UiTheme.HEADING if hero else "")
	name_l.name = "Name_" + key
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.clip_text = true
	var bar := UiParts.hp_line(p.hp, p.top, p.temp, 10.0 if hero else 7.0, 2)  # temporary hits in blue (v0.8.4.30)
	bar.name = "HeroBar" if hero else "Bar_" + key
	info.add_child(bar)
	if hero and NeedRules.on(s):
		_needs(s, info)
	var chips := EffectChips.new()  # what is on it (v0.8.1), icons since v0.8.4.43.4
	chips.icons = HERO_ICON if hero else ICON
	chips.who = {} if hero else who
	if not hero:
		chips.name = "EffectChips_" + key
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	info.add_child(chips)
	chips.refresh()
	_marks(s, chips, who)


## What the fight lays on it beside its statuses (CombatRules.marks) as icons of the same row.
func _marks(s: GameSession, chips: EffectChips, who: Dictionary) -> void:
	for k: String in CombatRules.marks(s, who):
		var spec: Array = MARKS[k]
		var title := tr(str(spec[1]))
		var body := tr(str(spec[2])) if not str(spec[2]).is_empty() else ""
		if k == "shape":
			var b := Guise.body(Sheet.holder(s, who))
			title = tr("COMBAT_WILD_SHAPE_LINE").format({"beast": Catalog.data["monsters"].get(str(b["monster"]), {}).get("name", ""),
				"hp": int(b.get("hp", 0)), "max": int(b.get("max_hp", 0))})
		var cell := IconSlot.make(str(spec[0]), title, chips.icons)
		cell.name = "Mark_" + k
		cell.tip_title = title
		cell.tip_body = body
		cell.focus_mode = Control.FOCUS_NONE
		chips.add_child(cell)
		chips.visible = true


## Food, water, sleep as icons with their fill under the hero (v0.7.23; icons since v0.8.4.43.4, larger since v0.8.4.43.10).
func _needs(s: GameSession, info: VBoxContainer) -> void:
	var data := Catalog.data
	var row := HBoxContainer.new()
	row.name = "Needs"
	row.add_theme_constant_override("separation", 6)
	info.add_child(row)
	for need: String in NeedRules.KINDS:
		var v := NeedRules.value(s, data, need)
		var st := NeedRules.stage(s, data, need)
		var title := str(NeedRules.cfg(data)[need]["name"])
		var cell := IconSlot.make("ui/" + need, "%s %d/100" % [title, roundi(v)], HERO_ICON)
		cell.name = "Need_" + need
		cell.tip_title = title
		cell.tooltip_text = "%d/100%s" % [roundi(v), (" — " + str(st["chip"])) if not st.is_empty() else ""]
		cell.tip_body = str(st.get("line", ""))
		cell.focus_mode = Control.FOCUS_NONE
		cell.meter = v / 100.0
		cell.meter_color = UiTheme.hp_color(v / 100.0)  # what is left, on the scale of a bar of HP
		if not st.is_empty():
			cell.badge = "!"
		row.add_child(cell)
