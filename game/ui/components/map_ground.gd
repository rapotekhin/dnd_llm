class_name MapGround
extends ColorRect
## The ground of a map under MapField: its squares' grounds and things (LayoutGen.grounds, `grounds` of
## data/layouts.json) drawn on a dual grid by map_ground.gdshader, with what the hero does not see darkened smooth.
## It draws behind the field, which lays the tokens, the paths and the marks over it. Close up it takes the sharper
## pictures of `<group>_hi/` (v0.8.4.43.21): twice the side, built the first time the view comes that close.

const GROUND_PX := 512
const PROP_PX := 256
const HI := 2  ## the sharp set's side, times the plain one
const HI_FROM := 0.5  ## a ground's texel over this many screen pixels — its plain picture blurred by the mipmaps
const HI_BACK := 0.4  ## and back under this, so a view on the line does not flicker
const MAX_PROPS := 64  ## the shader's arrays of props
const EDGE_PX := 1024  ## a sheet of the sixteen tiles of a drawn edge
const MAX_SURFACES := 16  ## the shader's arrays of surfaces (v0.8.4.43.29)
const MAX_GROUNDS := 32  ## the grounds of the order: a bit each in the shader's sharp mask, a row of the edge table

static var _arrays: Dictionary = {}  ## the textures of the grounds and of the things, built once: {"ground": …, "props": …}

var _cells := ImageTexture.new()
var _light := ImageTexture.new()
var _size := Vector2i.ZERO
var _light_bytes := PackedByteArray()
var _base := PackedByteArray()  ## the cells as the map's rows draw them, before the things of the room
var _lib: Dictionary = {}
var _hi := false  ## the sharp set is laid


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	color = Color.WHITE
	var m := ShaderMaterial.new()
	m.shader = preload("res://ui/components/map_ground.gdshader")
	material = m


## The squares of `map`: their grounds, their things and how a door turns.
func lay(lib: Dictionary, map: Dictionary) -> void:
	var g: Dictionary = lib["grounds"]
	var order: Array = g["order"]
	var props := prop_ids(lib)
	var w := int(map["w"])
	var h := int(map["h"])
	var keys := LayoutGen.ground_keys(lib, map)
	var grounds := LayoutGen.grounds(lib, map)
	var rows: Array = map["rows"]
	var bytes := PackedByteArray()
	bytes.resize(w * h * 4)
	for y: int in h:
		var line: String = rows[y]
		for x: int in w:
			var i := (y * w + x) * 4
			bytes[i] = grounds[y * w + x]
			var c := line[x] if x < line.length() else LayoutGen.BLANK
			var thing := LayoutGen.prop_at(lib, keys, rows, x, y)
			var prop := props.find(str(thing["id"]))
			bytes[i + 1] = prop + 1
			bytes[i + 2] = int(thing["turn"]) if prop >= 0 else 0
			bytes[i + 3] = 255
	_base = bytes
	_cells.set_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes))
	_size = Vector2i(w, h)
	_light_bytes = PackedByteArray()
	_light_bytes.resize(w * h * 4)
	_light.set_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _light_bytes))
	var sharp := 0
	for id: Variant in g.get("sharp", []):
		var at := order.find(id)
		if at >= 0:
			sharp |= 1 << at
	var sizes := PackedFloat32Array()
	sizes.resize(MAX_PROPS)
	sizes.fill(1.0)
	var dims := PackedVector2Array()
	dims.resize(MAX_PROPS)
	var bodies := bodies_of()
	for i: int in mini(props.size(), MAX_PROPS):
		sizes[i] = float(g.get("size", {}).get(LayoutGen.prop_base(lib, props[i]), 1.0))
		var sz: Array = (bodies.get(props[i], {}) as Dictionary).get("size", [1, 1])
		dims[i] = Vector2(float(sz[0]), float(sz[1]))
	_lib = lib
	var m := material as ShaderMaterial
	m.set_shader_parameter("cells", _cells)
	_surface_params(m)
	m.set_shader_parameter("light", _light)
	_lay_set()
	m.set_shader_parameter("map_size", Vector2(w, h))
	m.set_shader_parameter("repeat_cells", float(g.get("repeat", 3)))
	m.set_shader_parameter("sharp_mask", sharp)
	var kin := PackedInt32Array()  # a ground drawn as another counts as that one where two grounds meet (v0.8.4.43.28)
	for i: int in 32:
		kin.append(order.find(str(g.get("same", {}).get(order[i], order[i]))) if i < order.size() else i)
	m.set_shader_parameter("kin", kin)
	m.set_shader_parameter("ground_move", ground_motion(lib))
	m.set_shader_parameter("prop_size", sizes)
	var shimmer := PackedFloat32Array()  # v0.8.4.43.36: a thing whose picture moves (falling water)
	shimmer.resize(MAX_PROPS)
	for i: int in mini(props.size(), MAX_PROPS):
		shimmer[i] = float(g.get("shimmer", {}).get(LayoutGen.prop_base(lib, props[i]), 0.0))
	m.set_shader_parameter("prop_shimmer", shimmer)
	m.set_shader_parameter("prop_dims", dims)
	m.set_shader_parameter("watch_tint", UiTheme.BAD)
	var edges := _edges(lib)
	m.set_shader_parameter("edges", edges["sheets"])
	m.set_shader_parameter("edge_pairs", edges["pairs"])
	m.set_shader_parameter("edge_cell", edge_cells(lib))
	m.set_shader_parameter("edge_band", float(g.get("edge_band", 0.16)))


## The set of pictures for a square of `tile` pixels: the sharp one when a plain texel takes over half a screen pixel
## (the mipmaps would blend the picture with its halved one there), the plain one again further off.
func detail(tile: float) -> void:
	if _lib.is_empty():
		return
	var texel := tile * float(_lib["grounds"].get("repeat", 3)) / float(GROUND_PX)
	var want := texel > HI_FROM if not _hi else texel > HI_BACK
	if want != _hi and (not want or has_hi(_lib)):
		_hi = want
		_lay_set()


## Whether the sharp set is laid now (a playtest checks the switch).
func sharp() -> bool:
	return _hi


## Whether any sharp picture of a ground is installed: none — the plain set stays at every zoom.
static func has_hi(lib: Dictionary) -> bool:
	if not _arrays.has("has_hi"):
		_arrays["has_hi"] = lib["grounds"]["order"].any(func(id: Variant) -> bool:
			return ResourceLoader.exists("res://assets/tiles/ground_hi/%s.png" % id))
	return bool(_arrays["has_hi"])


func _lay_set() -> void:
	var m := material as ShaderMaterial
	m.set_shader_parameter("grounds", _array(_lib, "ground", _hi))
	m.set_shader_parameter("surfaces", _array(_lib, "surface", _hi))
	m.set_shader_parameter("props", _array(_lib, "props", _hi))


## What the hero does not see now (dimmed by `dark`) and the squares under watch.
func light(dim: bool, now: Dictionary, cones: Dictionary, dark: float) -> void:
	if _size == Vector2i.ZERO:
		return
	var shade := int(dark * 255.0) if dim else 0
	for y: int in _size.y:
		for x: int in _size.x:
			var i := (y * _size.x + x) * 4
			var cell := Vector2i(x, y)
			_light_bytes[i] = 0 if not dim or now.has(cell) else shade
			_light_bytes[i + 1] = 255 if cones.has(cell) else 0
	_light.update(Image.create_from_data(_size.x, _size.y, false, Image.FORMAT_RGBA8, _light_bytes))


## The surfaces lying on the squares now (v0.8.4.43.29): {square: surface id of AnimRules.surface_grounds} — fire, a
## puddle, oil, ice, acid — drawn as the second layer of the dual grid; kept in the light texture's blue (read exact).
func cover(by_square: Dictionary) -> void:
	if _size == Vector2i.ZERO:
		return
	var ids := AnimRules.surface_grounds(Catalog.data)
	for y: int in _size.y:
		for x: int in _size.x:
			_light_bytes[(y * _size.x + x) * 4 + 2] = ids.find(str(by_square.get(Vector2i(x, y), ""))) + 1
	_light.update(Image.create_from_data(_size.x, _size.y, false, Image.FORMAT_RGBA8, _light_bytes))


## How each surface moves: its `flow`, `waver` and `glow` of anims.json `surfaces.layer.grounds`.
func _surface_params(m: ShaderMaterial) -> void:
	var rows: Dictionary = AnimRules.cfg(Catalog.data).get("surfaces", {}).get("layer", {}).get("grounds", {})
	var flow := PackedVector2Array()
	var move := PackedVector2Array()  # x — waver, y — glow
	for id: String in AnimRules.surface_grounds(Catalog.data):
		var row: Dictionary = rows[id]
		var f: Array = row.get("flow", [0, 0])
		flow.append(Vector2(float(f[0]), float(f[1])))
		move.append(Vector2(float(row.get("waver", 0.0)), float(row.get("glow", 0.0))))
	flow.resize(MAX_SURFACES)
	move.resize(MAX_SURFACES)
	m.set_shader_parameter("surface_flow", flow)
	m.set_shader_parameter("surface_move", move)


## The things on the squares of a room (v0.8.4.43.23): each token with a body drawn from above on its squares, kept on its
## top left square with its turn. A thing with no picture keeps its token.
func place(tokens: Array[Dictionary]) -> void:
	if _base.is_empty() or _lib.is_empty():
		return
	var bytes := _base.duplicate()
	var props := prop_ids(_lib)
	for t: Dictionary in tokens:
		var at := props.find(str(t.get("body", "")))
		if at < 0 or not t.has("corner"):
			continue
		var c: Vector2i = t["corner"]
		if c.x < 0 or c.y < 0 or c.x >= _size.x or c.y >= _size.y:
			continue
		var i := (c.y * _size.x + c.x) * 4
		bytes[i + 1] = at + 1
		bytes[i + 2] = int(t.get("turn", 0)) % 4
	_cells.set_image(Image.create_from_data(_size.x, _size.y, false, Image.FORMAT_RGBA8, bytes))


## Whether a body has its picture drawn (assets/tiles/props/<id>.png): a token without one stays a square.
static func drawn(body_id: String) -> bool:
	return not body_id.is_empty() and ResourceLoader.exists("res://assets/tiles/props/%s.png" % body_id)


## The things of the map: the bodies of rules.things (v0.8.4.43.23).
static func bodies_of() -> Dictionary:
	return Catalog.data.get("rules", {}).get("things", {}).get("bodies", {}) if Catalog.data is Dictionary else {}


## How each ground of the order moves (`grounds.motion`, v0.8.4.43.32): xy — drift, z — ripple, w — glow.
static func ground_motion(lib: Dictionary) -> PackedVector4Array:
	var g: Dictionary = lib["grounds"]
	var rows: Dictionary = g.get("motion", {})
	var out := PackedVector4Array()
	for i: int in MAX_GROUNDS:
		var id := str(g["order"][i]) if i < (g["order"] as Array).size() else ""
		var row: Variant = rows.get(id, {})
		var f: Array = (row as Dictionary).get("flow", [0, 0]) if row is Dictionary else [0, 0]
		out.append(Vector4(float(f[0]), float(f[1]), float(row.get("waver", 0.0)) if row is Dictionary else 0.0, float(row.get("glow", 0.0)) if row is Dictionary else 0.0))
	return out


## The things of `grounds.props` and the bodies of the map in one order: a thing's place in the texture of the things.
static func prop_ids(lib: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var strips: Dictionary = lib["grounds"].get("strips", {})
	for row: Variant in lib["grounds"]["props"].values():
		for id: Variant in (row as Dictionary).values():
			var drawn: Array = [str(id)]
			if (strips.get("of", []) as Array).has(id):  # a strip: its parts are drawn, not itself (v0.8.4.43.36)
				drawn = (strips["parts"] as Array).map(func(p: Variant) -> String: return "%s_%s" % [id, p])
			for one: Variant in drawn:
				if not out.has(str(one)):
					out.append(str(one))
	for id: Variant in bodies_of():
		if not out.has(str(id)) and out.size() < MAX_PROPS:
			out.append(str(id))
	return out


## The tile of an edge sheet for each case of four corners (8 TL + 4 TR + 2 BL + BR, 1 — the higher ground): its
## place y * 4 + x among the sixteen windows of `grounds.edge_layout`.
static func edge_cells(lib: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(16)
	var rows: Array = lib["grounds"].get("edge_layout", [])
	if rows.size() < 5:
		return out
	for y: int in 4:
		for x: int in 4:
			var bit := func(dx: int, dy: int) -> int: return int(str(rows[y + dy])[x + dx])
			out[bit.call(0, 0) * 8 + bit.call(1, 0) * 4 + bit.call(0, 1) * 2 + bit.call(1, 1)] = y * 4 + x
	return out


## The drawn edges: a sheet per pair of `grounds.edges` whose picture is laid, and a table of pairs → sheet + 1.
static func _edges(lib: Dictionary) -> Dictionary:
	if _arrays.has("edges"):
		return _arrays["edges"]
	var order: Array = lib["grounds"]["order"]
	var table := Image.create(MAX_GROUNDS, MAX_GROUNDS, false, Image.FORMAT_RGBA8)
	table.fill(Color(0, 0, 0, 0))
	var images: Array[Image] = []
	for pair: Dictionary in lib["grounds"].get("edges", []):
		var path := "res://assets/tiles/edges/%s__%s.png" % [pair["low"], pair["high"]]
		var low := order.find(pair["low"])
		var high := order.find(pair["high"])
		if not ResourceLoader.exists(path) or low < 0 or high < 0 or images.size() >= 255:
			continue
		var img := (load(path) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(EDGE_PX, EDGE_PX, Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		images.append(img)
		# g — the gain of its alpha × 64, b — its band × 255 (v0.8.4.43.28: a cliff painted wider than a shore)
		table.set_pixel(low, high, Color8(images.size(), int(float(pair.get("gain", 2.0)) * 64.0), int(float(pair.get("band", lib["grounds"].get("edge_band", 0.16))) * 255.0), 255))
	if images.is_empty():
		var none := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		none.generate_mipmaps()
		images.append(none)
	var sheets := Texture2DArray.new()
	sheets.create_from_images(images)
	_arrays["edges"] = {"sheets": sheets, "pairs": ImageTexture.create_from_image(table)}
	return _arrays["edges"]


## The textures of a group, a colour where none is drawn yet; `hi` — the sharp set of `<group>_hi/`, the plain picture
## stretched where a sharp one is not drawn.
static func _array(lib: Dictionary, group: String, hi := false) -> Texture2DArray:
	var key := group + ("_hi" if hi else "")
	if _arrays.has(key):
		return _arrays[key]
	var g: Dictionary = lib["grounds"]
	var ids: Array = g["order"] if group == "ground" else AnimRules.surface_grounds(Catalog.data) if group == "surface" else prop_ids(lib)
	var flat := group != "props"  # a ground or a surface: a seamless texture of a ground's size
	var side := (GROUND_PX if flat else PROP_PX) * (HI if hi else 1)
	var folder := "ground" if group == "surface" else group  # a surface's texture lies with the grounds'
	var images: Array[Image] = []
	var same: Dictionary = g.get("same", {}) if group == "ground" else {}
	for raw: Variant in ids:
		var id: String = str(same.get(raw, raw))  # a ground with the texture of another (`grounds.same`, v0.8.4.43.28)
		var path := "res://assets/tiles/%s_hi/%s.png" % [folder, id]
		if not hi or not ResourceLoader.exists(path):
			path = "res://assets/tiles/%s/%s.png" % [folder, id]
		var img: Image
		if ResourceLoader.exists(path):
			img = (load(path) as Texture2D).get_image()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(side, side, Image.INTERPOLATE_LANCZOS)
		else:
			img = Image.create(side, side, false, Image.FORMAT_RGBA8)
			img.fill(Color(str(g.get("colour", {}).get(id, "#00000000"))) if group == "ground" else Color(0, 0, 0, 0))  # a surface not drawn yet: none
		img.generate_mipmaps()
		images.append(img)
	if images.is_empty():
		var none := Image.create(side, side, true, Image.FORMAT_RGBA8)
		images.append(none)
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	_arrays[key] = arr
	return arr
