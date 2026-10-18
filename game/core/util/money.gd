class_name Money
extends RefCounted
## Coins are stored in copper (cp); shown as «15 зм 3 см 7 мм».


static func format(cp: int) -> String:
	var sign := "−" if cp < 0 else ""
	var v := absi(cp)
	var parts: PackedStringArray = []
	if v / 100 > 0:
		parts.append("%d зм" % (v / 100))
	if (v % 100) / 10 > 0:
		parts.append("%d см" % ((v % 100) / 10))
	if v % 10 > 0:
		parts.append("%d мм" % (v % 10))
	return sign + (" ".join(parts) if not parts.is_empty() else "0 зм")
