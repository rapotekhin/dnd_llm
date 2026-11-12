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
const MAX_PROPS := 16
const EDGE_PX := 1024  ## a sheet of the sixteen tiles of a drawn edge
const MAX_GROUNDS := 32  ## the grounds of the order: a bit each in the shader's sharp mask, a row of the edge table

static var _arrays: Dictionary = {}  ## the textures of the grounds and of the things, built once: {"ground": …, "props": …}

var _cells := ImageTexture.new()
var _light := ImageTexture.new()
var _size := Vector2i.ZERO
var _light_bytes := PackedByteArray()
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
			var prop := props.find(LayoutGen.prop_of(lib, keys, c))
			bytes[i + 1] = prop + 1
			bytes[i + 2] = 1 if prop >= 0 and _walled(rows, x - 1, y) and _walled(rows, x + 1, y) else 0
			bytes[i + 3] = 255
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
	for i: int in props.size():
		sizes[i] = float(g.get("size", {}).get(props[i], 1.0))
	_lib = lib
	var m := material as ShaderMaterial
	m.set_shader_parameter("cells", _cells)
	m.set_shader_parameter("light", _light)
	_lay_set()
	m.set_shader_parameter("map_size", Vector2(w, h))
	m.set_shader_parameter("repeat_cells", float(g.get("repeat", 3)))
	m.set_shader_parameter("sharp_mask", sharp)
	m.set_shader_parameter("prop_size", sizes)
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


## The things of `grounds.props` in one order: a thing's place in the texture of the things.
static func prop_ids(lib: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for row: Variant in lib["grounds"]["props"].values():
		for id: Variant in (row as Dictionary).values():
			if not out.has(str(id)):
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
		table.set_pixel(low, high, Color8(images.size(), 0, 0, 255))
	if images.is_empty():
		var none := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		none.generate_mipmaps()
		images.append(none)
	var sheets := Texture2DArray.new()
	sheets.create_from_images(images)
	_arrays["edges"] = {"sheets": sheets, "pairs": ImageTexture.create_from_image(table)}
	return _arrays["edges"]


static func _walled(rows: Array, x: int, y: int) -> bool:
	if y < 0 or y >= rows.size() or x < 0 or x >= (rows[y] as String).length():
		return false
	return (rows[y] as String)[x] in [LayoutGen.WALL, "w", LayoutGen.SOCKET]


## The textures of a group, a colour where none is drawn yet; `hi` — the sharp set of `<group>_hi/`, the plain picture
## stretched where a sharp one is not drawn.
static func _array(lib: Dictionary, group: String, hi := false) -> Texture2DArray:
	var key := group + ("_hi" if hi else "")
	if _arrays.has(key):
		return _arrays[key]
	var g: Dictionary = lib["grounds"]
	var ids: Array = g["order"] if group == "ground" else prop_ids(lib)
	var side := (GROUND_PX if group == "ground" else PROP_PX) * (HI if hi else 1)
	var images: Array[Image] = []
	for id: Variant in ids:
		var path := "res://assets/tiles/%s_hi/%s.png" % [group, id]
		if not hi or not ResourceLoader.exists(path):
			path = "res://assets/tiles/%s/%s.png" % [group, id]
		var img: Image
		if ResourceLoader.exists(path):
			img = (load(path) as Texture2D).get_image()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(side, side, Image.INTERPOLATE_LANCZOS)
		else:
			img = Image.create(side, side, false, Image.FORMAT_RGBA8)
			img.fill(Color(str(g.get("colour", {}).get(id, "#00000000"))) if group == "ground" else Color(0, 0, 0, 0))
		img.generate_mipmaps()
		images.append(img)
	if images.is_empty():
		var none := Image.create(side, side, true, Image.FORMAT_RGBA8)
		images.append(none)
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	_arrays[key] = arr
	return arr
