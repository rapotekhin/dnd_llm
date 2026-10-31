class_name DeathScreen
extends Control
## The hero died in a fight (roadmap v0.6.1): the master's epitaph and the hero's path; load the autosave made
## before the fight or go to the menu. «Одна жизнь» (no loading) — M5.

const SCENE := "res://ui/screens/death_screen.tscn"

var epitaph: String


static func make(text: String) -> DeathScreen:
	var screen := UiScenes.open(SCENE) as DeathScreen
	screen.epitaph = text
	return screen


func required() -> Dictionary:
	return {"%Who": "Label", "%Epitaph": "Label", "%PathLabel": "Label", "%LoadBeforeFight": "Button", "%HeirButton": "Button",
		"%ToMenu": "Button"}


func _ready() -> void:
	var s := GameState.session if GameState.has_session() else null
	var who: Label = UiScenes.need(self, "%Who")
	var path: Label = UiScenes.need(self, "%PathLabel")
	who.visible = s != null
	path.visible = s != null
	(UiScenes.need(self, "%Epitaph") as Label).text = epitaph
	var heir_id := ""
	if s != null:
		var c := s.character
		who.text = tr("DEATH_WHO").format({"name": c["name"], "race": c.get("race_name", ""), "class": c.get("class_name", ""), "level": int(c.get("level", 1))})
		path.text = tr("DEATH_PATH").format({"days": s.day, "quests": s.quests_done.size(), "xp": int(s.character.get("xp", 0))})
		heir_id = FamilyRules.heir(s, Catalog.data)
	var load_btn: Button = UiScenes.need(self, "%LoadBeforeFight")
	load_btn.disabled = not SaveManager.has_slot(GameState.COMBAT_SAVE)
	load_btn.pressed.connect(func() -> void:
		var err := GameState.load_from(GameState.COMBAT_SAVE)
		if not err.is_empty():
			EventBus.message.emit(tr(err)))
	var heir: Button = UiScenes.need(self, "%HeirButton")
	heir.visible = not heir_id.is_empty()  # v0.7.32: the family goes on
	if heir.visible:
		heir.text = tr("BTN_PLAY_HEIR").format({"name": BondRules.npc_name(s, Catalog.data, heir_id)})
		heir.pressed.connect(func() -> void:
			EventBus.navigate.emit("creation", {"settings": s.settings, "heir": FamilyRules.heir_choices(s, Catalog.data)}))
	(UiScenes.need(self, "%ToMenu") as Button).pressed.connect(GameState.close_session)
