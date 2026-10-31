class_name ArenaPanel
extends ModalFrame
## The arena window (roadmap v0.7.45), opened at its manager: the arena's rule, the hero's rank and wins; enlisting;
## the bout of the day — the opponent, the engine's estimate, the prize and a bet on oneself («Точно?» before the blood
## pit); the bout of two fighters to bet on — the house's odds, Insight for the true estimate; a festival's
## tournament. Every act is GameState.arena_*: the engine decides.

const SCENE := "res://ui/components/arena_panel.tscn"

var _box: VBoxContainer
var _site := ""
var _bet_self := 0
var _bet_card := 0


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseArenaButton"
	_box = body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


func open(site_id: String) -> void:
	_site = site_id
	visible = true
	_rebuild()


func _label(parent: Control, text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not variation.is_empty():
		l.theme_type_variation = variation
	parent.add_child(l)
	return l


func _head(text: String) -> void:
	_label(_box, text).theme_type_variation = UiTheme.ACCENT_LABEL


func _act(err: String) -> void:
	set_note(err)
	if not err.is_empty():
		EventBus.message.emit(err)


func _button(parent: Control, name: String, text: String, why: String, run: Callable) -> Button:
	var b := Button.new()
	b.name = name
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.disabled = not why.is_empty() or GameState.is_busy() or not Backend.is_ready()
	if not why.is_empty():
		b.tooltip_text = why
	b.pressed.connect(run)
	parent.add_child(b)
	return b


func _spin(parent: Control, name: String, value: int, max_cp: int, on_change: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = name
	spin.min_value = 0
	spin.max_value = maxf(0.0, max_cp / 100.0)
	spin.step = 0.5
	spin.suffix = "зм"
	spin.value = clampi(value, 0, max_cp) / 100.0
	spin.value_changed.connect(func(v: float) -> void: on_change.call(roundi(v * 100)))
	parent.add_child(spin)
	return spin


func _rebuild() -> void:
	if not visible or not GameState.has_session() or _site.is_empty():
		return
	clear_body()
	for b in footer.get_children():
		footer.remove_child(b)
		b.queue_free()
	var s := GameState.session
	var data := Catalog.data
	title.text = ArenaRules.site_name(data, _site)
	var rc := ArenaRules.rule_cfg(data, _site)
	var rule := _label(_box, tr("ARENA_RULE").format({"rule": str(rc["name"]), "text": str(rc["text"])}))
	rule.name = "ArenaRule"
	if ArenaRules.rule(data, _site) == "death":
		rule.add_theme_color_override("font_color", UiTheme.BAD)
	var gold := int(s.character["gold_cp"])
	if not ArenaRules.enlisted(s, _site):
		_label(_box, tr("ARENA_ENLIST_HINT").format({"fee": Money.format(int(ArenaRules.cfg(data)["fee_cp"]))}), UiTheme.MUTED_LABEL)
		_button(_box, "ArenaEnlist", tr("BTN_ARENA_ENLIST"), ArenaRules.enlist_why(s, data, _site), func() -> void: _act(GameState.arena_enlist(_site)))
	else:
		var r := ArenaRules.rec(s, _site)
		_label(_box, tr("ARENA_RANK").format({"rank": ArenaRules.rank_name(data, int(r["rank"])), "wins": int(r.get("wins", 0)),
			"losses": int(r.get("losses", 0))})).name = "ArenaRank"
		_bout(s, data, gold)
	_tourney(s, data)
	_card(s, data, gold)
	_label(_box, tr("CONTEST_GOLD").format({"money": Money.format(gold)}), UiTheme.MUTED_LABEL)


func _bout(s: GameSession, data: Dictionary, gold: int) -> void:
	var opp := ArenaRules.opponent(s, data, _site)
	var m: Dictionary = data["monsters"][str(opp["monster"])]
	var o := ArenaRules.hero_odds(s, data, _site, str(opp["monster"]))
	var prize := int(int(ArenaRules.ranks(data)[int(opp["rank"])]["prize_cp"]) * int(ArenaRules.rule_cfg(data, _site).get("prize_pct", 100)) / 100)
	_head(tr("ARENA_BOUT_HEAD"))
	_label(_box, tr("ARENA_OPPONENT").format({"name": str(opp["name"]), "hp": int(m["hp"]), "ac": int(m["ac"]), "prize": Money.format(prize)})).name = "ArenaOpponent"
	var est := tr("ARENA_ODDS").format({"house": roundi(float(o["house"]) * 100), "mult": "%.2f" % float(o["mult"])})
	if ArenaRules.knows(s, _site):
		est += " " + tr("ARENA_ODDS_TRUE").format({"p": roundi(float(o["p"]) * 100)})
	_label(_box, est, UiTheme.MUTED_LABEL).name = "ArenaOdds"
	var why := ArenaRules.bout_why(s, data, _site)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	_label(row, tr("ARENA_BET_SELF"))
	_spin(row, "ArenaBetSelf", _bet_self, mini(gold, ArenaRules.max_bet(s, data)), func(cp: int) -> void: _bet_self = cp)
	var deadly := ArenaRules.rule(data, _site) == "death"
	_button(row, "ArenaFight", tr("BTN_ARENA_FIGHT"), why, func() -> void:
		var go := func() -> void: _act(GameState.arena_bout(_site, _bet_self))
		if deadly:  # «Точно?» before the blood pit
			ConfirmBox.ask(self, tr("CONFIRM_PIT_TITLE"), tr("CONFIRM_PIT").format({"name": str(opp["name"])}), tr("BTN_ARENA_FIGHT"), go)
		else:
			go.call())


func _tourney(s: GameSession, data: Dictionary) -> void:
	var t := ArenaRules.tournament(s, data, _site)
	if t.is_empty():
		return
	var st := ArenaRules.tourney_state(s, _site)
	_head(tr("ARENA_TOURNEY_HEAD").format({"name": str(t["name"])}))
	_label(_box, tr("ARENA_TOURNEY").format({"bouts": int(t.get("bouts", 3)), "round": int(st.get("round", 0)), "prize": Money.format(int(t.get("prize_cp", 0))),
		"item": ItemRules.display_name(data["items"], s.items, str(t.get("prize_item", ""))) if not str(t.get("prize_item", "")).is_empty() else "—"})).name = "ArenaTourney"
	_button(_box, "ArenaTourneyFight", tr("BTN_ARENA_TOURNEY"), ArenaRules.tourney_why(s, data, _site),
		func() -> void: _act(GameState.arena_bout(_site, 0, true)))


func _card(s: GameSession, data: Dictionary, gold: int) -> void:
	var c := ArenaRules.card(s, data, _site)
	_head(tr("ARENA_CARD_HEAD"))
	var line := tr("ARENA_CARD").format({"a": str(c["a"]["name"]), "b": str(c["b"]["name"]), "pa": roundi(float(c["house"]) * 100),
		"ma": "%.2f" % float(c["mult_a"]), "mb": "%.2f" % float(c["mult_b"])})
	if ArenaRules.knows(s, _site):
		line += " " + tr("ARENA_ODDS_TRUE").format({"p": roundi(float(c["p"]) * 100)})
	_label(_box, line).name = "ArenaCard"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var ins := _button(row, "ArenaInsight", tr("BTN_ARENA_INSIGHT"), ArenaRules.insight_why(s, data, _site), func() -> void: _act(GameState.arena_insight(_site)))
	ins.tooltip_text = tr("BTN_ARENA_INSIGHT_TIP").format({"dc": int(ArenaRules.cfg(data)["insight"]["dc"])}) if ins.tooltip_text.is_empty() else ins.tooltip_text
	_spin(row, "ArenaBetCard", _bet_card, mini(gold, ArenaRules.max_bet(s, data)), func(cp: int) -> void: _bet_card = cp)
	var why := ArenaRules.card_why(s, data, _site)
	for side: String in ["a", "b"]:
		_button(row, "ArenaBet_" + side, tr("BTN_ARENA_BET").format({"name": str(c[side]["name"]).get_slice("«", 1).trim_suffix("»")}), why,
			func() -> void: _act(GameState.arena_bet(_site, side, _bet_card)))
