// The ground of a map on a dual grid (MapGround): the picture of a point is decided by the four squares whose
// centres stand around it, so two grounds meet by a rough line between the centres, not on a square's border.
// A higher ground of `grounds.order` lies over a lower one; a sharp one (a wall) keeps the square's border, with a
// bevel and a shadow on what is south and east of it. Then the things of the squares (a tree overflows its square),
// then what the hero does not see now (`light`, sampled smooth between the squares' centres). A thing of many squares
// (v0.8.4.43.23) is kept on its top left square: its picture, square, spans its long side round the middle of its squares,
// turned by its quarter turns.
// Where only two grounds meet and their pair has a drawn edge (`grounds.edges`), the line and a band round it come
// from that pair's sheet of the sixteen tiles (`edges`, the line in its alpha); inside, the grounds' own textures.
shader_type canvas_item;

uniform sampler2D cells : filter_nearest;  // r — the ground's place in the order (255 none), g — a prop + 1 on its top left square, b — its quarter turns
uniform sampler2D light : filter_linear;   // r — darkness, g — under watch
uniform sampler2DArray grounds : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray props : filter_linear_mipmap;
uniform vec2 map_size = vec2(1.0);
uniform float repeat_cells = 3.0;
uniform int sharp_mask = 0;  // a bit per ground of the order
uniform float prop_size[64];
uniform vec2 prop_dims[64];  // a prop's squares [long, short]; none — one square
uniform float rough = 0.22;
uniform float soft = 0.05;
uniform vec4 watch_tint : source_color = vec4(0.75, 0.25, 0.2, 1.0);
uniform sampler2DArray edges : filter_linear_mipmap;  // a sheet of 4 × 4 tiles per pair, the line in alpha (0.5)
uniform sampler2D edge_pairs : filter_nearest;  // at (lower, higher): r — the pair's sheet + 1, 0 — none
uniform int edge_cell[16];  // the case of the four corners (8 TL + 4 TR + 2 BL + BR, 1 — higher) → its tile y * 4 + x
uniform float edge_band = 0.16;
uniform int edge_px = 1024;  // a sheet's side

ivec2 clamped(ivec2 c) {
	return clamp(c, ivec2(0), ivec2(map_size) - 1);
}

int ground_at(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= int(map_size.x) || c.y >= int(map_size.y)) return -1;
	int g = int(texelFetch(cells, c, 0).r * 255.0 + 0.5);
	return g == 255 ? -1 : g;
}

bool sharp(int g) {
	return g >= 0 && ((sharp_mask >> g) & 1) == 1;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec4 ground(int g, vec2 p) {
	return texture(grounds, vec3(p / repeat_cells, float(g)));
}

void fragment() {
	vec2 p = UV * map_size;
	ivec2 here = ivec2(floor(p));
	int gh = ground_at(here);
	vec2 q = p - 0.5;
	ivec2 i = ivec2(floor(q));
	vec2 f = fract(q);
	int g0 = ground_at(i);
	int g1 = ground_at(i + ivec2(1, 0));
	int g2 = ground_at(i + ivec2(0, 1));
	int g3 = ground_at(i + ivec2(1, 1));
	// the rough line dies out on the display tile's sides: it crosses each side at its middle, as a drawn edge does
	float wobble = (noise(p * 2.7) * 0.65 + noise(p * 7.3) * 0.35 - 0.5) * 2.0 * rough * sqrt(sin(PI * f.x) * sin(PI * f.y));

	int now = min(min(g0, g1), min(g2, g3));
	int top_g = max(max(g0, g1), max(g2, g3));
	bool two = now >= 0 && now != top_g && (g0 == now || g0 == top_g) && (g1 == now || g1 == top_g)
		&& (g2 == now || g2 == top_g) && (g3 == now || g3 == top_g) && !sharp(top_g);
	int layer = two ? int(texelFetch(edge_pairs, ivec2(now, top_g), 0).r * 255.0 + 0.5) - 1 : -1;
	vec4 col = now < 0 ? vec4(0.0) : ground(now, p);
	if (layer >= 0) {  // a drawn edge: the line of the sheet, its painting in a band round it
		int key = int(g0 == top_g) * 8 + int(g1 == top_g) * 4 + int(g2 == top_g) * 2 + int(g3 == top_g);
		int cell = edge_cell[key];
		// the mip by the screen, no deeper than 3, and the point kept inside its own tile by that mip's texel, so
		// filtering never reaches the next tile of the sheet (a different case)
		vec2 at = f * float(edge_px) / 4.0;
		float lod = clamp(log2(max(length(dFdx(at)), length(dFdy(at)))), 0.0, 3.0);
		float inset = exp2(lod) * 1.5 / (float(edge_px) / 4.0);
		vec2 uv = (vec2(float(cell % 4), float(cell / 4)) + clamp(f, vec2(inset), vec2(1.0 - inset))) / 4.0;
		vec4 e = textureLod(edges, vec3(uv, float(layer)), lod);
		float d = (e.a - 0.5) * 0.5;  // how far above the line, as the sheet's own measure
		col = d >= 0.0 ? ground(top_g, p) : col;
		col.rgb = mix(col.rgb, e.rgb, 1.0 - smoothstep(edge_band * 0.6, edge_band, abs(d)));
		col.a = 1.0;
		now = top_g;
	}
	for (int step = 0; step < 4; step++) {
		int k = 999;  // the next ground above `now` among the four
		if (g0 > now) k = min(k, g0);
		if (g1 > now) k = min(k, g1);
		if (g2 > now) k = min(k, g2);
		if (g3 > now) k = min(k, g3);
		if (k == 999) break;
		float a;
		if (sharp(k)) {
			a = gh >= k ? 1.0 : 0.0;
		} else {
			vec4 c = vec4(float(g0 >= k), float(g1 >= k), float(g2 >= k), float(g3 >= k));
			float cov = mix(mix(c.x, c.y, f.x), mix(c.z, c.w, f.x), f.y);
			a = smoothstep(0.5 - soft, 0.5 + soft, cov + wobble * 4.0 * cov * (1.0 - cov));
		}
		vec4 top = ground(k, p);
		col = vec4(mix(col.rgb, top.rgb, a), max(col.a, a));
		now = k;
	}

	vec2 l = fract(p);
	if (sharp(gh)) {  // a wall's bevel towards what is not a wall
		float d = 1.0;
		if (!sharp(ground_at(here + ivec2(0, -1)))) d = min(d, l.y);
		if (!sharp(ground_at(here + ivec2(0, 1)))) d = min(d, 1.0 - l.y);
		if (!sharp(ground_at(here + ivec2(-1, 0)))) d = min(d, l.x);
		if (!sharp(ground_at(here + ivec2(1, 0)))) d = min(d, 1.0 - l.x);
		col.rgb *= mix(0.55, 1.08, smoothstep(0.0, 0.14, d));
	} else if (gh >= 0) {  // the shadow a wall casts south and east
		float s = 0.0;
		if (sharp(ground_at(here + ivec2(0, -1)))) s = max(s, 1.0 - smoothstep(0.0, 0.32, l.y));
		if (sharp(ground_at(here + ivec2(-1, 0)))) s = max(s, 1.0 - smoothstep(0.0, 0.22, l.x));
		col.rgb *= 1.0 - 0.4 * s;
	}

	for (int dy = -3; dy <= 1; dy++) {  // the things of this square and of those around whose squares or overflow reach it
		for (int dx = -3; dx <= 1; dx++) {
			ivec2 n = here + ivec2(dx, dy);
			if (n.x < 0 || n.y < 0 || n.x >= int(map_size.x) || n.y >= int(map_size.y)) continue;
			vec4 cell = texelFetch(cells, n, 0);
			int prop = int(cell.g * 255.0 + 0.5) - 1;
			if (prop < 0) continue;
			int turn = int(cell.b * 255.0 + 0.5);
			vec2 dims = max(prop_dims[prop], vec2(1.0));
			vec2 span = turn % 2 == 1 ? dims.yx : dims;
			float size = prop_size[prop] * max(dims.x, dims.y);
			vec2 at = (p - (vec2(n) + span * 0.5)) / size;
			for (int r = 0; r < turn; r++) at = vec2(-at.y, at.x);
			vec2 uv = at + 0.5;
			vec2 shade_uv = uv - vec2(0.06, 0.08) / size;
			if (shade_uv.x >= 0.0 && shade_uv.y >= 0.0 && shade_uv.x <= 1.0 && shade_uv.y <= 1.0) {
				col.rgb *= 1.0 - 0.38 * texture(props, vec3(shade_uv, float(prop))).a;
			}
			if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
				vec4 t = texture(props, vec3(uv, float(prop)));
				col = vec4(mix(col.rgb, t.rgb, t.a), max(col.a, t.a));
			}
		}
	}

	vec4 lit = texture(light, UV);
	col.rgb = mix(col.rgb, watch_tint.rgb, lit.g * 0.32);
	col.rgb *= 1.0 - lit.r;
	COLOR = col;
}
