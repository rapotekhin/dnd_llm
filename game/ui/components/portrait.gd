class_name Portrait
extends IconSlot
## A character's portrait as in BG3 (v0.8.4.43.4): its face (v0.8.4.43.5.2, PortraitRules; no picture — its letter) in a ring
## of its hit points, a blue arc of temporary ones, its AC on a shield at the corner, an arrow while a level waits. One
## drawing for the hotbar's portrait and the left column's hero and companions; what it is shows at the cursor as an
## icon's card (`tip_title`, `tip_body`). `face` draws a face in a circle anywhere: the map's tokens, the fight's bodies.
## No autoload names: a playtest's script may compile this first.

## Where the drawn ring's lines stand, a share of the portrait's half side (measured on assets/ui/frames/ring.png): the
## face inside the inner line, the HP along the channel between the inner line and the outer one.
const RING_INNER := 0.833
const RING_CHANNEL := 0.865
const RING_WIDTH := 0.045

var letter := "?"
var hp := 0
var top := 1
var temp := 0
var ac := -1  ## its armour class on a shield at the corner; below 0 — none
var up := false  ## a level waits: an arrow over the ring
var numbers := false  ## «12/12» under the letter (the hotbar's big portrait)
var picture := ""  ## the face's res:// path (PortraitRules.of); "" — the letter
var picked := false  ## a bright rim: the one chosen (the creation screen's faces), whose turn it is in a fight
var down := false  ## at 0 HP or out of the fight: the face greyed (v0.8.4.43.10)
var saves := {}  ## its death saves while it lies dying: {ok, fail} as three green and three red dots, as in BG3


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
	picture = PortraitRules.of(s, data, who)
	var fighting := CombatRules.active(s) and who.has("side")
	down = hp <= 0 or (fighting and not Sheet.is_hero(who) and str(who.get("status", "active")) != "active")
	saves = CombatRules.saves_of(s, who) if fighting and CombatRules.dying(s, who) else {}
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
	var tint := Color(0.42, 0.42, 0.42) if down else Color.WHITE
	var temp_share := clampf(float(temp) / maxi(1, top), 0.0, 1.0)
	var ring := UiTheme.ornament("ring")
	var drawn := false
	if ring != null:  # the drawn ring (v0.8.4.43.23): the face inside its inner line, the HP in the channel between its lines
		var half := minf(size.x, size.y) / 2
		var inner := half * RING_INNER
		draw_circle(centre, inner, UiTheme.PANEL_RAISED)
		drawn = face(self, picture, centre, inner, tint)
		var width := maxf(2.0, half * RING_WIDTH)
		draw_arc(centre, half * RING_CHANNEL, 0, TAU, 48, UiTheme.BG, width)
		draw_arc(centre, half * RING_CHANNEL, -PI / 2, -PI / 2 + TAU * share, 48, UiTheme.hp_color(share), width)
		draw_texture_rect(ring, Rect2(centre - Vector2(half, half), Vector2(half, half) * 2), false)
		if picked:
			draw_arc(centre, half - 1.5, 0, TAU, 48, UiTheme.ACCENT_BRIGHT, 2.5)
		if temp > 0:
			draw_arc(centre, inner - 2.5, -PI / 2, -PI / 2 + TAU * temp_share, 32, UiTheme.TEMP_HP, 2.0)
	else:
		draw_circle(centre, rad, UiTheme.PANEL_RAISED)
		drawn = face(self, picture, centre, rad - 1.5, tint)
		if picked:
			draw_arc(centre, rad + 2.5, 0, TAU, 48, UiTheme.ACCENT_BRIGHT, 3.0)
		draw_arc(centre, rad, 0, TAU, 48, UiTheme.BORDER, 3.0)
		draw_arc(centre, rad, -PI / 2, -PI / 2 + TAU * share, 48, UiTheme.hp_color(share), maxf(3.0, rad / 11.0))
		if temp > 0:
			draw_arc(centre, rad - 5, -PI / 2, -PI / 2 + TAU * temp_share, 32, UiTheme.TEMP_HP, 2.0)
	var font := get_theme_font("font")
	var big := int(rad * (0.8 if numbers else 0.95))
	if not drawn:
		draw_string(font, centre + Vector2(-rad, big * 0.36 - (rad * 0.12 if numbers else 0.0)), letter, HORIZONTAL_ALIGNMENT_CENTER, rad * 2, big,
			UiTheme.ACCENT_BRIGHT)
	var w := rad * 0.36  # the shield's half width
	if numbers:  # left of the shield, so a long count is not hidden under it
		var at := centre + Vector2(-rad - (w * 0.5 if ac >= 0 else 0.0), rad - 14)
		draw_string_outline(font, at, "%d/%d" % [hp, top], HORIZONTAL_ALIGNMENT_CENTER, rad * 2, 15, 4, UiTheme.BG)  # readable over a face
		draw_string(font, at, "%d/%d" % [hp, top], HORIZONTAL_ALIGNMENT_CENTER, rad * 2, 15, UiTheme.TEXT)
	if ac >= 0:
		_shield(Vector2(size.x - w, size.y - rad * 0.4), w, font)
	if not saves.is_empty():
		_saves(centre, rad)
	if up:
		var at: Vector2 = _arrow()[0]
		var a := rad * 0.22
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -a), at + Vector2(a, 0), at + Vector2(a * 0.4, 0), at + Vector2(a * 0.4, a),
			at + Vector2(-a * 0.4, a), at + Vector2(-a * 0.4, 0), at + Vector2(-a, 0)]), UiTheme.ACCENT_BRIGHT)


## Where the arrow of a waiting level stands, its centre and reach.
func _arrow() -> Array:
	var rad := minf(size.x, size.y) / 2 - 4
	return [Vector2(size.x - rad * 0.3, rad * 0.32), rad * 0.42]


## A click on the arrow of a waiting level opens the level-up (the author, 2026-11-13: «щелчок на стрелочку "повышения
## уровня" так же должен вести на панель повышения уровня»); anywhere else the portrait's own act.
func _gui_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if up and mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var arrow := _arrow()
		if mb.position.distance_to(arrow[0]) <= float(arrow[1]):
			accept_event()
			(Engine.get_main_loop() as SceneTree).root.get_node("EventBus").level_up_requested.emit()
			return
	super(ev)


## A face of `path` cut to a circle of `rad` at `centre` on any canvas item (a portrait, a token of the map, a body of a
## fight), dimmed by `tint`; false — no picture, the caller draws its letter.
static func face(ci: CanvasItem, path: String, centre: Vector2, rad: float, tint := Color.WHITE) -> bool:
	var tex := IconSlot.texture(path)
	if tex == null or rad <= 0.0:
		return false
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 40:
		var d := Vector2.from_angle(TAU * i / 40.0)
		pts.append(centre + d * rad)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	ci.draw_colored_polygon(pts, tint, uvs, tex)
	return true


## A face of `path` as a square picture for a box (the fight's queue, the creature's card); null — no picture.
static func square(path: String, side: float, dim := false) -> TextureRect:
	var tex := IconSlot.texture(path)
	if tex == null:
		return null
	var pic := TextureRect.new()
	pic.name = "Face"
	pic.texture = tex
	pic.custom_minimum_size = Vector2(side, side)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.modulate = Color(0.5, 0.5, 0.5) if dim else Color.WHITE
	return pic


## The death saves over the bottom of the face: three for successes on the left, three for failures on the right.
func _saves(centre: Vector2, rad: float) -> void:
	var r := maxf(3.0, rad * 0.09)
	var y := centre.y + rad * 0.55
	for i in 3:
		for side: int in [-1, 1]:
			var ok := side < 0
			var lit := i < int(saves.get("ok" if ok else "fail", 0))
			var at := Vector2(centre.x + side * (r * 1.6 + i * r * 2.6), y)
			var col := UiTheme.OK if ok else UiTheme.BAD
			draw_circle(at, r, col if lit else UiTheme.BG)
			draw_arc(at, r, 0, TAU, 16, col, 1.5)


## The AC on a small shield, as BG3 draws it beside the portrait.
func _shield(at: Vector2, w: float, font: Font) -> void:
	var pts := PackedVector2Array([at + Vector2(-w, -w), at + Vector2(w, -w), at + Vector2(w, w * 0.2), at + Vector2(0, w * 1.15),
		at + Vector2(-w, w * 0.2)])
	draw_colored_polygon(pts, UiTheme.PANEL)
	pts.append(pts[0])
	draw_polyline(pts, UiTheme.ACCENT, 1.5)
	var fs := clampi(int(w * 1.05), 10, 18)
	draw_string(font, at + Vector2(-w, fs * 0.36), str(ac), HORIZONTAL_ALIGNMENT_CENTER, w * 2, fs, UiTheme.TEXT)
