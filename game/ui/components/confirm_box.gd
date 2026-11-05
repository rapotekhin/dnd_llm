class_name ConfirmBox
extends ModalFrame
## «Точно?» before an irreversible act (v0.7.22.27, UI audit С3; the first window inheriting the frame's scene, v0.7.51):
## attacking a person, finishing off, surrendering, resisting the guard. «Больше не показывать» (off by default) turns
## the questions off; the settings bring them back (SaveManager.confirm_risky). «✕» and Esc are «no».

signal answered(yes: bool)

const SCENE := "res://ui/components/confirm_box.tscn"

var never: CheckBox
var yes: Button
var _no: Button


## Runs `go` at once when the questions are off (null), else after «yes» in the box it returns.
static func ask(host: Node, title_text: String, body_text: String, yes_label: String, go: Callable) -> ConfirmBox:
	if not SaveManager.confirm_risky:
		go.call()
		return null
	var box := UiScenes.open(SCENE) as ConfirmBox
	box.setup(title_text, 640.0)
	box.fill(body_text, yes_label)
	box.answered.connect(func(ok: bool) -> void:
		if ok:
			go.call())
	host.get_window().add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return box


## Quests taken by `take` (Callable() -> String, a refusal key): a near-impossible one among them asks first (v0.7.39.6;
## v0.8.4.29.6: one question for the giver's button, the board's order and «Взять все»). The refusal now, or "" — a later
## one goes to the message line.
static func take_quests(host: Node, qids: Array, take: Callable) -> String:
	var world: Dictionary = Catalog.data["world"]
	var deadly := qids.filter(func(qid: Variant) -> bool: return QuestGen.warns(Catalog.data, QuestRules.quest(world, str(qid))))
	if deadly.is_empty():
		return str(take.call())
	ask(host, TranslationServer.translate("CONFIRM_QUEST_DEADLY_TITLE").format({"title": QuestRules.quest(world, str(deadly[0]))["title"]}),
		TranslationServer.translate("CONFIRM_QUEST_DEADLY"), TranslationServer.translate("BTN_QUEST_TAKE_DEADLY"), func() -> void:
			var err := str(take.call())
			if not err.is_empty():
				EventBus.message.emit(TranslationServer.translate(err)))
	return ""


func required() -> Dictionary:
	var nodes := super()
	nodes.merge({"%ConfirmText": "Label", "%NeverAsk": "CheckBox", "%ConfirmNo": "Button", "%ConfirmYes": "Button"})
	return nodes


## The texts are the game's own, already translated, with names in them.
func fill(body_text: String, yes_label: String) -> void:
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var text: Label = UiScenes.need(self, "%ConfirmText")
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text.text = body_text
	never = UiScenes.need(self, "%NeverAsk")
	_no = UiScenes.need(self, "%ConfirmNo")
	_no.pressed.connect(_answer.bind(false))
	yes = UiScenes.need(self, "%ConfirmYes")
	yes.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	yes.text = yes_label
	yes.pressed.connect(_answer.bind(true))
	close_requested.connect(_answer.bind(false))


func _ready() -> void:
	_no.grab_focus.call_deferred()  # Enter must not do the irreversible thing by accident


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		_answer(false)
		get_viewport().set_input_as_handled()


func _answer(ok: bool) -> void:
	if ok and never.button_pressed:  # «больше не показывать» counts only with «yes»
		SaveManager.confirm_risky = false
		SaveManager.save_settings()
	answered.emit(ok)
	queue_free()
