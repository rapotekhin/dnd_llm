class_name Portrait
extends IconSlot
## A character's portrait as in BG3 (v0.8.4.43.4): its letter on a ring of its hit points, a blue arc of temporary ones,
## its AC on a shield at the corner, an arrow while a level waits. One drawing for the hotbar's portrait and the left
## column's hero and companions; what it is shows at the cursor as an icon's card (`tip_title`, `tip_body`). No autoload
## names: a playtest's script may compile this first.

var letter := "?"
var hp := 0
var top := 1
var temp := 0
var ac := -1  ## its armour class on a shield at the corner; below 0 — none
var up := false  ## a level waits: an arrow over the ring
var numbers := false  ## «12/12» under the letter (the hotbar's big portrait)


static func of(name_text: String, side: int) -> Portrait:
	var p := Portrait.new()
	p.text = name_text
	p.tooltip_text = name_text
	p.custom_minimum_size = Vector2(side, side)
	p.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	p.focus_mode = Control.FOCUS_NONE
	p.flat = true
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return p


## Its numbers off anybody's sheet: `who` is the hero (`Sheet.HERO`), a follower, a summoned creature or one of the room.
func show_of(s: GameSession, data: Dictionary, who: Dictionary, name_text: String) -> void:
	text = name_text
	letter = name_text.left(1).to_upper() if not name_text.is_empty() else "?"
	hp = Sheet.hp(s, data, who)
	top = maxi(1, Sheet.max_hp(s, data, who))
	temp = int(Sheet.holder(s, who).get("temp_hp", 0))
	ac = Sheet.ac(s, who, data)
	up = Sheet.is_hero(who) and LevelUp.can_level_up(s.character, data)
	tip_title = name_text
	tooltip_text = name_text
	tip_body = hero_tip(s, data) if Sheet.is_hero(who) else _tr("SIDE_HP_AC").format({"hp": hp, "max": top, "ac": ac}) \
		+ ((" · +%d врем." % temp) if temp > 0 else "")
	queue_redraw()


## What the hero's portrait tells at the cursor: race, class and level, HP and AC, the coins, the experience to the next
## level, the festivals near (the author: «монеты, опыт, праздник — при наведении или в листе»).
static func hero_tip(s: GameSession, data: Dictionary) -> String:
	var c := s.character
	var lines: Array[String] = []
	lines.append(_tr("SIDE_HERO_LINE").format({"race": c.get("race_name", ""), "class": c.get("class_name", ""), "level": int(c.get("level", 1)),
		"hp": c.get("hp", 0), "max": c.get("max_hp", 1), "ac": c.get("ac", 10)}) + ((" · +%d врем." % int(c["temp_hp"])) if int(c.get("temp_hp", 0)) > 0 else ""))
	var next_xp := LevelUp.xp_for(data, int(c.get("level", 1)) + 1)
	var xp := _tr("SIDE_HERO_XP").format({"xp": int(c.get("xp", 0)), "next": next_xp}) if int(c.get("level", 1)) < LevelUp.max_level(c, data) else ""
	lines.append(" · ".join([Money.format(Ledger.balance(s)), xp].filter(func(x: String) -> bool: return not x.is_empty())))
	var near := CalendarRules.upcoming(s, data, data["world"])
	if not near.is_empty():  # the nearest festival as the column said it: «★ Бродская ярмарка — через 5 дней», then all near
		var e: Dictionary = near[0]
		var when := _tr("SIDE_FESTIVAL_IN").format({"in": int(e.get("in", 0)), "days": CalendarRules.days_noun(int(e.get("in", 0)))})
		if bool(e["on"]):
			when = _tr("SIDE_FESTIVAL_ON").format({"left": CalendarRules.days_word(int(e["left"]))})
		lines.append("★ %s — %s" % [e["name"], when])
	for e: Dictionary in near:
		lines.append(CalendarRules.line(data["world"], e, true))
	return "\n".join(lines)


static func _tr(key: String) -> String:
	return str(TranslationServer.translate(key))


func _draw() -> void:
	var centre := size / 2
	var rad := minf(size.x, size.y) / 2 - 4
	var share := clampf(float(hp) / maxi(1, top), 0.0, 1.0)
	draw_circle(centre, rad, UiTheme.PANEL_RAISED)
	draw_arc(centre, rad, 0, TAU, 48, UiTheme.BORDER, 3.0)
	draw_arc(centre, rad, -PI / 2, -PI / 2 + TAU * share, 48, UiTheme.hp_color(share), maxf(3.0, rad / 11.0))
	if temp > 0:
		draw_arc(centre, rad - 5, -PI / 2, -PI / 2 + TAU * clampf(float(temp) / maxi(1, top), 0.0, 1.0), 32, UiTheme.TEMP_HP, 2.0)
	var font := get_theme_font("font")
	var big := int(rad * (0.8 if numbers else 0.95))
	draw_string(font, centre + Vector2(-rad, big * 0.36 - (rad * 0.12 if numbers else 0.0)), letter, HORIZONTAL_ALIGNMENT_CENTER, rad * 2, big,
		UiTheme.ACCENT_BRIGHT)
	var w := rad * 0.36  # the shield's half width
	if numbers:  # left of the shield, so a long count is not hidden under it
		draw_string(font, centre + Vector2(-rad - (w * 0.5 if ac >= 0 else 0.0), rad - 14), "%d/%d" % [hp, top], HORIZONTAL_ALIGNMENT_CENTER, rad * 2, 15,
			UiTheme.TEXT)
	if ac >= 0:
		_shield(Vector2(size.x - w, size.y - rad * 0.4), w, font)
	if up:
		var at := Vector2(size.x - rad * 0.3, rad * 0.32)
		var a := rad * 0.22
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -a), at + Vector2(a, 0), at + Vector2(a * 0.4, 0), at + Vector2(a * 0.4, a),
			at + Vector2(-a * 0.4, a), at + Vector2(-a * 0.4, 0), at + Vector2(-a, 0)]), UiTheme.ACCENT_BRIGHT)


## The AC on a small shield, as BG3 draws it beside the portrait.
func _shield(at: Vector2, w: float, font: Font) -> void:
	var pts := PackedVector2Array([at + Vector2(-w, -w), at + Vector2(w, -w), at + Vector2(w, w * 0.2), at + Vector2(0, w * 1.15),
		at + Vector2(-w, w * 0.2)])
	draw_colored_polygon(pts, UiTheme.PANEL)
	pts.append(pts[0])
	draw_polyline(pts, UiTheme.ACCENT, 1.5)
	var fs := clampi(int(w * 1.05), 10, 18)
	draw_string(font, at + Vector2(-w, fs * 0.36), str(ac), HORIZONTAL_ALIGNMENT_CENTER, w * 2, fs, UiTheme.TEXT)
