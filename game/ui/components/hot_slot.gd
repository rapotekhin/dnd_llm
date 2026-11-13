class_name HotSlot
extends Control
## One slot of the hotbar's grid (v0.8.4.43, as in BG3): a dark square that holds a cell or nothing, and takes a cell
## dropped on it — from another slot or from the sheet's spells and abilities. `section` and `index` say where it is.

signal dropped(key: String, section: int, index: int)

var section := 0
var index := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	if get_child_count() == 0:  # an empty slot is faint, a filled one is its cell (v0.8.4.43.33: the icons stand out)
		draw_style_box(UiTheme.box(Color(0, 0, 0, 0.18), UiTheme.BORDER.darkened(0.5), 1, 0, 4), Rect2(Vector2.ZERO, size))


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("hotbar")


func _drop_data(_at: Vector2, data: Variant) -> void:
	dropped.emit(str(data["hotbar"]), section, index)
