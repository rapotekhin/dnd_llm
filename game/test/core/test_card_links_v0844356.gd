extends GdUnitTestSuite
## v0.8.4.43.56, the author's note «Карточка в карточке» (roadmap «Находки автора 2026-11-13», «Карточка у курсора»): in the
## status «Концентрация: Зловонное облако» the spell's name shows the spell's card, as in BG3. A card of `CardInfo` carries
## `refs` — the names in it with a card of their own; `DetailsPanel` draws each a link and, while the cursor is on it, that
## card (`CardInfo.of_ref`) beside its own as `LinkedCard`, gone when the cursor leaves both.

var data: Dictionary
var kept: GameSession


func before_test() -> void:
	data = TestUtils.data()
	kept = GameState.session
	var s := TestUtils.new_session()
	for p: Dictionary in data["presets"]:
		if p["id"] == "cleric_branko":
			s.character = GameSession.normalized_character(CharacterBuilder.build_preset(p, data))
	CharacterRules.refresh(s.character, data, s.items)
	s.room_id = "brod-tavern-hall"
	GameState.session = s


func after_test() -> void:
	var pinned := DetailsPanel.icon_card()
	if pinned != null:
		pinned.unpin()
		pinned.visible = false
	GameState.session = kept


func _concentration() -> Dictionary:
	var s := GameState.session
	s.character["concentration"] = "stinking_cloud"
	for e: Dictionary in ConditionRules.shown(s, data):
		if str(e["condition"]) == "concentration":
			return e
	return {}


func _refs(card: Dictionary) -> Array:
	return (card.get("refs", []) as Array).map(func(r: Dictionary) -> String: return "%s=%s" % [r["text"], r["ref"]])


func test_the_concentration_s_card_links_its_spell_in_its_name_and_its_source() -> void:
	var e := _concentration()
	assert_str(str(e["of"])).is_equal("spells/stinking_cloud")
	var card := CardInfo.status(data, e)
	assert_str(str(card["title"])).is_equal("Концентрация: Зловонное облако")
	assert_str(str(card["sub"])).is_equal("Статус")
	assert_array(_refs(card)).contains(["Зловонное облако=spells/stinking_cloud"])
	assert_array(card["notes"]).contains(["Источник: Зловонное облако"])
	assert_bool((card["props"] as Array).any(func(p: String) -> bool: return p.begins_with(CardInfo.DURATION))).is_true()
	var text := DetailsPanel.card_text(card)
	assert_str(text).contains("[url=spells/stinking_cloud]")
	assert_str(DetailsPanel._linked(str(card["title"]), card["refs"])).contains("[url=spells/stinking_cloud]")
	assert_str(DetailsPanel._linked(str(card["title"]), card["refs"])).starts_with("Концентрация: ")


func test_a_status_a_spell_feature_or_thing_laid_links_what_laid_it() -> void:
	var s := GameState.session
	ConditionRules.add_effect(s.character, {"condition": "", "ends": {}, "source": {"kind": "spell", "id": "bless", "name": "Благословение"}})
	ConditionRules.add_effect(s.character, {"condition": "poisoned", "ends": {}, "source": {"kind": "master", "name": "яд в кружке"}})
	var bless := {}
	var poison := {}
	for e: Dictionary in ConditionRules.shown(s, data):
		if str(e["source"]) == "Благословение":
			bless = e
		if str(e["condition"]) == "poisoned":
			poison = e
	assert_str(str(bless["of"])).is_equal("spells/bless")
	assert_array(_refs(CardInfo.status(data, bless))).contains(["Благословение=spells/bless"])
	assert_str(str(poison["of"])).is_empty()  # the master's poison: nothing to show
	assert_array(_refs(CardInfo.status(data, poison))).is_empty()
	assert_array(CardInfo.status(data, poison)["notes"]).contains(["Источник: яд в кружке"])
	# a feature, a trait, a thing: their tables, the made ones by the session
	assert_str(ConditionRules.source_ref(data, {"source": {"kind": ItemRules.BORN, "id": "pact_of_the_chain"}})).is_equal("features/pact_of_the_chain")
	var trait_id := str((data["races"]["traits"] as Dictionary).keys()[0])
	assert_str(ConditionRules.source_ref(data, {"source": {"kind": "trait", "id": trait_id}})).is_equal("traits/" + trait_id)
	assert_str(ConditionRules.source_ref(data, {"source": {"kind": ItemRules.WORN, "id": "ring_of_protection"}})).is_equal("items/ring_of_protection")
	assert_str(ConditionRules.source_ref(data, {"source": {"kind": "spell", "id": "no_such_spell"}})).is_empty()
	assert_str(ConditionRules.source_ref(data, {"source": {"kind": "engine", "name": "0 HP"}})).is_empty()


func test_a_spell_links_the_conditions_it_lays_and_a_feature_its_spells() -> void:
	var hold := CardInfo.spell(data, "hold_person")
	var paralyzed := ConditionRules.name_of(data, "paralyzed")
	assert_array(_refs(hold)).contains([paralyzed + "=conditions/paralyzed"])
	assert_str(DetailsPanel.card_text(hold)).contains("[url=conditions/paralyzed]")
	var chain := CardInfo.feature(data, "pact_of_the_chain")
	var familiar := str(data["spells"]["find_familiar"]["name"])
	assert_array(_refs(chain)).contains([familiar + "=spells/find_familiar"])
	assert_str(DetailsPanel.card_text(chain)).contains("[url=spells/find_familiar]")


func test_a_ref_names_its_card() -> void:
	assert_str(str(CardInfo.of_ref(data, "spells/stinking_cloud")["title"])).is_equal("Зловонное облако")
	assert_str(str(CardInfo.of_ref(data, "features/pact_of_the_chain")["title"])).is_equal(str(data["classes"]["features"]["pact_of_the_chain"]["name"]))
	var cond := CardInfo.of_ref(data, "conditions/poisoned")
	assert_str(str(cond["title"])).is_equal("Отравлен")
	assert_str(str(cond["sub"])).is_equal("Состояние")
	assert_str(str(cond["desc"])).is_equal("помеха на броски атаки и проверки характеристик.")
	assert_str(str(CardInfo.of_ref(data, "items/longsword")["icon"])).is_equal("items/longsword")
	assert_dict(CardInfo.of_ref(data, "spells/")).is_empty()
	assert_dict(CardInfo.of_ref(data, "spells/no_such_spell")).is_empty()
	assert_dict(CardInfo.of_ref(data, "monsters/wolf")).is_empty()


func test_a_link_is_a_whole_word_the_longest_at_one_place() -> void:
	var light := [{"text": "Свет", "ref": "spells/light"}]
	var t := DetailsPanel._linked("Светлячок, Свет и [скобки]", light)
	assert_int(t.count("[url=")).is_equal(1)
	assert_str(t).contains("Светлячок, [url=spells/light]")
	assert_str(t).contains("[lb]скобки]")  # the rest is escaped as before
	var two := [{"text": "Огненный", "ref": "a/x"}, {"text": "Огненный шар", "ref": "spells/fireball"}]
	assert_str(DetailsPanel._linked("Огненный шар.", two)).contains("[url=spells/fireball]")
	assert_str(DetailsPanel._linked("без ссылок", [])).is_equal("без ссылок")


## The author's example: the hero's status on its portrait carries the card with the link; pinned, the cursor on the link
## shows the spell's card beside it; off the link and off that card it goes.
func test_a_pinned_status_shows_the_spell_s_card_while_its_link_is_hovered() -> void:
	_concentration()
	var col := auto_free(PartyColumn.new()) as PartyColumn
	add_child(col)
	col.refresh()
	var chip := col.find_child("Chip_concentration", true, false) as IconSlot
	assert_object(chip).is_not_null()
	assert_array(_refs(chip.card)).contains(["Зловонное облако=spells/stinking_cloud"])
	assert_str(chip.card_line(chip.tooltip_text)).is_empty()  # the time is on the card, not a line over it
	# not pinned, its card says that pinning it reaches the links
	chip.show_card()
	var tip := DetailsPanel.icon_card()
	assert_object(tip).is_not_null()
	var more := tip.find_child("DetailsMore", true, false) as Label
	assert_bool(more.visible).is_true()
	assert_str(more.text).is_equal(tr("DETAILS_LINKS"))
	chip.pin_card()
	var pinned := DetailsPanel.pinned_card()
	assert_object(pinned).is_not_null()
	var title := pinned.find_child("DetailsTitle", true, false) as RichTextLabel
	assert_str(title.text).contains("[url=spells/stinking_cloud]")
	assert_str(pinned.title()).is_equal("Концентрация: Зловонное облако")
	assert_int(title.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)  # the cursor reaches a pinned card's links, a drag goes on to the card
	title.meta_hover_started.emit("spells/stinking_cloud")
	await await_idle_frame()
	var linked := pinned.linked_card()
	assert_object(linked).is_not_null()
	assert_str(linked.title()).is_equal("Зловонное облако")
	assert_str(linked.body()).contains("Заклинание 3 круга")
	assert_bool(linked.position.x >= pinned.get_global_rect().end.x or linked.get_global_rect().end.x <= pinned.position.x).is_true()
	assert_int(linked.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)  # the cursor goes over to it
	assert_str(pinned.pinned()).is_equal("Концентрация: Зловонное облако")  # the pinned card stays as it was
	title.meta_hover_ended.emit("spells/stinking_cloud")
	await await_idle_frame()
	assert_object(pinned.linked_card()).override_failure_message("a moment to reach it").is_not_null()
	pinned._left_at = Time.get_ticks_msec() - DetailsPanel.LINK_GRACE_MS - 1
	await await_idle_frame()
	await await_idle_frame()
	assert_object(pinned.linked_card()).is_null()
	# unpinned, its link's card goes with it
	title.meta_hover_started.emit("spells/stinking_cloud")
	assert_object(pinned.linked_card()).is_not_null()
	pinned.unpin()
	assert_object(pinned.linked_card()).is_null()
	await await_idle_frame()


## A card of a link has links of its own: Hold Person's card shows «Парализован» beside it.
func test_a_card_of_a_link_shows_a_card_of_its_own_link() -> void:
	var panel := DetailsPanel.new(Vector2.ZERO, true)
	add_child(panel)
	auto_free(panel)
	var card := CardInfo.status(data, {"name": "Удержание", "left": "1 мин", "source": "Удержание человека", "text": "", "icon": "spells/hold_person", "of": "spells/hold_person"})
	panel.pin(panel, str(card["title"]), CardInfo.plain(card), card)
	var body := panel.find_child("DetailsText", true, false) as RichTextLabel
	body.meta_hover_started.emit("spells/hold_person")
	var hold := panel.linked_card()
	assert_object(hold).is_not_null()
	(hold.find_child("DetailsText", true, false) as RichTextLabel).meta_hover_started.emit("conditions/paralyzed")
	var para := hold.linked_card()
	assert_object(para).is_not_null()
	assert_str(para.title()).is_equal(ConditionRules.name_of(data, "paralyzed"))
	assert_bool(panel._wants_child()).is_true()  # a card of its link's link up keeps it
	panel.unpin()
	assert_bool(hold.visible).is_false()
	assert_bool(para.visible).is_false()
	await await_idle_frame()


## A creature's status a spell laid: its icon in the creature's card carries the card with the spell's link.
func test_a_creature_s_status_of_a_spell_links_the_spell() -> void:
	var s := GameState.session
	TestUtils.fight(s, data, [{"monster": "wolf", "col": 1}])
	var wolf := CombatRules.fighter(s, TestUtils.foe(s, 1))
	ConditionRules.add_effect(wolf, {"condition": "", "ends": {}, "source": {"kind": "spell", "id": "bane", "name": "Бедствие"}})
	var box := VBoxContainer.new()
	CreatureCardPanel.fill(box, CreatureCard.of(s, data, wolf))
	var cells := (box.find_child("CardStatuses", false, false) as Node).find_children("*", "IconSlot", true, false)
	var bane := cells.filter(func(c: IconSlot) -> bool: return _refs(c.card).has("Бедствие=spells/bane"))
	assert_int(bane.size()).is_equal(1)
	assert_str((bane[0] as IconSlot).tooltip_text).is_equal((bane[0] as IconSlot).tip_title)
	box.free()
