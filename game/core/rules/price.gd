class_name Price
extends RefCounted
## One price (v0.7.60, ADR-0012): a base and its modifiers with their labels, as a roll has its parts. A rule says what
## changes the price and how it rounds; the player sees why on the hover. Whole coppers, in percents as the data has them.


## A quote from `base`: {num, den, base, parts [{label, pct}]}; the running value is num / den.
static func start(base: int) -> Dictionary:
	return {"num": float(base), "den": 1.0, "base": base, "parts": [] as Array[Dictionary]}


## A modifier in percent; 100 changes nothing and shows nothing.
static func mod(q: Dictionary, label: String, pct: float) -> Dictionary:
	if not is_equal_approx(pct, 100.0):
		q["num"] = float(q["num"]) * pct
		q["den"] = float(q["den"]) * 100.0
		(q["parts"] as Array[Dictionary]).append({"label": label, "pct": pct})
	return q


static func value(q: Dictionary) -> float:
	return float(q["num"]) / float(q["den"])


## The running value kept between `least` and `most`, with what limited it.
static func clamp_to(q: Dictionary, least: float, most: float, label: String) -> Dictionary:
	var v := value(q)
	if v < least or v > most:
		q["num"] = clampf(v, least, most)
		q["den"] = 1.0
		(q["parts"] as Array[Dictionary]).append({"label": label, "pct": 0.0})
	return q


## The running value rounded up now: a rule that rounds between its modifiers.
static func ceil_now(q: Dictionary) -> Dictionary:
	q["num"] = float(ceili(value(q)))
	q["den"] = 1.0
	return q


static func ceiled(q: Dictionary, least: int = 0) -> int:
	return maxi(least, ceili(value(q)))


static func floored(q: Dictionary, least: int = 0) -> int:
	return maxi(least, floori(value(q)))


static func rounded(q: Dictionary, least: int = 0) -> int:
	return maxi(least, roundi(value(q)))


## A plain share of a base: `pct` of it, rounded, never under `least`.
static func share(base: int, pct: float, least: int = 0) -> int:
	return rounded(mod(start(base), "", pct), least)


## The hover of a price: «Основа: 10 зм\n−10% торг\n= 9 зм».
static func text(q: Dictionary, cp: int) -> String:
	var lines: Array[String] = ["Основа: %s" % Money.format(int(q["base"]))]
	for p: Dictionary in q["parts"]:
		var pct := float(p["pct"])
		lines.append(str(p["label"]) if pct <= 0.0 else "%+d%% %s" % [roundi(pct - 100.0), p["label"]])
	lines.append("= %s" % Money.format(cp))
	return "\n".join(lines)
