class_name PartyLead
extends RefCounted
## Who of the party the player leads out of a fight (v0.8.4.44.12, as in BG3; the author: «клик на портрет союзника должен
## … давать управление союзником непосредственно как игроком (игрок становится спутником в этот момент и ходит за тем
## персонажем, которым я управляю)»): the hero or one who follows it. Its square is the walk's (`s.layouts.at`,
## WalkRules.settle), the rest of the party walks round it (MapSpots.party); its face is the token's, its things and
## passives the hotbar's, its eyes and feet find what a walk finds (a cache, a trap underfoot) and «Осмотреться» rolls its
## Perception. The hero still speaks for the party: a talk and the master's story stay the hero's. A fight hands the lead
## back to the hero (CombatRules.start), so does a follower that leaves. Kept in `s.layouts.lead`, nothing new to migrate.

const KEY := "lead"


## The id of the one led now: Being.HERO, or a follower's.
static func of(s: GameSession) -> String:
	var id := str(s.layouts.get(KEY, ""))
	if id.is_empty() or id == Being.HERO:
		return Being.HERO
	if not Being.follows(s, id) or CombatRules.active(s):
		return Being.HERO
	return id


## Its sheet for reading: Sheet.HERO or the follower's.
static func who(s: GameSession, data: Dictionary) -> Dictionary:
	return Sheet.who(s, data, of(s))


## Its sheet for writing (damage, a status): Sheet.own.
static func own(s: GameSession) -> Dictionary:
	return Sheet.own(s, of(s))


## The ref of the party's portrait led now: "" — the hero, "npc:<id>" — a follower (AllyRules.party).
static func ref(s: GameSession) -> String:
	var id := of(s)
	return "" if id == Being.HERO else "npc:" + id


## "" when `id` may be led now, else the reason (a localization key): not in a fight, one of the party, on its feet.
static func why(s: GameSession, data: Dictionary, id: String) -> String:
	if CombatRules.active(s):
		return "LEAD_NOT_IN_FIGHT"
	if id == Being.HERO:
		return ""
	if not Being.follows(s, id):
		return "LEAD_NOT_PARTY"
	return "LEAD_DOWN" if Sheet.hp(s, data, Sheet.who(s, data, id)) <= 0 else ""


## `id` is led from now (why first): the walk's square becomes the one it stands on, the one led before walks with the rest.
static func take(s: GameSession, data: Dictionary, id: String) -> void:
	if id == of(s):
		return
	var map := WalkRules.view(s, data)
	var cell := MapSpots.square_of(s, data, id)
	if id == Being.HERO:
		s.layouts.erase(KEY)
	else:
		s.layouts[KEY] = id
	if cell.x >= 0:
		WalkRules.stand(s, map, s.room_id, cell)
