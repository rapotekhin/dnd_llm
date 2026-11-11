extends Act
## A shapechanger takes another form or its own (5e Shapechanger, v0.8.4.27.2): the forms are rows of `rules.shapes` of its
## template (FeatureRules.forms) — another template's body with its blows, AC and size (a werewolf's wolf), or its own with
## other feet (an imp's raven). Its hit points stay its own; it falls in its true form (Harm). The AI takes a form when its
## blows there are worth more (`rules.combat.ai.acts.shape` — turns of that gain).


func title() -> String:
	return "Сменить облик"


func tip() -> String:
	return "Действием: другой облик или свой; хиты те же"


func order() -> int:
	return 40


func shown(s: GameSession, data: Dictionary, f: Dictionary) -> bool:
	return not FeatureRules.forms(data, Sheet.holder(s, f)).is_empty()


func buttons(s: GameSession, data: Dictionary, f: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for form: String in _ways(s, data, f):
		var name := str(FeatureRules.forms(data, Sheet.holder(s, f)).get(form, {}).get("name", "свой облик"))
		out.append({"name": "Shape_" + (form if not form.is_empty() else "own"), "text": "Облик: " + name, "how": {"form": form}, "tip": tip()})
	return out


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> String:
	return "" if _ways(s, data, f).has(str(how.get("form", ""))) else "COMBAT_BAD_TARGET"


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> Array[String]:
	return FeatureRules.take_form(s, data, f, str(how.get("form", "")))


## A form worth more blows than the one it is in, by the attack's own offers in each.
func offers(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if targets.is_empty() or Sheet.is_hero(f):
		return out
	var now := _blows(s, data, f, targets)
	for form: String in _ways(s, data, f):
		var ghost := f.duplicate(true)
		FeatureRules.take_form(s, data, ghost, form)
		var gain := _blows(s, data, ghost, targets) - now
		if gain > 0.0:
			out.append({"act": id, "to": "", "how": {"form": form}, "t": f, "kind": "self", "far": 0, "self": true, "power": gain * _weight(data)})
	return out


## The forms it can take now: those it is not in, and its own ("") when it is in another.
func _ways(s: GameSession, data: Dictionary, f: Dictionary) -> Array[String]:
	var c := Sheet.holder(s, f)
	var now := FeatureRules.form_of(s, f)
	var out: Array[String] = []
	var all := FeatureRules.forms(data, c)
	for form: String in all:
		if form != now and not FeatureRules.is_own(all[form], str(c.get("monster", ""))):
			out.append(form)
	if not now.is_empty():
		out.append("")
	return out


func _blows(s: GameSession, data: Dictionary, f: Dictionary, targets: Array[Dictionary]) -> float:
	var best := 0.0
	for o: Dictionary in Acts.one("attack").offers(s, data, f, targets):
		best = maxf(best, float(o["power"]))
	return best


## By the moment, not the character's own: not in the book (v0.8.4.43.13).
func book() -> bool:
	return false
