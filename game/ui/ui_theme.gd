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
const NPC_TEXT := "NpcText"  # Label: an NPC's line in conversation
const EFFECT_TEXT := "EffectText"  # Label: applied effects of a turn
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
## Suffix of the RichTextLabel twins of the chat variations: DmText + Rich (v0.6.6).
const RICH := "Rich"
## Colours of the chat markup: names of people and places, direct speech.
const NAME_COLOR := Color("#e6c47e")
const SPEECH_COLOR := Color("#cfd8b8")


## The frame colour of a spell by its school (v0.7.22.21, #20): the eight schools of 5e, muted to the «dark book».
const SCHOOL_COLORS := {
	"abjuration": Color("#6f9fc0"), "conjuration": Color("#c99a4a"), "divination": Color("#b9b0d8"),
	"enchantment": Color("#c77fa8"), "evocation": Color("#d0704f"), "illusion": Color("#8a7fc8"),
	"necromancy": Color("#7fa07a"), "transmutation": Color("#c8b45a"),
}


## A spell's button framed in the colour of its school ("" — no frame).
static func school_frame(b: Button, school_id: String) -> void:
	if not SCHOOL_COLORS.has(school_id):
		return
	var c: Color = SCHOOL_COLORS[school_id]
	b.add_theme_stylebox_override("normal", box(PANEL_RAISED, c.darkened(0.15), 2, 10, 4))
	b.add_theme_stylebox_override("hover", box(PANEL_RAISED.lightened(0.08), c, 2, 10, 4))


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
