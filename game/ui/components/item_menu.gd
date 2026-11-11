class_name ItemMenu
## The right button's menu of a thing in any window of things (v0.8.4.43.6, as in BG3): the character window, a chest or a
## body, the trade, a companion's things. Its rows — ItemActs.of, or a window's own (take one, take the stack) in the
## same form {name, label + args | text, why, group?} — are staged as buttons in the window's hidden box, so a playtest
## presses them by name; the player sees them as one list with lists inside (ActsMenu). `act` does a row and reports a
## refusal itself.


## The rows as buttons in `box` under the thing's name; a row with `group` goes into that group's list.
static func stage(box: Control, head: String, rows: Array, act: Callable) -> Control:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	UiParts.label(box, head)
	var groups := {}
	for r: Dictionary in rows:
		var at: Control = box
		var g := str(r.get("group", ""))
		if not g.is_empty():
			if not groups.has(g):
				var fold := Button.new()
				fold.name = "Fold_" + g
				fold.text = TranslationServer.translate(g) + " ▸"
				fold.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
				box.add_child(fold)
				var list := VBoxContainer.new()
				list.name = "Group_" + g
				box.add_child(list)
				groups[g] = list
			at = groups[g]
		var text := str(r["text"]) if r.has("text") else str(TranslationServer.translate(str(r["label"]))).format(r.get("args", {}))
		var why := str(r.get("why", ""))
		if not why.is_empty() and r.has("tool"):  # poured only with its tool: the tool named
			why = "%s: %s" % [TranslationServer.translate(why), BackgroundRules.tool_name(Catalog.data, str(r["tool"]))]
		var row := r
		var b := UiParts.act_button(at, str(r["name"]), text, why, func() -> String:
			act.call(row)
			return "")  # `act` has said why already
		if str(r.get("act", "")) in ["drop", "drop_bag"] and why.is_empty():
			b.tooltip_text = TranslationServer.translate("BTN_DROP_TIP")
	return box


## The list of the staged box at the cursor, owned by `owner`; the old one of the window goes. The new one.
static func show(owner: Control, box: Container, old: ActsMenu) -> ActsMenu:
	if old != null and is_instance_valid(old):
		old.queue_free()
	var m := ActsMenu.of(box)
	owner.add_child(m)
	m.popup(Rect2i(Vector2i(owner.get_viewport().get_mouse_position()), Vector2i.ZERO))
	return m
