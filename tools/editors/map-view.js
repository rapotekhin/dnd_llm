'use strict';
// The map of a chunk or a room for the data editors, drawn as the game draws it: the squares' grounds and things
// by `grounds` of game/data/layouts.json (the same reading as LayoutGen.ground_of / prop_of / grounds and
// MapGround.prop_ids / edge_cells) and the game's own shader game/ui/components/map_ground.gdshader, turned into
// WebGL2 GLSL as it is read, with the textures of game/assets/tiles (a ground's colour where none is drawn).

const MapView = (() => {
	const SHADER = 'game/ui/components/map_ground.gdshader';
	const TILES = 'game/assets/tiles/';
	const GROUND_PX = 512, PROP_PX = 256, EDGE_PX = 1024, MAX_PROPS = 64, MAX_GROUNDS = 32;
	const BLANK = ' ', FLOOR = '.', SOCKET = 'D';

	// LayoutGen.turned: a quarter turn clockwise `rot` times after a mirror.
	function turned(rows, rot, flip) {
		let out = rows.map((r) => (flip ? [...r].reverse().join('') : r));
		for (let i = 0; i < ((rot % 4) + 4) % 4; i++) {
			const w = out[0].length;
			out = Array.from({ length: w }, (_, x) => out.map((r) => r[x]).reverse().join(''));
		}
		return out;
	}

	// LayoutGen.shape_of: a kind's shape, through its family.
	function shapeOf(lib, kind, indoor = true) {
		let k = lib.kinds?.[kind] || {};
		for (let n = 0; !k.shape && k.family && n < 8; n++) k = lib.kinds[k.family] || {};
		return k.shape || (indoor ? 'building' : 'open');
	}

	// The shape a chunk is laid on: a landmark lies on an open map, a room on its kind's.
	function chunkShape(lib, chunk) {
		if (chunk.landmarks || chunk.tile) return 'open';
		return shapeOf(lib, chunk.kinds?.[0] || '', true);
	}

	// LayoutGen.ground_keys: the kind, the kinds of its family, the shape, '*'.
	function groundKeys(lib, kind, shape) {
		const out = [];
		for (let k = kind || ''; k && !out.includes(k); k = lib.kinds?.[k]?.family || '') out.push(k);
		return [...out, shape, '*'];
	}

	const byKeys = (row, keys) => (row && typeof row === 'object' ? String(row[keys.find((k) => k in row)] ?? '') : String(row ?? ''));

	function groundOf(lib, keys, c) {
		const cells = lib.grounds.cells;
		return byKeys(cells[c] ?? cells[FLOOR], keys);
	}

	function propOf(lib, keys, c) {
		return byKeys(lib.grounds.props[c] || {}, keys);
	}

	// MapGround.prop_ids: the things of `grounds.props`, then the bodies of rules.things (v0.8.4.43.24) — a thing's place.
	function propIds(lib, bodies = {}) {
		const out = [];
		for (const row of Object.values(lib.grounds.props)) for (const id of Object.values(row)) if (!out.includes(String(id))) out.push(String(id));
		for (const id of Object.keys(bodies)) if (!out.includes(id) && out.length < MAX_PROPS) out.push(id);
		return out;
	}

	// LayoutGen.turn_cell / turn_offset / turn_of (v0.8.4.43.31): a square, an offset and a thing's turn on a chunk
	// mirrored and turned `rot` quarters clockwise; a thing's picture turns against the clock.
	function turnCell([x, y], w, h, rot, flip) {
		let p = flip ? [w - 1 - x, y] : [x, y], size = [w, h];
		for (let i = 0; i < ((rot % 4) + 4) % 4; i++) { p = [size[1] - 1 - p[1], p[0]]; size = [size[1], size[0]]; }
		return p;
	}
	const turnOf = (turn, rot, flip) => ((((flip ? 2 - turn : turn) - rot) % 4) + 4) % 4;
	// MapSpots.footprint: the squares a thing of `size` [long, short] takes from its top left, `turn` odd — the other way.
	function footprint(size, x, y, turn) {
		const [w, hh] = turn % 2 ? [size[1], size[0]] : [size[0], size[1]];
		const out = [];
		for (let j = 0; j < hh; j++) for (let i = 0; i < w; i++) out.push([x + i, y + j]);
		return out;
	}

	function edgeCells(lib) {
		const out = new Int32Array(16);
		const rows = lib.grounds.edge_layout || [];
		if (rows.length < 5) return out;
		for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) {
			const b = (dx, dy) => Number(rows[y + dy][x + dx]);
			out[b(0, 0) * 8 + b(1, 0) * 4 + b(0, 1) * 2 + b(1, 1)] = y * 4 + x;
		}
		return out;
	}

	// A chunk's rows as the generator stamps them: a mark's letter is floor (LayoutGen._stamp).
	function stamped(rows, marks = {}) {
		return rows.map((r) => [...r].map((c) => (c in marks ? FLOOR : c)).join(''));
	}

	const walled = (rows, x, y) => y >= 0 && y < rows.length && x >= 0 && x < rows[y].length && ['#', 'w', SOCKET].includes(rows[y][x]);

	// The cells texture of MapGround.lay: r — the ground's place in the order (255 none), g — a prop + 1, b — a turn.
	function cellBytes(lib, rows, keys) {
		const order = lib.grounds.order;
		const props = propIds(lib);
		const h = rows.length, w = Math.max(...rows.map((r) => r.length));
		const out = new Uint8Array(w * h * 4);
		const floor = order.indexOf(groundOf(lib, keys, FLOOR));
		for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
			const c = rows[y][x] ?? BLANK;
			const i = (y * w + x) * 4;
			if (c === BLANK) { const g = byKeys(lib.grounds.cells[BLANK], keys); const at = g ? order.indexOf(g) : -1; out[i] = at >= 0 ? at : 255; } // rock in tunnels
			else { const at = order.indexOf(groundOf(lib, keys, c)); out[i] = at >= 0 ? at : floor; }
			const prop = props.indexOf(propOf(lib, keys, c));
			out[i + 1] = prop + 1;
			out[i + 2] = prop >= 0 && walled(rows, x - 1, y) && walled(rows, x + 1, y) ? 1 : 0;
			out[i + 3] = 255;
		}
		return { w, h, bytes: out };
	}

	// map_ground.gdshader → GLSL ES 3.00: the hints and the uniforms' defaults off, fragment() → main().
	function glsl(src) {
		const body = src
			.replace(/^\s*shader_type[^;]*;/m, '')
			.replace(/^(\s*uniform[^;:=]*?)\s*:[^;=]*?(=|;)/gm, '$1 $2')
			.replace(/^(\s*uniform[^;=]*?)\s*=[^;]*;/gm, '$1;')
			.replace(/\bvoid\s+fragment\s*\(\s*\)/, 'void main()')
			.replace(/\bUV\b/g, 'v_uv')
			.replace(/\bCOLOR\s*=/g, 'out_color =');
		return `#version 300 es
precision highp float; precision highp int; precision highp sampler2D; precision highp sampler2DArray;
#define PI 3.14159265358979
#define TIME 0.0
in vec2 v_uv;
out vec4 out_color;
${body}`;
	}

	const VERTEX = `#version 300 es
in vec2 pos;
out vec2 v_uv;
void main() { v_uv = vec2(pos.x * 0.5 + 0.5, 0.5 - pos.y * 0.5); gl_Position = vec4(pos, 0.0, 1.0); }`;

	let shaderText = null;
	const pics = new Map();  // a texture path → an ImageBitmap or null, shared by every view

	async function picture(store, path, side) {
		const key = path + '@' + side;
		if (pics.has(key)) return pics.get(key);
		const p = (async () => {
			const blob = await store.blob?.(path).catch(() => null);
			if (!blob) return null;
			return await createImageBitmap(blob, { resizeWidth: side, resizeHeight: side, resizeQuality: 'high', premultiplyAlpha: 'none', colorspaceConversion: 'none' }).catch(() => null);
		})();
		pics.set(key, p);
		return p;
	}

	function solid(side, colour) {
		const c = new OffscreenCanvas(side, side);
		const g = c.getContext('2d');
		g.fillStyle = colour || '#00000000';
		if (colour) g.fillRect(0, 0, side, side);
		return c;
	}

	// A thing's picture (game/assets/tiles/props/<id>.png) for the editor's own drawing; null — not drawn yet.
	const thingPic = (store, id) => picture(store, `${TILES}props/${id}.png`, PROP_PX);
	// A ground's picture, through `grounds.same` (v0.8.4.43.28); null — none, its colour then.
	const groundPic = (store, lib, id) => picture(store, `${TILES}ground/${lib.grounds.same?.[id] || id}.png`, GROUND_PX);

	// One view: a canvas that draws `rows` of a lib; `draw(rows, shape)` again after an edit. `bodies` — rules.things.bodies:
	// the things of a chunk's furnishings drawn as the game draws them (v0.8.4.43.31).
	class View {
		constructor(store, lib, bodies = {}) {
			this.store = store;
			this.lib = lib;
			this.bodies = bodies;
			this.canvas = document.createElement('canvas');
			this.canvas.className = 'mapview';
			this.ready = this.init().catch((e) => { this.failed = e.message; });
		}

		async init() {
			shaderText ??= await this.store.read(SHADER).catch(() => null);
			if (!shaderText) throw new Error(`нет ${SHADER}: откройте корень репозитория`);
			const gl = (this.gl = this.canvas.getContext('webgl2', { premultipliedAlpha: false, preserveDrawingBuffer: true }));
			if (!gl) throw new Error('браузер без WebGL2');
			const prog = gl.createProgram();
			for (const [type, src] of [[gl.VERTEX_SHADER, VERTEX], [gl.FRAGMENT_SHADER, glsl(shaderText)]]) {
				const s = gl.createShader(type);
				gl.shaderSource(s, src);
				gl.compileShader(s);
				if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error('шейдер: ' + gl.getShaderInfoLog(s));
				gl.attachShader(prog, s);
			}
			gl.bindAttribLocation(prog, 0, 'pos');
			gl.linkProgram(prog);
			if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error('шейдер: ' + gl.getProgramInfoLog(prog));
			this.prog = prog;
			gl.useProgram(prog);
			const buf = gl.createBuffer();
			gl.bindBuffer(gl.ARRAY_BUFFER, buf);
			gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
			gl.enableVertexAttribArray(0);
			gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
			gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
			gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, gl.NONE);
			const g = this.lib.grounds;
			const order = g.order;
			const props = (this.props = propIds(this.lib, this.bodies));
			this.units = {};
			this.array('grounds', 0, GROUND_PX, await Promise.all(order.map(async (id) => (await groundPic(this.store, this.lib, id)) || solid(GROUND_PX, g.colour?.[id]))), true);
			this.array('props', 1, PROP_PX, await Promise.all(props.map(async (id) => (await picture(this.store, `${TILES}props/${id}.png`, PROP_PX)) || solid(PROP_PX, null))), false);
			const sheets = [], table = new Uint8Array(MAX_GROUNDS * MAX_GROUNDS * 4);
			for (const pair of g.edges || []) {
				const low = order.indexOf(pair.low), high = order.indexOf(pair.high);
				const pic = low >= 0 && high >= 0 ? await picture(this.store, `${TILES}edges/${pair.low}__${pair.high}.png`, EDGE_PX) : null;
				if (!pic) continue;
				sheets.push(pic);
				const i = (high * MAX_GROUNDS + low) * 4;
				table[i] = sheets.length; table[i + 3] = 255;
			}
			this.array('edges', 2, sheets.length ? EDGE_PX : 4, sheets.length ? sheets : [solid(4, null)], false);
			this.tex2d('edge_pairs', 3, MAX_GROUNDS, MAX_GROUNDS, table, gl.NEAREST);
			this.tex2d('light', 4, 1, 1, new Uint8Array(4), gl.LINEAR);
			const sharp = (g.sharp || []).reduce((m, id) => (order.includes(id) ? m | (1 << order.indexOf(id)) : m), 0);
			const sizes = new Float32Array(MAX_PROPS).fill(1);
			const dims = new Float32Array(MAX_PROPS * 2).fill(1);
			props.forEach((id, i) => {
				if (i >= MAX_PROPS) return;
				sizes[i] = Number(g.size?.[id] ?? 1);
				const sz = this.bodies[id]?.size || [1, 1];
				dims[i * 2] = Number(sz[0]); dims[i * 2 + 1] = Number(sz[1]);
			});
			const kin = new Int32Array(MAX_GROUNDS).map((_, i) => (i < order.length ? Math.max(0, order.indexOf(g.same?.[order[i]] || order[i])) : i));
			const u = (n) => gl.getUniformLocation(prog, n);
			gl.uniform2fv(u('prop_dims'), dims);
			gl.uniform1iv(u('kin'), kin);
			gl.uniform1f(u('repeat_cells'), Number(g.repeat ?? 3));
			gl.uniform1i(u('sharp_mask'), sharp);
			gl.uniform1fv(u('prop_size'), sizes);
			gl.uniform1f(u('rough'), 0.22);
			gl.uniform1f(u('soft'), 0.05);
			gl.uniform4f(u('watch_tint'), 0.75, 0.25, 0.2, 1);
			gl.uniform1iv(u('edge_cell'), edgeCells(this.lib));
			gl.uniform1f(u('edge_band'), Number(g.edge_band ?? 0.16));
			gl.uniform1i(u('edge_px'), EDGE_PX);
			this.cells = gl.createTexture();
			this.drawn = sheets.length;
		}

		array(name, unit, side, images, repeat) {
			const gl = this.gl;
			const t = gl.createTexture();
			gl.activeTexture(gl.TEXTURE0 + unit);
			gl.bindTexture(gl.TEXTURE_2D_ARRAY, t);
			gl.texStorage3D(gl.TEXTURE_2D_ARRAY, Math.floor(Math.log2(side)) + 1, gl.RGBA8, side, side, images.length);
			images.forEach((img, i) => gl.texSubImage3D(gl.TEXTURE_2D_ARRAY, 0, 0, 0, i, side, side, 1, gl.RGBA, gl.UNSIGNED_BYTE, img));
			gl.generateMipmap(gl.TEXTURE_2D_ARRAY);
			gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
			gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
			const wrap = repeat ? gl.REPEAT : gl.CLAMP_TO_EDGE;
			gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, wrap);
			gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, wrap);
			gl.uniform1i(gl.getUniformLocation(this.prog, name), unit);
		}

		tex2d(name, unit, w, h, bytes, filter, tex) {
			const gl = this.gl;
			const t = tex || gl.createTexture();
			gl.activeTexture(gl.TEXTURE0 + unit);
			gl.bindTexture(gl.TEXTURE_2D, t);
			gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
			gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, bytes);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
			gl.uniform1i(gl.getUniformLocation(this.prog, name), unit);
			return t;
		}

		// `rows` with marks already stamped as floor, `keys` — groundKeys of the place; `px` — a square's side on screen;
		// `grounds` — the squares' grounds as the game counted them (LayoutGen.grounds with its patches), when known;
		// `things` — [{body, x, y, turn}] at their top left squares (MapGround.place).
		async draw(rows, keys, px, grounds = null, things = []) {
			await this.ready;
			if (this.failed || !rows.length) return;
			const gl = this.gl;
			const m = cellBytes(this.lib, rows, keys);
			if (grounds) grounds.forEach((g, i) => { m.bytes[i * 4] = g; });
			for (const t of things) {
				const at = this.props.indexOf(t.body);
				if (at < 0 || t.x < 0 || t.y < 0 || t.x >= m.w || t.y >= m.h) continue;
				const i = (t.y * m.w + t.x) * 4;
				m.bytes[i + 1] = at + 1;
				m.bytes[i + 2] = (t.turn || 0) % 4;
			}
			const dpr = window.devicePixelRatio || 1;
			this.canvas.width = Math.round(m.w * px * dpr);
			this.canvas.height = Math.round(m.h * px * dpr);
			this.canvas.style.width = m.w * px + 'px';
			this.canvas.style.height = m.h * px + 'px';
			gl.useProgram(this.prog);
			this.tex2d('cells', 5, m.w, m.h, m.bytes, gl.NEAREST, this.cells);
			gl.uniform2f(gl.getUniformLocation(this.prog, 'map_size'), m.w, m.h);
			gl.viewport(0, 0, this.canvas.width, this.canvas.height);
			gl.clearColor(0, 0, 0, 0);
			gl.clear(gl.COLOR_BUFFER_BIT);
			gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
		}
	}

	return { View, turned, shapeOf, chunkShape, groundKeys, groundOf, propOf, propIds, edgeCells, stamped, cellBytes, glsl, turnCell, turnOf, footprint,
		thingPic, groundPic, BLANK, FLOOR, SOCKET };
})();
