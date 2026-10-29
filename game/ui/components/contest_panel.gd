class_name ContestPanel
extends Control
## The contest window (roadmap v0.7.40): a game with an NPC of the scene for a stake. Before the game — the kind with
## both bonuses and the chance of a round, the stake (coins or a thing of the NPC); during it — the score and the
## rounds rolled one by one, honestly or cheating, or given up. Every act is GameState.contest_*: the engine decides.

var _box: VBoxContainer
var frame: ModalFrame
var _npc := ""
var _kind := ""
var _stake := 0
var _cp := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.new(tr("CONTEST_TITLE"), 720.0)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	frame.close_x.name = "CloseContestButton"
	_box = frame.body
	EventBus.state_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)


## Opens the window at `npc_id`, on `kind` when the master offered one.
func open(npc_id: String, kind: String = "") -> void:
	_npc = npc_id
	_kind = kind
	_stake = 0
	_cp = 0
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


func _act(err: String) -> void:
	frame.set_note(err)
	if not err.is_empty():
		EventBus.message.emit(err)


func _clear_footer() -> void:
	for b in frame.footer.get_children():
		frame.footer.remove_child(b)
		b.queue_free()


func _rebuild() -> void:
	if not visible or not GameState.has_session() or _npc.is_empty():
		return
	frame.clear_body()
	_clear_footer()
	var s := GameState.session
	var data := Catalog.data
	frame.title.text = tr("CONTEST_TITLE_AT").format({"name": BondRules.npc_name(s, data, _npc)})
	var st := ContestRules.state(s)
	if not st.is_empty():
		_game(s, data, st)
	else:
		_setup(s, data)


func _setup(s: GameSession, data: Dictionary) -> void:
	_label(_box, tr("CONTEST_HINT"), UiTheme.MUTED_LABEL)
	var why := ContestRules.why_not(s, data, _npc)
	if not why.is_empty():
		_label(_box, why).name = "ContestWhy"
		return
	var kinds := ContestRules.kinds(data)
	if not kinds.has(_kind):
		_kind = str(kinds.keys()[0])
	var kinds_box := OptionButton.new()
	kinds_box.name = "ContestKinds"
	for id: String in kinds:
		kinds_box.add_item(str(kinds[id]["name"]))
		kinds_box.set_item_metadata(kinds_box.item_count - 1, id)
		if id == _kind:
			kinds_box.select(kinds_box.item_count - 1)
	kinds_box.item_selected.connect(func(i: int) -> void:
		_kind = str(kinds_box.get_item_metadata(i))
		_rebuild.call_deferred())
	_box.add_child(kinds_box)
	var k := ContestRules.kind(data, _kind)
	var o := ContestRules.odds(s, data, _npc, _kind)
	var odds := _label(_box, tr("CONTEST_ODDS").format({"hero": "%+d" % int(o["hero"]), "npc": "%+d" % int(o["npc"]),
		"p": int(o["chance"]), "wins": int(k.get("wins", 1))}))
	odds.name = "ContestOdds"
	if not str(k.get("cheat", "")).is_empty():
		var co := ContestRules.odds(s, data, _npc, _kind, true)
		_label(_box, tr("CONTEST_CHEAT_ODDS").format({"skill": tr("SKILL_" + str(k["cheat"]).to_upper()), "p": int(co["chance"])}), UiTheme.MUTED_LABEL)
	if not str(k.get("lose", {}).get("condition", "")).is_empty():
		_label(_box, tr("CONTEST_LOSE").format({"what": ConditionRules.name_of(data, str(k["lose"]["condition"]))}), UiTheme.MUTED_LABEL)
	var stakes := ContestRules.stakes(s, data, _npc)
	_stake = clampi(_stake, 0, stakes.size() - 1)
	var stake_box := OptionButton.new()
	stake_box.name = "ContestStakes"
	for st: Dictionary in stakes:
		stake_box.add_item(str(st["name"]) if str(st["kind"]) == "coins" else "%s — %s" % [st["name"], Money.format(int(st["cp"]))])
	stake_box.select(_stake)
	stake_box.item_selected.connect(func(i: int) -> void:
		_stake = i
		_rebuild.call_deferred())
	_box.add_child(stake_box)
	var stake: Dictionary = stakes[_stake]
	var gold := int(s.character["gold_cp"])
	if str(stake["kind"]) == "coins":
		var row := HBoxContainer.new()
		_box.add_child(row)
		_label(row, tr("CONTEST_COINS"))
		var spin := SpinBox.new()
		spin.name = "ContestCoins"
		spin.min_value = float(ContestRules.cfg(data)["stake"]["min_cp"]) / 100.0
		spin.max_value = float(mini(int(stake["max"]), gold)) / 100.0
		spin.step = 0.1
		spin.suffix = "зм"
		_cp = clampi(_cp if _cp > 0 else int(ContestRules.cfg(data)["stake"]["min_cp"]) * 10, int(spin.min_value * 100), maxi(int(spin.max_value * 100), int(spin.min_value * 100)))
		spin.value = _cp / 100.0
		spin.value_changed.connect(func(v: float) -> void: _cp = roundi(v * 100))
		row.add_child(spin)
	_label(_box, tr("CONTEST_GOLD").format({"money": Money.format(gold)}), UiTheme.MUTED_LABEL)
	var play := frame.add_button(tr("BTN_CONTEST_PLAY"), func() -> void:
		_act(GameState.contest_start(_npc, _kind, _stake, _cp)), true)
	play.name = "ContestPlay"
	play.disabled = GameState.is_busy() or not Backend.is_ready()


func _game(s: GameSession, data: Dictionary, st: Dictionary) -> void:
	var k := ContestRules.kind(data, str(st["kind"]))
	var stake: Dictionary = st["stake"]
	_label(_box, "%s · %s" % [k.get("name", ""), Money.format(int(st["cp"])) if str(stake["kind"]) == "coins" else "%s / %s" % [stake["name"], Money.format(int(st["cp"]))]])
	var score := _label(_box, tr("CONTEST_SCORE").format({"hero": int(st["hero"]), "npc": int(st["npc_wins"]), "wins": int(k.get("wins", 1)),
		"name": BondRules.npc_name(s, data, str(st["npc"]))}))
	score.name = "ContestScore"
	score.add_theme_color_override("font_color", UiTheme.ACCENT)
	var o := ContestRules.odds(s, data, str(st["npc"]), str(st["kind"]))
	_label(_box, tr("CONTEST_ROUND_ODDS").format({"hero": "%+d" % int(o["hero"]), "npc": "%+d" % int(o["npc"]), "p": int(o["chance"])}), UiTheme.MUTED_LABEL)
	var busy := GameState.is_busy() or not Backend.is_ready()
	var give := frame.add_button(tr("BTN_CONTEST_FORFEIT"), func() -> void: _act(GameState.contest_forfeit()))
	give.name = "ContestForfeit"
	give.disabled = busy
	if not str(k.get("cheat", "")).is_empty():
		var co := ContestRules.odds(s, data, str(st["npc"]), str(st["kind"]), true)
		var cheat := frame.add_button(tr("BTN_CONTEST_CHEAT"), func() -> void: _act(GameState.contest_round(true)))
		cheat.name = "ContestCheat"
		cheat.disabled = busy
		cheat.tooltip_text = tr("CONTEST_CHEAT_TIP").format({"skill": tr("SKILL_" + str(k["cheat"]).to_upper()), "p": int(co["chance"])})
	var roll := frame.add_button(tr("BTN_CONTEST_ROLL"), func() -> void: _act(GameState.contest_round(false)), true)
	roll.name = "ContestRoll"
	roll.disabled = busy
