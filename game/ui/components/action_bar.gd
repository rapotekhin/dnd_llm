class_name ActionBar
extends PanelContainer
## Under the field (v0.8.1): tabs of acts on the left, the windows on the right. No hotbar and no key numbers: the keys are
## in the tooltips. The side panel fills the pages; in a conversation the tabs give way to the acts with the partner, and
## in the fight of v0.8.4 they become the fight's own.

const PLACE := 0
const EXITS := 1
const DEEDS := 2
const TITLES := ["BAR_PLACE", "SIDE_EXITS", "BAR_DEEDS"]

var windows: HBoxContainer  ## the sheet, the map, the journal, the menu
var talk: HBoxContainer  ## the acts of a conversation
var talk_acts: VBoxContainer

var _tabs: TabBar
var _scrolls: Array[ScrollContainer] = []
var _pages: Array[Container] = []
var _talking := false


func _init() -> void:
	name = "ActionBar"
	theme_type_variation = UiTheme.CARD
	custom_minimum_size = Vector2(0, 182)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_tabs = TabBar.new()
	_tabs.name = "ActionTabs"
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
	for title: String in TITLES:
		_tabs.add_tab(title)
	_tabs.tab_changed.connect(func(_i: int) -> void: _show())
	head.add_child(_tabs)
	windows = HBoxContainer.new()
	windows.name = "Windows"
	windows.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	windows.add_theme_constant_override("separation", 4)
	head.add_child(windows)
	for i: int in TITLES.size():
		var scroll := ScrollContainer.new()
		scroll.name = "ExitsScroll" if i == EXITS else "Page_%d" % i
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(scroll)
		_scrolls.append(scroll)
		var page: Container = _flow() if i == PLACE else VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(page)
		_pages.append(page)
	talk = HBoxContainer.new()
	talk.name = "TalkActs"
	talk.add_theme_constant_override("separation", 8)
	talk.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(talk)
	var acts := ScrollContainer.new()  # as tall as the tabs: the map does not jump when a talk starts
	acts.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	acts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talk.add_child(acts)
	talk_acts = VBoxContainer.new()
	talk_acts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.add_child(talk_acts)
	_show()


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	return f


func page(index: int) -> Container:
	return _pages[index]


func current() -> int:
	return _tabs.current_tab


func select(index: int) -> void:
	_tabs.current_tab = index


func clear() -> void:
	for box: Container in _pages + ([talk_acts] as Array[Container]):
		for c: Node in box.get_children():
			box.remove_child(c)
			c.queue_free()


func set_talk(on: bool) -> void:
	if on != _talking:
		_talking = on
		_show()


## A button of a page is as wide as its text, never cut.
func tidy() -> void:
	for box: Container in _pages + ([talk_acts] as Array[Container]):
		for b: Node in box.find_children("*", "BaseButton", true, false):
			var button := b as BaseButton
			button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			if button is Button:
				(button as Button).clip_text = false
				(button as Button).text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
				(button as Button).autowrap_mode = TextServer.AUTOWRAP_OFF
	var empty := _pages[DEEDS].get_child_count() == 0
	_tabs.set_tab_hidden(DEEDS, empty)
	if empty and _tabs.current_tab == DEEDS:
		_tabs.current_tab = PLACE


func _show() -> void:
	_tabs.visible = not _talking
	talk.visible = _talking
	for i: int in _scrolls.size():
		_scrolls[i].visible = not _talking and i == _tabs.current_tab
