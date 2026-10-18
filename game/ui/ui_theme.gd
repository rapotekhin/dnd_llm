class_name UiTheme
extends RefCounted
## «Dark book» theme (docs/design/art-style.md): warm dark paper, light serif text for the master,
## sans for the interface, old-gold accent. Every color and font of the UI comes from here.

const BG := Color("#17130f")
const PANEL := Color("#211b16")
const PANEL_RAISED := Color("#2b231c")
const BORDER := Color("#4a3d2f")
const TEXT := Color("#e8dcc6")
const MUTED := Color("#9a8f7e")
const ACCENT := Color("#c9a45c")
const ACCENT_BRIGHT := Color("#e6c47e")
const OK := Color("#8fb36f")
const BAD := Color("#c8705f")
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
const SYSTEM_TEXT := "SystemText"  # Label: engine notices
const MUTED_LABEL := "MutedLabel"
const TITLE := "TitleLabel"
const HEADING := "HeadingLabel"
const CARD := "CardPanel"  # PanelContainer: check cards
const SIDE := "SidePanel"  # PanelContainer: side panel / dialogs
const ACCENT_BUTTON := "AccentButton"


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font(FONT_UI, 450)
	t.default_font_size = SIZE_UI

	t.set_stylebox("panel", "Panel", box(BG, Color.TRANSPARENT, 0, 0))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 1, 16))
	t.set_type_variation(SIDE, "PanelContainer")
	t.set_stylebox("panel", SIDE, box(PANEL, BORDER, 1, 24))
	t.set_type_variation(CARD, "PanelContainer")
	t.set_stylebox("panel", CARD, box(PANEL_RAISED, BORDER, 1, 12, 6))

	t.set_color("font_color", "Label", TEXT)
	for v: Array in [
		[DM_TEXT, font(FONT_SERIF, 400), SIZE_BODY, TEXT],
		[PLAYER_TEXT, font(FONT_SERIF_ITALIC, 400), SIZE_BODY, ACCENT],
		[SYSTEM_TEXT, font(FONT_UI, 400), SIZE_SMALL, MUTED],
		[MUTED_LABEL, font(FONT_UI, 400), SIZE_SMALL, MUTED],
		[TITLE, font(FONT_SERIF, 600), SIZE_TITLE, ACCENT_BRIGHT],
		[HEADING, font(FONT_SERIF, 600), SIZE_HEADING, ACCENT],
	]:
		t.set_type_variation(v[0], "Label")
		t.set_font("font", v[0], v[1])
		t.set_font_size("font_size", v[0], v[2])
		t.set_color("font_color", v[0], v[3])
	t.set_constant("line_spacing", DM_TEXT, 6)

	for type: String in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, box(PANEL_RAISED, BORDER, 1, 10, 4))
		t.set_stylebox("hover", type, box(PANEL_RAISED.lightened(0.08), ACCENT, 1, 10, 4))
		t.set_stylebox("pressed", type, box(PANEL_RAISED.darkened(0.2), ACCENT, 1, 10, 4))
		t.set_stylebox("hover_pressed", type, box(PANEL_RAISED.darkened(0.2), ACCENT, 1, 10, 4))
		t.set_stylebox("disabled", type, box(PANEL, PANEL_RAISED, 1, 10, 4))
		t.set_stylebox("focus", type, box(Color.TRANSPARENT, ACCENT.darkened(0.3), 1, 10, 4))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, ACCENT_BRIGHT)
		t.set_color("font_pressed_color", type, ACCENT)
		t.set_color("font_disabled_color", type, MUTED.darkened(0.3))
	t.set_type_variation(ACCENT_BUTTON, "Button")
	t.set_stylebox("normal", ACCENT_BUTTON, box(ACCENT.darkened(0.55), ACCENT, 1, 10, 4))
	t.set_font("font", ACCENT_BUTTON, font(FONT_UI, 600))

	for type: String in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, box(BG, BORDER, 1, 12, 4))
		t.set_stylebox("focus", type, box(BG, ACCENT, 1, 12, 4))
		t.set_stylebox("read_only", type, box(PANEL, BORDER, 1, 12, 4))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_placeholder_color", type, MUTED.darkened(0.2))
		t.set_color("caret_color", type, ACCENT)
		t.set_color("selection_color", type, ACCENT.darkened(0.5))

	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", ACCENT_BRIGHT)
	t.set_stylebox("panel", "TabContainer", box(PANEL, BORDER, 1, 20))
	t.set_stylebox("tab_selected", "TabContainer", box(PANEL, ACCENT, 1, 12, 4))
	t.set_stylebox("tab_unselected", "TabContainer", box(BG, BORDER, 1, 12, 4))
	t.set_stylebox("tab_hovered", "TabContainer", box(PANEL_RAISED, ACCENT, 1, 12, 4))
	t.set_color("font_selected_color", "TabContainer", ACCENT_BRIGHT)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_stylebox("panel", "PopupMenu", box(PANEL_RAISED, BORDER, 1, 8))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", ACCENT_BRIGHT)
	t.set_stylebox("hover", "PopupMenu", box(ACCENT.darkened(0.6), Color.TRANSPARENT, 0, 4))
	t.set_stylebox("panel", "TooltipPanel", box(PANEL_RAISED, BORDER, 1, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


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
