extends Act
## What is done with a door or a thing beside it (`how.how`, FightField.acts): shut, bar, unbar, lock, pick, force a door; push or
## smash a thing. A foe at a barred door forces it by the same road. Its cost by the way (`rules.combat.act_bonus` field.<how>).

const WORDS := {
	"door_close": "Закрыть дверь", "door_bar": "Подпереть дверь", "door_unbar": "Убрать подпорку", "door_lock": "Запереть ключом",
	"door_pick": "Вскрыть замок", "door_force": "Выломать дверь", "block_push": "Толкнуть вещь", "block_smash": "Разбить вещь",
}


func title() -> String:
	return "Дверь или вещь рядом"


func order() -> int:
	return 23


func buttons(s: GameSession, data: Dictionary, f: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for how: String in FightField.acts(s, data, f):
		out.append({"name": "Act_" + how, "text": WORDS[how], "how": {"how": how}, "tip": ""})
	return out


func why(s: GameSession, data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> String:
	return FightField.why_not(s, data, f, str(how.get("how", "")))


func run(s: GameSession, data: Dictionary, f: Dictionary, _to: String, how: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	FightField.act(s, data, f, str(how["how"]), lines)
	return lines


## By the moment, not the character's own: not in the book (v0.8.4.43.13).
func book() -> bool:
	return false
