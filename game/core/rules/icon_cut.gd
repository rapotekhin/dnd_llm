class_name IconCut
extends RefCounted
## A thing cut out of a flat chroma ground (v0.8.4.44.1): the frame the icon model drew for a made thing (MadeIcons)
## becomes an icon with a clear ground, no model and no network. The A/B of 2026-11-14 on FLUX frames: as clean as
## BiRefNet at a fiftieth of its time.
## 1. The ground's colour is a box over the four corners' squares, each mean ± `sd` deviations: a ground with a little
##    gradient across the frame is all inside it.
## 2. The ground grows from the border through pixels near that box: what the thing surrounds is kept — an emerald,
##    a green cloak, the glass of a flask.
## 3. The edge is soft by how far a pixel is from the box, and the ground's colour is taken off the thing's rim.
## 4. Inside the thing a pixel near the ground's hue and saturation is the ground showing through (glass, the gaps of a
##    chain mail): its tint is taken off and it is as clear as it is close to the ground's colour.
## 5. The thing is cropped to its own square with a margin and scaled to the icon's side.
## The numbers are rules.made_icons.cut.


## The icon of a chroma frame, RGBA8 of cf.side; null for an empty frame.
static func cut(src: Image, cf: Dictionary) -> Image:
	if src == null or src.is_empty():
		return null
	var side := int(cf["work"])
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	img.resize(side, side, Image.INTERPOLATE_LANCZOS)
	var px := img.get_data()
	var n := side * side
	var box := _box(px, side, int(cf["corner"]), float(cf["sd"]))
	var lo: PackedFloat32Array = box[0]
	var hi: PackedFloat32Array = box[1]
	var mean: PackedFloat32Array = box[2]
	var far := PackedFloat32Array()  # how far out of the ground's box
	far.resize(n)
	for i: int in n:
		var d := 0.0
		for c: int in 3:
			var v := float(px[i * 3 + c])
			d = maxf(d, maxf(lo[c] - v, v - hi[c]))
		far[i] = d
	var ground := _grow(far, side, float(cf["like"]))
	var alpha := PackedFloat32Array()
	alpha.resize(n)
	var margin := float(cf["margin"])
	var ramp := float(cf["ramp"])
	for i: int in n:
		alpha[i] = clampf((far[i] - margin) / ramp, 0.0, 1.0) if ground[i] == 1 else 1.0
	var out := PackedByteArray()
	out.resize(n * 4)
	var green := mean[1] >= mean[0] and mean[1] >= mean[2]  # else a magenta ground: its red and blue are the spill
	var ground_hue := _hue(mean[0], mean[1], mean[2])
	for y: int in side:
		for x: int in side:
			var i := y * side + x
			var r := float(px[i * 3])
			var g := float(px[i * 3 + 1])
			var b := float(px[i * 3 + 2])
			var a := alpha[i]
			var spill := 0.0  # how much of the ground's colour to take off: 1 on the rim
			if a > 0.0 and (a < 1.0 or _beside_ground(ground, side, x, y)):
				spill = 1.0
			elif a >= 1.0:  # inside the thing: the ground showing through
				var w := _like_ground(cf, r, g, b, ground_hue)
				if w > 0.0:
					spill = w
					var dist := sqrt(pow(r - mean[0], 2) + pow(g - mean[1], 2) + pow(b - mean[2], 2))
					var clear := 1.0 - clampf((dist - float(cf["clear_from"])) / float(cf["clear_span"]), 0.0, 1.0)
					a = 1.0 - w * clear
			if spill > 0.0:
				if green:
					g -= spill * maxf(g - maxf(r, b), 0.0)
				else:
					var over := maxf((r + b) / 2.0 - g, 0.0) * spill
					r -= over
					b -= over
			out[i * 4] = clampi(roundi(r), 0, 255)
			out[i * 4 + 1] = clampi(roundi(g), 0, 255)
			out[i * 4 + 2] = clampi(roundi(b), 0, 255)
			out[i * 4 + 3] = clampi(roundi(a * 255.0), 0, 255)
	var rgba := Image.create_from_data(side, side, false, Image.FORMAT_RGBA8, out)
	return _crop(rgba, cf)


## [lo, hi, mean] of the ground: the box over the four corners' squares of `k`, each mean ± sd deviations.
static func _box(px: PackedByteArray, side: int, k: int, sd: float) -> Array:
	var lo := PackedFloat32Array([255.0, 255.0, 255.0])
	var hi := PackedFloat32Array([0.0, 0.0, 0.0])
	var mean := PackedFloat32Array([0.0, 0.0, 0.0])
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(side - k, 0), Vector2i(0, side - k), Vector2i(side - k, side - k)]:
		for c: int in 3:
			var sum := 0.0
			var sq := 0.0
			for y: int in k:
				for x: int in k:
					var v := float(px[((corner.y + y) * side + corner.x + x) * 3 + c])
					sum += v
					sq += v * v
			var m := sum / (k * k)
			var dev := sqrt(maxf(sq / (k * k) - m * m, 0.0))
			lo[c] = minf(lo[c], m - sd * dev)
			hi[c] = maxf(hi[c], m + sd * dev)
			mean[c] += m / 4.0
	return [lo, hi, mean]


## The ground: 1 for a pixel reached from the border through pixels less than `like` out of the box.
static func _grow(far: PackedFloat32Array, side: int, like: float) -> PackedByteArray:
	var ground := PackedByteArray()
	ground.resize(side * side)
	var queue := PackedInt32Array()
	for i: int in side:
		for at: int in [i, (side - 1) * side + i, i * side, i * side + side - 1]:
			if ground[at] == 0 and far[at] < like:
				ground[at] = 1
				queue.append(at)
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		var x := at % side
		var y := at / side
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + step.x
			var ny := y + step.y
			if nx < 0 or ny < 0 or nx >= side or ny >= side:
				continue
			var j := ny * side + nx
			if ground[j] == 0 and far[j] < like:
				ground[j] = 1
				queue.append(j)
	return ground


static func _beside_ground(ground: PackedByteArray, side: int, x: int, y: int) -> bool:
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx := x + step.x
		var ny := y + step.y
		if nx >= 0 and ny >= 0 and nx < side and ny < side and ground[ny * side + nx] == 1:
			return true
	return false


## 0…1: how much a pixel inside the thing is the ground showing through, by its hue's distance and its saturation.
static func _like_ground(cf: Dictionary, r: float, g: float, b: float, ground_hue: float) -> float:
	var mx := maxf(r, maxf(g, b))
	if mx <= 0.0:
		return 0.0
	var sat := (mx - minf(r, minf(g, b))) / mx
	var dh := absf(fposmod(_hue(r, g, b) - ground_hue + 180.0, 360.0) - 180.0)
	var by_hue := clampf((float(cf["hue_zero"]) - dh) / (float(cf["hue_zero"]) - float(cf["hue_full"])), 0.0, 1.0)
	var by_sat := clampf((sat - float(cf["sat_zero"])) / (float(cf["sat_full"]) - float(cf["sat_zero"])), 0.0, 1.0)
	return by_hue * by_sat


## The hue of a colour in degrees.
static func _hue(r: float, g: float, b: float) -> float:
	return Color(r / 255.0, g / 255.0, b / 255.0).h * 360.0


## The thing in its own square with a margin, at the icon's side.
static func _crop(rgba: Image, cf: Dictionary) -> Image:
	var side := rgba.get_width()
	var keep := int(cf["keep"])
	var x0 := side
	var y0 := side
	var x1 := -1
	var y1 := -1
	var data := rgba.get_data()
	for y: int in side:
		for x: int in side:
			if data[(y * side + x) * 4 + 3] > keep:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	var icon := int(cf["side"])
	if x1 < 0:
		rgba.resize(icon, icon, Image.INTERPOLATE_LANCZOS)
		return rgba
	var big := maxi(x1 - x0 + 1, y1 - y0 + 1)
	var sq := maxi(1, roundi(big * (1.0 + 2.0 * float(cf["pad"]))))
	var square := Image.create_empty(sq, sq, false, Image.FORMAT_RGBA8)
	var at := Vector2i(sq / 2 - (x0 + x1 + 1) / 2, sq / 2 - (y0 + y1 + 1) / 2)
	square.blit_rect(rgba, Rect2i(0, 0, side, side), at)
	square.resize(icon, icon, Image.INTERPOLATE_LANCZOS)
	return square
