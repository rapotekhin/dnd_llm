class_name DropTarget
extends PanelContainer
## A place that takes a thing dragged onto it (v0.8.4.43.6, the character window as in BG3): a companion's portrait hands
## it over, the world round the window drops it. The owner says what it takes (`accept`) and what it does (`take`).

var accept := Callable()  ## (drag: Dictionary) -> bool
var take := Callable()  ## (drag: Dictionary)


func _init() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("item") and accept.is_valid() and bool(accept.call(data))


func _drop_data(_at: Vector2, data: Variant) -> void:
	if take.is_valid():
		take.call(data)
