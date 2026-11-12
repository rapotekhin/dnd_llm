class_name UiTheme
extends RefCounted
## «Dark book» theme (docs/design/art-style.md): warm dark paper, light serif text for the master,
## sans for the interface, old-gold accent. The theme itself is `ui/theme/game_theme.tres`, the project's theme, edited in
## the editor (v0.7.51); here are the names of its variations and the colours of what is still built in code.

const BG := Color("#17130f")
const PANEL := Color("#211b16")
const PANEL_RAISED := Color("#2b231c")
const BORDER := Color("#4a3d2f")
const TEXT := Color("#e8dcc6")
const MUTED := Color("#9a8f7e")
const TEMP_HP := Color("#6f9fc8")  # temporary hit points: a blue piece beside the HP bar
const ACCENT := Color("#c9a45c")
const ACCENT_BRIGHT := Color("#e6c47e")
const OK := Color("#8fb36f")
const BAD := Color("#c8705f")
const TILES := {  ## squares of a map, plain until the sprites (v0.8.0)
	"#": Color("#5e4d3a"), ".": Color("#3b3027"), "=": Color("#7f7a6c"), ",": Color("#6b5838"), "+": Color("#8a6a3c"), "%": Color("#33301c"), "^": Color("#6a2f22"),
	"~": Color("#2c4a5c"), "o": Color("#0d0b09"), "T": Color("#27402a"), "B": Color("#5a4c3c"), "w": Color("#7d98a3"),
}
const WARN := Color("#d1a14a")

const FONT_UI := "res://assets/fonts/inter.ttf"
const FONT_SERIF := "res://assets/fonts/literata.ttf"
const FONT_SERIF_ITALIC := "res://assets/fonts/literata_italic.ttf"

const SIZE_UI := 22
const SIZE_SMALL := 18
const SIZE_BODY := 26
const SIZE_TITLE := 72
const SIZE_HEADING := 36

## Type variations.
const DM_TEXT := "DmText"  # Label: the master's narration
const PLAYER_TEXT := "PlayerText"  # Label: the player's lines
const NPC_TEXT := "NpcText"  # Label: an NPC's line in conversation
const ENGINE_TEXT := "EngineText"  # Label: the engine's own line in the chat — quiet: small, muted, under a rule (v0.8.4.43.5.1)
const MUTED_LABEL := "MutedLabel"
const TITLE := "TitleLabel"
const HEADING := "HeadingLabel"
const CARD := "CardPanel"  # PanelContainer: check cards
const SIDE := "SidePanel"  # PanelContainer: side panel / dialogs
const ACCENT_BUTTON := "AccentButton"
const DANGER_BUTTON := "DangerButton"  # an irreversible act
const ACCENT_LABEL := "AccentLabel"
const BRIGHT_LABEL := "BrightLabel"
const WARN_LABEL := "WarnLabel"
const BAD_LABEL := "BadLabel"
const OK_LABEL := "OkLabel"
const SMALL_LABEL := "SmallLabel"
const CAPTION_LABEL := "CaptionLabel"  # a small accent caption over a list
## Suffix of the RichTextLabel twins of the chat variations: DmText + Rich (v0.6.6).
const RICH := "Rich"
## Colours of the chat markup: names of people and places, direct speech.
const NAME_COLOR := Color("#e6c47e")
const SPEECH_COLOR := Color("#cfd8b8")


## A spell's button framed in the colour of its school ("" — no frame): `schools` of data/icons.json, the same colour as
## the spell's icon (v0.7.22.21, #20; one place since v0.8.4.43).
static func school_frame(b: Button, school_id: String) -> void:
	var hex := IconRules.school_color((Engine.get_main_loop() as SceneTree).root.get_node("Catalog").data, school_id)  # no autoload name: a playtest's script compiles this before the autoloads
	if hex.is_empty():
		return
	var c := Color(hex)
	b.add_theme_stylebox_override("normal", box(PANEL_RAISED, c.darkened(0.15), 2, 10, 4))
	b.add_theme_stylebox_override("hover", box(PANEL_RAISED.lightened(0.08), c, 2, 10, 4))


## The drawn frames of `frames` (data/icons.json) laid over the theme as StyleBoxTexture, each with the content margins
## of the flat style it replaces, so no layout moves; a file not drawn leaves its flat style — the art is not kept in
## git (v0.8.4.43.23). Called once at the start, before any screen. The number of styles laid.
static func skin(theme: Theme, frames: Dictionary) -> int:
	var laid := 0
	for slot: String in frames.get("slots", {}):
		var file := str(frames["slots"][slot])
		var tex := frame(frames, file)
		if tex == null:
			continue
		var type := slot.get_slice("/", 0)
		var style := slot.get_slice("/", 1)
		theme.set_stylebox(style, type, frame_box(tex, _part_of(frames, file), _style_of(theme, style, type)))
		laid += 1
	return laid


## A drawn file of `frames` by its name; null when it is not drawn.
static func frame(frames: Dictionary, file: String) -> Texture2D:
	var path := str(frames.get("root", "")) + file + ".png"
	return load(path) if not frames.is_empty() and ResourceLoader.exists(path) else null


## A drawn frame as a style: its corners as drawn (the part's `cut` at its `scale`), the edges and the middle stretched,
## the content's margins as `like` has them and the part's `pad` [across, down] more — how far its drawn line stands
## inside the edge, so the text keeps the gap it had from the flat border.
static func frame_box(tex: Texture2D, part: Dictionary, like: StyleBox) -> StyleBoxTexture:
	var b := StyleBoxTexture.new()
	b.texture = tex
	b.set_texture_margin_all(roundf(float(part.get("cut", 0)) * float(part.get("scale", 1.0))))
	var pad: Variant = part.get("pad", 0)
	var across := float(pad[0]) if pad is Array else float(pad)
	var down := float(pad[1]) if pad is Array else float(pad)
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		var was := maxf(0.0, like.get_content_margin(side)) if like != null else 0.0
		var more := across if side == SIDE_LEFT or side == SIDE_RIGHT else down
		if like != null or more > 0.0:
			b.set_content_margin(side, was + more)
	return b


static var _ornaments := {}  # a file of `frames` → its texture or null, read once
static var _cell: StyleBox = null


## A drawn file of the game's own `frames` (Catalog), null when it is not drawn: an ornament laid by code.
static func ornament(file: String) -> Texture2D:
	if not _ornaments.has(file):
		_ornaments[file] = frame(_frames(), file)
	return _ornaments[file]


## The cell's drawn frame for a square of the hotbar and the inventory (IconSlot), null when it is not drawn.
static func cell_box() -> StyleBox:
	if _cell == null and ornament("cell") != null:
		_cell = frame_box(ornament("cell"), _part_of(_frames(), "cell"), null)
	return _cell


## The crest over a window's top edge, in its middle, half above it (the author's pick of the lines style), on the
## panel's own drawing; a window narrower than the crest takes it smaller.
static func crest(panel: Control) -> void:
	var tex := ornament("crest")
	if tex == null:
		return
	panel.draw.connect(func() -> void:
		var w := minf(tex.get_width(), panel.size.x * 0.5)
		var h := tex.get_height() * w / tex.get_width()
		panel.draw_texture_rect(tex, Rect2(Vector2((panel.size.x - w) / 2, -h / 2), Vector2(w, h)), false))
	panel.queue_redraw()


## A node as it enters the tree: an HSeparator gets the divider's mark in its middle over the stretched line the theme
## draws (StyleBoxTexture cannot keep a mark unstretched). Connected to SceneTree.node_added by main.gd.
static func adorn(node: Node) -> void:
	var tex := ornament("divider_mark") if node is HSeparator else null
	if tex == null:
		return
	var sep := node as HSeparator
	sep.draw.connect(func() -> void:
		var at := (sep.size - tex.get_size()) / 2
		sep.draw_texture(tex, at.floor()))


static func _frames() -> Dictionary:
	var root := (Engine.get_main_loop() as SceneTree).root
	return root.get_node("Catalog").data.get("icons", {}).get("frames", {}) if root.has_node("Catalog") else {}


static func _part_of(frames: Dictionary, file: String) -> Dictionary:
	return frames.get("parts", {}).get(str(frames.get("files", {}).get(file, {}).get("part", "")), {})


## A style of the theme by its type or the type its variation stands on (AccentButton → Button).
static func _style_of(theme: Theme, style: String, type: String) -> StyleBox:
	var t := StringName(type)
	while t != &"":
		if theme.has_stylebox(style, t):
			return theme.get_stylebox(style, t)
		t = theme.get_type_variation_base(t)
	return null


## The colour of what is left of HP: green over a half, yellow over a quarter, red below.
static func hp_color(share: float) -> Color:
	return OK if share > 0.5 else WARN if share > 0.25 else BAD


static func box(bg: Color, border: Color, border_width: int, margin: int, radius: int = 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(border_width)
	b.set_content_margin_all(margin)
	b.set_corner_radius_all(radius)
	return b


static var _fonts: Dictionary[String, Font] = {}


## A variable font at a given weight (Literata and Inter ship as variable TTFs).
static func font(path: String, weight: int) -> Font:
	var key := "%s@%d" % [path, weight]
	if not _fonts.has(key):
		var v := FontVariation.new()
		v.base_font = load(path)
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[key] = v
	return _fonts[key]
