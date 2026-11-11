class_name ActsMenu
extends PopupMenu
## The one menu of anything (v0.8.4.43.4, as in BG3): a list with lists inside. Built two ways on one road:
## - `of(box)` reads the buttons the side panel built for a ref of the map (`SidePanel.menu`): a person, a creature, a
##   body, a thing, a station, a door, a trap, a foe before a fight, a companion's portrait. The first line is the title,
##   a later one a grey row with the whole text at the cursor, a button an item (grey with why), a group's head
##   «Разговор ▸» a list of its buttons, a red act (attack, finish off) apart under a line. A pick presses the button
##   itself, so the act is the button's own: the hero walks up first, «Точно?» asks before a kill.
## - `list_of(path)` and `add_act` for a menu made of rows: a foe's acts in a fight (a tab, then a spell's circle).
## A list is named «List_<title>».

const LINE := 44  ## a grey row of a long line is cut here; the whole text at the cursor

var _picks: Array[Callable] = []
var _buttons := {}  # an item's id → the button it presses
var _lists := {}  # "/title/title" → its list


func _init() -> void:
	name = "ActsMenu"
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	id_pressed.connect(_pick)


static func of(box: Container) -> ActsMenu:
	var m := ActsMenu.new()
	m._fill([], box, box)
	return m


## The list under `path` (titles from the top, an empty one skipped), made at first need.
func list_of(path: Array) -> PopupMenu:
	var at: PopupMenu = self
	var key := ""
	for t: Variant in path:
		if str(t).is_empty():
			continue
		key += "/" + str(t)
		if not _lists.has(key):
			var sub := PopupMenu.new()
			sub.name = "List_" + str(t)
			sub.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			sub.id_pressed.connect(_pick)
			at.add_child(sub)
			at.add_submenu_node_item(str(t), sub)
			_lists[key] = sub
		at = _lists[key]
	return at


## An item of `list`: grey with `tip` when `disabled`; `on_pick` when it is picked. Its id.
func add_act(list: PopupMenu, text: String, tip: String, disabled: bool, on_pick: Callable) -> int:
	var id := _picks.size()
	list.add_item(text, id)
	var at := list.item_count - 1
	list.set_item_disabled(at, disabled)
	if not tip.is_empty():
		list.set_item_tooltip(at, tip)
	_picks.append(on_pick)
	return id


## The buttons it was read off, in the order of its items.
func buttons() -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	for id: int in _buttons:
		out.append(_buttons[id])
	return out


## The id of the item that presses `b`, -1 — none: a playtest picks it as the player would.
func id_of(b: BaseButton) -> int:
	for id: int in _buttons:
		if _buttons[id] == b:
			return id
	return -1


func _fill(path: Array, node: Node, box: Container) -> void:
	for c: Node in node.get_children():
		if c is CanvasItem and not (c as CanvasItem).visible and not str(c.name).begins_with("Group_"):
			continue
		if c is Label:
			_line(list_of(path), (c as Label).text)
		elif c is BaseButton and str(c.name).begins_with("Fold_"):
			var group := box.find_child("Group_" + str(c.name).trim_prefix("Fold_"), true, false)
			if group != null:
				_fill(path + [(c as Button).text.trim_suffix(" ▸").trim_suffix(" ▾")], group, box)
		elif c is BaseButton:
			_item(list_of(path), c as BaseButton)
		elif not str(c.name).begins_with("Group_"):  # a group is under its head's list
			_fill(path, c, box)


func _line(list: PopupMenu, text: String) -> void:
	var first := text.get_slice("\n", 0)
	if list.item_count == 0 and list == self:
		add_separator(first)
		return
	add_act(list, first if first.length() <= LINE else first.left(LINE - 1) + "…", text, true, Callable())


func _item(list: PopupMenu, b: BaseButton) -> void:
	if b is Button and (b as Button).get_theme_color("font_color") == UiTheme.BAD and list.item_count > 0:
		list.add_separator()  # the red acts apart, last
	var tip := (b as IconSlot).tip_body if b is IconSlot and not (b as IconSlot).tip_body.is_empty() else b.tooltip_text
	var id := add_act(list, (b as Button).text if b is Button else str(b.name), tip, b.disabled, press.bind(b))
	_buttons[id] = b


## Presses `b` as the player's click does: the left button's main act and a pick of the menu alike.
static func press(b: BaseButton) -> void:
	if not is_instance_valid(b) or b.disabled:
		return
	b.button_down.emit()  # the session trace records a click there
	b.pressed.emit()


func _pick(id: int) -> void:
	hide()
	if id >= 0 and id < _picks.size() and _picks[id].is_valid():
		_picks[id].call()
