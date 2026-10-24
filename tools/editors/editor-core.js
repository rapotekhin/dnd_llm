// Shared core of tools/editors (assets.html, world.html): format-keeping JSON, file stores, the entry form,
// a JSON Schema subset and the app shell. Plain browser JS, no build step.
'use strict';

/* ---------------- format-keeping JSON ---------------- */

const Fmt = (() => {
	// Parses JSON and keeps each value's source span and the whitespace around members, so a save can reuse it.
	function parse(text) {
		let i = 0;
		const fail = (m) => { throw new SyntaxError(`JSON: ${m} (символ ${i})`); };
		const ws = () => { const s = i; while (i < text.length && ' \t\r\n'.includes(text[i])) i++; return text.slice(s, i); };
		const str = () => {
			const s = i++;
			while (text[i] !== '"') { if (text[i] === '\\') i++; i++; if (i >= text.length) fail('строка не закрыта'); }
			i++;
			return JSON.parse(text.slice(s, i));
		};
		const num = /-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null/y;
		function value() {
			const start = i, c = text[i];
			if (c === '{' || c === '[') {
				const obj = c === '{', closeCh = obj ? '}' : ']';
				i++;
				const list = [], val = obj ? {} : [];
				let gap = ws();
				if (text[i] === closeCh) { i++; return { t: obj ? 'o' : 'a', start, end: i, list, close: gap, val }; }
				for (;;) {
					let key = null;
					if (obj) {
						if (text[i] !== '"') fail('ожидался ключ');
						key = str(); ws();
						if (text[i] !== ':') fail('ожидалось :');
						i++; ws();
					}
					const v = value();
					const after = ws();
					list.push({ key, gap, v });
					if (obj) val[key] = v.val; else val.push(v.val);
					if (text[i] === ',') { i++; gap = ws(); continue; }
					if (text[i] === closeCh) { i++; return { t: obj ? 'o' : 'a', start, end: i, list, close: after, val }; }
					fail(`ожидалось , или ${closeCh}`);
				}
			}
			if (c === '"') { const v = str(); return { t: 's', start, end: i, val: v }; }
			num.lastIndex = i;
			const m = num.exec(text);
			if (!m) fail('неизвестное значение');
			i += m[0].length;
			return { t: 's', start, end: i, val: JSON.parse(m[0]) };
		}
		const lead = ws();
		const root = value();
		const tail = text.slice(i);
		if (tail.trim()) fail('лишний текст после JSON');
		return { root, lead, tail };
	}

	const kind = (v) => (v === null || typeof v !== 'object' ? 's' : Array.isArray(v) ? 'a' : 'o');

	function equal(a, b) {
		if (a === b) return true;
		const ka = kind(a);
		if (ka === 's' || ka !== kind(b)) return false;
		if (ka === 'a') return a.length === b.length && a.every((x, j) => equal(x, b[j]));
		const ia = Object.keys(a), ib = Object.keys(b);
		return ia.length === ib.length && ia.every((k, j) => k === ib[j] && equal(a[k], b[k]));
	}

	// A sibling is a usable layout template only when it has about the same shape.
	function similar(node, v) {
		if (!node || node.t !== kind(v)) return false;
		if (node.t === 'a') return !node.list.length || !v.length || kind(node.list[0].v.val) === kind(v[0]);
		if (node.t !== 'o') return true;
		const ks = Object.keys(v);
		if (!ks.length || !node.list.length) return true;
		const have = new Set(node.list.map((m) => m.key));
		return ks.filter((k) => have.has(k)).length * 2 >= ks.length;
	}

	function inlineDefault(v, compact) {
		if (!compact) return false;
		const s = JSON.stringify(v);
		const flat = (Array.isArray(v) ? v : Object.values(v)).every((x) => kind(x) === 's');
		return (flat && s.length <= 100) || s.length <= 70;
	}

	function render(v, node, src, depth, compact) {
		if (node && node.t !== kind(v)) node = null;
		if (node && equal(v, node.val)) return src.slice(node.start, node.end);
		const k = kind(v);
		if (k === 's') return JSON.stringify(v);
		const isObj = k === 'o';
		const entries = isObj ? Object.keys(v).map((key) => [key, v[key]]) : v.map((x, j) => [j, x]);
		if (!entries.length) return isObj ? '{}' : '[]';
		const olds = node ? node.list : [];
		const multi = olds.length ? src.slice(node.start, node.end).includes('\n') : !inlineDefault(v, compact);
		const pad = '\t'.repeat(depth + 1);
		const nlGap = [...olds].reverse().find((m) => m.gap.includes('\n'))?.gap ?? '\n' + pad;
		const firstGap = olds.length ? olds[0].gap : multi ? '\n' + pad : '';
		const otherGap = multi ? nlGap : ' ';
		const close = olds.length ? node.close : multi ? '\n' + '\t'.repeat(depth) : '';
		const byKey = new Map(olds.map((m, j) => [m.key, j]));
		const used = new Set();
		let prev = null;
		const parts = entries.map(([key, x], idx) => {
			let j = -1, tpl = null;
			if (isObj) {
				j = byKey.has(key) ? byKey.get(key) : -1;
				tpl = j >= 0 ? olds[j].v : similar(prev, x) ? prev : null;
			} else {
				if (idx < olds.length && !used.has(idx) && equal(x, olds[idx].v.val)) j = idx;
				else j = olds.findIndex((m, n) => !used.has(n) && equal(x, m.v.val));
				if (j >= 0) used.add(j);
				const near = olds[Math.min(idx, olds.length - 1)]?.v;
				tpl = j >= 0 ? olds[j].v : similar(near, x) ? near : null;
			}
			const gap = idx === 0 ? firstGap : j > 0 ? olds[j].gap : otherGap;
			const body = render(x, tpl, src, depth + 1, compact);
			prev = tpl || null;
			return gap + (isObj ? JSON.stringify(key) + ': ' : '') + body;
		});
		return (isObj ? '{' : '[') + parts.join(',') + close + (isObj ? '}' : ']');
	}

	// A loaded file: text as on disk, its parse tree, the live value and its line ending.
	function load(text) {
		const eol = text.includes('\r\n') ? '\r\n' : '\n';
		const norm = text.replace(/\r\n/g, '\n');
		const tree = parse(norm);
		const pretty = JSON.stringify(tree.root.val, null, '\t') === norm.trim();
		return { text, norm, tree, eol, compact: !pretty, data: structuredClone(tree.root.val) };
	}

	function dump(f) {
		const body = f.tree.lead + render(f.data, f.tree.root, f.norm, 0, f.compact) + f.tree.tail;
		return f.eol === '\n' ? body : body.replace(/\n/g, f.eol);
	}

	function fresh(value) {
		return JSON.stringify(value, null, '\t') + '\n';
	}

	return { parse, load, dump, fresh, equal, kind };
})();

/* ---------------- file stores ---------------- */

// Every store speaks repo-relative paths ("game/data/items.json"); `mount` is where the opened folder sits.
function detectMount(names, folderName) {
	if (names.includes('game') && names.includes('tools')) return '';
	if (names.includes('srd') || names.includes('worlds') || names.includes('rules.json')) return 'game/data/';
	if (names.includes('pack.json')) return `game/data/worlds/${folderName}/`;
	if (names.includes('pack.schema.json')) return 'game/data/worlds/';
	return null;
}

class DirStore {
	constructor(handle, mount) { this.handle = handle; this.mount = mount; this.kind = 'dir'; this.label = handle.name; }
	rel(path) { return path.startsWith(this.mount) ? path.slice(this.mount.length) : null; }
	async dir(parts, create) {
		let d = this.handle;
		for (const p of parts) d = await d.getDirectoryHandle(p, { create });
		return d;
	}
	async read(path) {
		const r = this.rel(path);
		if (r === null) return null;
		const parts = r.split('/');
		try {
			const d = await this.dir(parts.slice(0, -1), false);
			return await (await (await d.getFileHandle(parts.at(-1))).getFile()).text();
		} catch (e) { if (e.name === 'NotFoundError' || e.name === 'TypeMismatchError') return null; throw e; }
	}
	async write(path, text) {
		const r = this.rel(path);
		if (r === null) throw new Error(`${path} вне открытой папки`);
		const parts = r.split('/');
		const d = await this.dir(parts.slice(0, -1), true);
		const w = await (await d.getFileHandle(parts.at(-1), { create: true })).createWritable();
		await w.write(text);
		await w.close();
	}
	async list(path) {
		const r = this.rel(path.endsWith('/') ? path : path + '/');
		if (r === null) return this.mount.startsWith(path + '/') ? [this.mount.slice(path.length + 1).split('/')[0]] : [];
		try {
			const d = await this.dir(r.split('/').filter(Boolean), false);
			const out = [];
			for await (const [name, h] of d.entries()) if (h.kind === 'directory') out.push(name);
			return out.sort();
		} catch { return []; }
	}
	canWrite(path) { return this.rel(path) !== null; }
}

// tools/editors/serve.py: GET files, PUT json under game/data and tools/srd, /__list for folders.
class HttpStore {
	constructor() { this.mount = ''; this.kind = 'http'; this.label = location.host; }
	async read(path) {
		const r = await fetch('/' + path, { cache: 'no-store' });
		if (r.status === 404) return null;
		if (!r.ok) throw new Error(`${path}: ${r.status}`);
		return await r.text();
	}
	async write(path, text) {
		const r = await fetch('/' + path, { method: 'PUT', body: text, headers: { 'Content-Type': 'application/json; charset=utf-8' } });
		if (!r.ok) throw new Error(`${path}: ${r.status} ${await r.text()}`);
	}
	async list(path) {
		const r = await fetch('/__list?dir=' + encodeURIComponent(path), { cache: 'no-store' });
		return r.ok ? await r.json() : [];
	}
	canWrite() { return true; }
}

// Files picked with <input webkitdirectory>: read-only, a save downloads the edited file.
class FileListStore {
	constructor(files) {
		this.kind = 'files';
		this.files = new Map();
		const root = files[0]?.webkitRelativePath.split('/')[0] || '';
		this.label = root;
		for (const f of files) this.files.set(f.webkitRelativePath.split('/').slice(1).join('/'), f);
		const top = [...new Set([...this.files.keys()].map((p) => p.split('/')[0]))];
		this.mount = detectMount(top, root);
	}
	rel(path) { return this.mount !== null && path.startsWith(this.mount) ? path.slice(this.mount.length) : null; }
	async read(path) { const f = this.files.get(this.rel(path)); return f ? await f.text() : null; }
	async write(path, text) {
		const a = document.createElement('a');
		a.href = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
		a.download = path.split('/').at(-1);
		a.click();
		setTimeout(() => URL.revokeObjectURL(a.href), 5000);
	}
	async list(path) {
		const r = this.rel(path.endsWith('/') ? path : path + '/');
		if (r === null) return this.mount?.startsWith(path + '/') ? [this.mount.slice(path.length + 1).split('/')[0]] : [];
		const out = new Set();
		for (const p of this.files.keys()) if (p.startsWith(r)) { const rest = p.slice(r.length).split('/'); if (rest.length > 1) out.add(rest[0]); }
		return [...out].sort();
	}
	canWrite(path) { return this.rel(path) !== null; }
}

const HandleDB = {
	open() {
		return new Promise((ok, bad) => {
			const r = indexedDB.open('btr-editors', 1);
			r.onupgradeneeded = () => r.result.createObjectStore('h');
			r.onsuccess = () => ok(r.result);
			r.onerror = () => bad(r.error);
		});
	},
	async get(key) {
		try {
			const db = await this.open();
			return await new Promise((ok) => { const q = db.transaction('h').objectStore('h').get(key); q.onsuccess = () => ok(q.result); q.onerror = () => ok(null); });
		} catch { return null; }
	},
	async set(key, val) {
		try {
			const db = await this.open();
			db.transaction('h', 'readwrite').objectStore('h').put(val, key);
		} catch { /* a private window: the folder is picked again next time */ }
	},
};

/* ---------------- JSON Schema subset ---------------- */

// The keywords pack.schema.json uses; draft 2020-12 semantics.
function schemaErrors(schema, value, rootSchema = schema, path = [], out = []) {
	if (schema === true || schema == null) return out;
	const at = path.join('.');
	const push = (m) => out.push({ path: [...path], msg: `${at || '(корень)'}: ${m}` });
	if (schema.$ref) {
		const def = schema.$ref.replace(/^#\//, '').split('/').reduce((o, k) => o?.[k], rootSchema);
		schemaErrors(def, value, rootSchema, path, out);
	}
	const t = value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
	if (schema.type) {
		const types = [].concat(schema.type);
		const ok = types.some((x) => x === t || (x === 'integer' && Number.isInteger(value)) || (x === 'number' && t === 'number'));
		if (!ok) { push(`ожидался тип ${types.join('|')}, а здесь ${t}`); return out; }
	}
	if ('const' in schema && !Fmt.equal(schema.const, value)) push(`должно быть ${JSON.stringify(schema.const)}`);
	if (schema.enum && !schema.enum.some((x) => Fmt.equal(x, value))) push(`одно из: ${schema.enum.join(', ')}`);
	if (t === 'string') {
		if (schema.minLength && value.length < schema.minLength) push('не может быть пустым');
		if (schema.pattern && !new RegExp(schema.pattern, 'u').test(value)) push(`не подходит под шаблон ${schema.pattern}`);
	}
	if (t === 'number') {
		if (schema.minimum != null && value < schema.minimum) push(`не меньше ${schema.minimum}`);
		if (schema.maximum != null && value > schema.maximum) push(`не больше ${schema.maximum}`);
	}
	if (t === 'array') {
		if (schema.minItems && value.length < schema.minItems) push(`минимум элементов: ${schema.minItems}`);
		if (schema.items) value.forEach((x, j) => schemaErrors(schema.items, x, rootSchema, [...path, j], out));
	}
	if (t === 'object') {
		for (const r of schema.required || []) if (!(r in value)) push(`нет обязательного поля ${r}`);
		if (schema.minProperties && Object.keys(value).length < schema.minProperties) push(`минимум полей: ${schema.minProperties}`);
		const props = schema.properties || {};
		for (const [k, x] of Object.entries(value)) {
			if (k in props) schemaErrors(props[k], x, rootSchema, [...path, k], out);
			else if (schema.additionalProperties === false) push(`лишнее поле ${k}`);
			else if (typeof schema.additionalProperties === 'object') schemaErrors(schema.additionalProperties, x, rootSchema, [...path, k], out);
		}
	}
	for (const s of schema.allOf || []) schemaErrors(s, value, rootSchema, path, out);
	if (schema.anyOf && !schema.anyOf.some((s) => !schemaErrors(s, value, rootSchema, path, []).length)) push('не подходит ни под один вариант');
	if (schema.oneOf && schema.oneOf.filter((s) => !schemaErrors(s, value, rootSchema, path, []).length).length !== 1) push('должно подходить ровно под один вариант');
	return out;
}

/* ---------------- helpers ---------------- */

const h = (tag, attrs = {}, ...kids) => {
	const el = document.createElement(tag);
	for (const [k, v] of Object.entries(attrs)) {
		if (v == null || v === false) continue;
		if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
		else if (k === 'class') el.className = v;
		else if (k === 'html') el.innerHTML = v;
		else if (k === 'value') el.value = v;
		else if (k in el && typeof v !== 'string') el[k] = v;
		else el.setAttribute(k, v === true ? '' : v);
	}
	for (const kid of kids.flat()) if (kid != null && kid !== false) el.append(kid.nodeType ? kid : String(kid));
	return el;
};

function getAt(obj, path) { return path.reduce((o, k) => (o == null ? undefined : o[k]), obj); }

function blank(v) {
	switch (Fmt.kind(v)) {
		case 'a': return [];
		case 'o': return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, blank(x)]));
		default: return typeof v === 'string' ? '' : typeof v === 'number' ? 0 : typeof v === 'boolean' ? false : null;
	}
}

// Path pattern match: "*" one segment, "**" any number, "[]" an array index, "{}" a key of a map.
function matchPath(pattern, segs) {
	if (pattern === '') return !segs.length;
	const p = pattern.split('.');
	const go = (i, j) => {
		if (i === p.length) return j === segs.length;
		if (p[i] === '**') return go(i + 1, j) || (j < segs.length && go(i, j + 1));
		if (j === segs.length) return false;
		return (p[i] === '*' || p[i] === segs[j]) && go(i + 1, j + 1);
	};
	return go(0, 0);
}

function normSegs(path) { return path.map((k) => (typeof k === 'number' ? '[]' : k)); }

function lineDiff(a, b) {
	const A = a.split('\n'), B = b.split('\n');
	let s = 0;
	while (s < A.length && s < B.length && A[s] === B[s]) s++;
	let e = 0;
	while (e < A.length - s && e < B.length - s && A[A.length - 1 - e] === B[B.length - 1 - e]) e++;
	const x = A.slice(s, A.length - e), y = B.slice(s, B.length - e);
	const out = [];
	const ctx = (from, to) => { for (let i = Math.max(0, from); i < to; i++) out.push(['  ', A[i], i + 1]); };
	ctx(s - 3, s);
	if (x.length * y.length > 4e6) {
		x.forEach((l) => out.push(['- ', l])); y.forEach((l) => out.push(['+ ', l]));
	} else {
		const n = x.length, m = y.length, L = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
		for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) L[i][j] = x[i] === y[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
		let i = 0, j = 0;
		while (i < n || j < m) {
			if (i < n && j < m && x[i] === y[j]) { out.push(['  ', x[i]]); i++; j++; }
			else if (i < n && (j === m || L[i + 1][j] >= L[i][j + 1])) out.push(['- ', x[i++]]);
			else out.push(['+ ', y[j++]]);
		}
	}
	ctx(A.length - e, Math.min(A.length, A.length - e + 3));
	// Collapse long unchanged runs between changes.
	const keep = out.map((r, k) => r[0] !== '  ' || out.slice(Math.max(0, k - 3), k + 4).some((q) => q[0] !== '  '));
	return out.map((r, k) => (keep[k] ? r[0] + r[1] : k > 0 && keep[k - 1] ? '  ⋯' : null)).filter((l) => l !== null).join('\n');
}

/* ---------------- labels ---------------- */

const LABELS = {
	name: 'название', name_en: 'название (англ.)', desc: 'описание', description: 'описание', title: 'заголовок',
	level: 'уровень', school: 'школа', school_id: 'школа (id)', casting_time: 'время накладывания', range: 'дистанция',
	duration: 'длительность', components: 'компоненты', concentration: 'концентрация', ritual: 'ритуал', classes: 'классы',
	subclasses: 'подклассы', damage_type: 'вид урона', save: 'спасбросок', attack: 'атака', area: 'область',
	item_type: 'тип вещи', rarity: 'редкость', value_cp: 'цена, мм', weight: 'вес, фнт', properties: 'свойства',
	attunement: 'настройка', stack: 'складывается', weapon: 'оружие', armor: 'доспех', use: 'применение', charges: 'заряды',
	look: 'вид неопознанной', base: 'основа', tool: 'инструмент', size: 'размер', type: 'тип', cr: 'ПО', xp: 'опыт',
	ac: 'КД', hp: 'хиты', hit_dice: 'кости хитов', speed: 'скорость', fly: 'полёт', swim: 'плавание', darkvision: 'тёмное зрение',
	abilities: 'характеристики', saves: 'спасброски', skills: 'навыки', actions: 'действия', traits: 'особенности',
	reactions: 'реакции', multiattack: 'мультиатака', languages: 'языки', resistances: 'сопротивления', immunities: 'иммунитеты',
	vulnerabilities: 'уязвимости', condition_immunities: 'иммунитет к состояниям', class: 'класс', subclass: 'подкласс',
	hit_die: 'кость хитов', race: 'раса', subraces: 'подрасы', ability_bonuses: 'бонусы характеристик', features: 'умения',
	location_id: 'локация', exits: 'выходы', npcs: 'NPC', hooks: 'зацепки', secrets: 'тайны', encounter: 'встреча',
	enemies: 'враги', allies: 'союзники', waves: 'волны', help: 'подмога', loot: 'добыча', open_edges: 'открытые края',
	closed_exits: 'закрытые выходы', variants: 'варианты по флагам', safe: 'безопасный отдых', tags: 'метки', dark: 'темно',
	indoor: 'в помещении', role: 'роль', gender: 'пол', personality: 'характер', trader: 'торговец', stock: 'товар',
	wants: 'охотно покупает', shuns: 'не покупает', purse_cp: 'кошелёк, мм', monster: 'шаблон-монстр', schedule: 'расписание',
	services: 'услуги', heir: 'наследник', giver: 'заказчик', offer_text: 'текст предложения', offer_items: 'выдаёт вещи',
	steps: 'шаги', when: 'условие', action: 'кнопка', done_text: 'итог (для мастера)', reward_cp: 'награда, мм', major: 'опасное',
	settlement: 'поселение', law: 'закон', terrain: 'местность', lit: 'освещено', summary: 'кратко', story: 'история', choices: 'выбор',
	count: 'число', col: 'колонка', id: 'id', text: 'текст', dc: 'СЛ', skill: 'навык', trap: 'ловушка', round: 'раунд', side: 'сторона',
};

/* ---------------- the app ---------------- */

class EditorApp {
	constructor(cfg) {
		this.cfg = cfg;
		this.store = null;
		this.files = new Map();
		this.colls = [];
		this.cur = null;
		this.filters = {};
		this.query = '';
		this.sort = '';
		this.snap = null;
		this.errors = [];
		this.root = document.getElementById('app');
		this.shell();
		addEventListener('hashchange', () => this.fromHash());
		addEventListener('beforeunload', (e) => { if (this.dirtyFiles().length) { e.preventDefault(); e.returnValue = ''; } });
		this.autoOpen();
	}

	/* ----- opening ----- */

	async autoOpen() {
		if (location.protocol.startsWith('http')) {
			try {
				const r = await fetch('/__list?dir=game/data', { cache: 'no-store' });
				if (r.ok) return this.useStore(new HttpStore());
			} catch { /* a plain static server: pick a folder */ }
		}
		const saved = await HandleDB.get(this.cfg.key);
		if (saved) {
			this.el.reopen.hidden = false;
			this.el.reopen.textContent = `Открыть снова: ${saved.name}`;
			this.el.reopen.onclick = async () => {
				if ((await saved.requestPermission({ mode: 'readwrite' })) === 'granted') this.useHandle(saved);
			};
		}
		this.welcome();
	}

	async pickFolder() {
		if (!window.showDirectoryPicker) {
			this.toast('Этот браузер не умеет открывать папку на запись: выберите её через «Открыть только для чтения», правки скачаются файлами.');
			return;
		}
		try {
			const handle = await showDirectoryPicker({ id: 'btr-data', mode: 'readwrite' });
			await HandleDB.set(this.cfg.key, handle);
			await this.useHandle(handle);
		} catch (e) { if (e.name !== 'AbortError') this.toast(e.message); }
	}

	async useHandle(handle) {
		const names = [];
		for await (const [name] of handle.entries()) names.push(name);
		const mount = detectMount(names, handle.name);
		if (mount === null) return this.toast('Это не папка игры: откройте корень репозитория, game/data или папку пакета мира.');
		await this.useStore(new DirStore(handle, mount));
	}

	async useStore(store, { force = false } = {}) {
		if (store.mount === null) return this.toast('Это не папка игры: откройте корень репозитория, game/data или папку пакета мира.');
		if (!force && this.dirtyFiles().length && !confirm('Есть несохранённые правки. Открыть другую папку и потерять их?')) return;
		this.store = store;
		this.files.clear();
		this.el.main.replaceChildren(h('p', { class: 'muted' }, 'Загрузка данных…'));
		try {
			await this.cfg.load(this);
		} catch (e) {
			console.error(e);
			return this.toast('Не удалось загрузить данные: ' + e.message);
		}
		this.el.where.textContent = `${store.kind === 'files' ? 'только чтение: ' : ''}${store.label}${store.mount ? ' → ' + store.mount : ''}`;
		try {
			this.reindex();
			this.renderNav();
			if (!this.fromHash()) this.openColl(this.colls.find((c) => !c.hidden && c.entries().length)?.id);
		} catch (e) {
			console.error(e);
			this.toast('Ошибка страницы: ' + e.message);
		}
	}

	async readFile(path, { optional = false } = {}) {
		if (this.files.has(path)) return this.files.get(path);
		const text = await this.store.read(path);
		if (text === null) {
			if (optional) return null;
			throw new Error(`нет файла ${path}`);
		}
		const f = Fmt.load(text);
		f.path = path;
		this.files.set(path, f);
		return f;
	}

	// A file that may not exist yet (tools/srd/promoted.json): created on the first save.
	async ensureFile(path, empty = {}) {
		const f = await this.readFile(path, { optional: true });
		if (f) return f;
		const n = Fmt.load(Fmt.fresh(empty));
		n.path = path;
		n.created = true;
		this.files.set(path, n);
		return n;
	}

	/* ----- collections ----- */

	// cfg.load() registers collections: {id, title, group, file, at, type: map|array|single, ...}.
	addColl(c) {
		const app = this;
		c.at = c.at || [];
		c.type = c.type || 'map';
		c.container ||= () => getAt(app.files.get(c.file)?.data, c.at);
		c.entries = () => {
			const box = c.container();
			if (box == null) return [];
			if (c.type === 'single') return [[c.singleId || 'main', box]];
			if (c.type === 'array') return box.map((e) => [String(e?.[c.idKey] ?? ''), e]);
			return Object.entries(box).filter(([k]) => !k.startsWith('_') && !(c.skip || []).includes(k));
		};
		c.get = (id) => c.entries().find(([k]) => k === id)?.[1];
		c.title = c.title || c.id;
		this.colls.push(c);
		return c;
	}

	coll(id) { return this.colls.find((c) => c.id === id); }

	entryName(c, id, e) {
		if (c.name) return c.name(e, id) || id;
		if (e && typeof e === 'object') return e.name || e.title || e.summary || id;
		return id;
	}

	reindex() {
		for (const c of this.colls) {
			c.text = new Map(c.entries().map(([id, e]) => [id, (id + ' ' + JSON.stringify(e)).toLowerCase()]));
			c.facets = this.facets(c);
			c.keyUnion = null;
		}
	}

	// Filters by the collection's own properties: few distinct values → a list, many numbers → a range.
	facets(c) {
		const entries = c.entries();
		const objs = entries.filter(([, e]) => e && typeof e === 'object' && !Array.isArray(e));
		if (!objs.length) return [];
		const paths = new Set();
		for (const [, e] of objs) for (const k of Object.keys(e)) paths.add(k);
		for (const p of c.filterPaths || []) paths.add(p);
		for (const k of Object.keys(c.computed || {})) paths.add('=' + k);
		const out = [];
		for (const p of paths) {
			if ((c.noFilter || []).includes(p) || ['name', 'name_en', 'desc', 'description', 'title', 'id', 'story', 'summary', 'text'].includes(p)) continue;
			const vals = objs.map(([id, e]) => (p.startsWith('=') ? c.computed[p.slice(1)](e, id) : getAt(e, p.split('.'))));
			const present = vals.filter((v) => v !== undefined && v !== null);
			if (!present.length) continue;
			const label = (c.labels || {})[p] || LABELS[p.split('.').at(-1).replace(/^=/, '')] || p.replace(/^=/, '');
			if (present.every((v) => typeof v === 'boolean')) { out.push({ p, label, kind: 'bool' }); continue; }
			if (present.every((v) => Array.isArray(v) && v.every((x) => typeof x === 'string'))) {
				const all = [...new Set(present.flat())].sort();
				if (all.length && all.length <= 80) out.push({ p, label, kind: 'has', opts: all });
				continue;
			}
			if (present.every((v) => typeof v === 'number')) {
				const d = [...new Set(present)].sort((a, b) => a - b);
				out.push(d.length <= 12 ? { p, label, kind: 'eq', opts: d } : { p, label, kind: 'range', min: d[0], max: d.at(-1) });
				continue;
			}
			if (present.every((v) => typeof v === 'string')) {
				const d = [...new Set(present)].sort();
				if (d.length <= 40 && d.length < objs.length * 0.8) out.push({ p, label, kind: 'eq', opts: d, missing: present.length < objs.length });
			}
		}
		const pref = c.filterOrder || [];
		const rank = (f) => { const i = pref.indexOf(f.p); return i < 0 ? 999 : i; };
		return out.sort((a, b) => rank(a) - rank(b));
	}

	visible(c) {
		const q = this.query.trim().toLowerCase();
		const words = q.split(/\s+/).filter(Boolean);
		const fs = this.filters[c.id] || {};
		let list = c.entries().filter(([id, e]) => {
			if (words.length) { const t = c.text.get(id) ?? ''; if (!words.every((w) => t.includes(w))) return false; }
			for (const f of c.facets) {
				const want = fs[f.p];
				if (want == null || want === '' || (Array.isArray(want) && want.every((x) => x === ''))) continue;
				const v = f.p.startsWith('=') ? c.computed[f.p.slice(1)](e, id) : getAt(e, f.p.split('.'));
				if (f.kind === 'bool' && String(!!v) !== want) return false;
				if (f.kind === 'has' && !(Array.isArray(v) && v.includes(want))) return false;
				if (f.kind === 'eq' && (want === '∅' ? v != null : String(v) !== want)) return false;
				if (f.kind === 'range') {
					if (typeof v !== 'number') return false;
					if (want[0] !== '' && v < Number(want[0])) return false;
					if (want[1] !== '' && v > Number(want[1])) return false;
				}
			}
			return true;
		});
		if (this.sort) {
			const key = this.sort === 'name' ? ([id, e]) => this.entryName(c, id, e) : this.sort === 'id' ? ([id]) => id : ([, e]) => getAt(e, this.sort.split('.'));
			list = [...list].sort((a, b) => {
				const x = key(a), y = key(b);
				return typeof x === 'number' && typeof y === 'number' ? x - y : String(x ?? '').localeCompare(String(y ?? ''), 'ru');
			});
		}
		return list;
	}

	/* ----- shell ----- */

	shell() {
		const el = (this.el = {});
		el.open = h('button', { class: 'primary', onclick: () => this.pickFolder() }, 'Открыть папку');
		el.reopen = h('button', { hidden: true });
		el.ro = h('input', { type: 'file', webkitdirectory: true, multiple: true, hidden: true, onchange: (e) => e.target.files.length && this.useStore(new FileListStore([...e.target.files])) });
		el.save = h('button', { class: 'primary', disabled: true, onclick: () => this.save() }, 'Сохранить');
		el.diff = h('button', { disabled: true, onclick: () => this.showDiff() }, 'Изменения');
		el.where = h('span', { class: 'where' });
		el.extra = h('span', { class: 'extra' });
		el.nav = h('nav');
		el.search = h('input', { type: 'search', placeholder: 'Поиск по всему тексту записи…', oninput: (e) => { this.query = e.target.value; this.renderList(); } });
		el.facets = h('div', { class: 'facets' });
		el.count = h('span', { class: 'count' });
		el.sortSel = h('select', { onchange: (e) => { this.sort = e.target.value; this.renderList(); } });
		el.create = h('button', { onclick: () => this.create() }, 'Создать');
		el.list = h('ul', { class: 'list' });
		el.main = h('main');
		el.toast = h('div', { class: 'toast', hidden: true });
		this.root.append(
			h('header', {}, h('b', {}, this.cfg.title), el.open, el.reopen,
				h('button', { title: 'Для браузеров без File System Access API: правки скачиваются файлами', onclick: () => el.ro.click() }, 'Открыть только для чтения'),
				el.ro, el.save, el.diff, el.extra, el.where),
			h('div', { class: 'body' }, el.nav,
				h('section', { class: 'side' }, el.search, el.facets, h('div', { class: 'listbar' }, el.count, el.sortSel, el.create), el.list),
				el.main),
			el.toast,
		);
		addEventListener('keydown', (e) => { if ((e.ctrlKey || e.metaKey) && e.key === 's') { e.preventDefault(); this.save(); } });
	}

	welcome() {
		this.el.main.replaceChildren(h('div', { class: 'welcome', html: this.cfg.welcome }));
	}

	toast(msg, ms = 6000) {
		const t = this.el.toast;
		t.textContent = msg;
		t.hidden = false;
		clearTimeout(this.toastT);
		this.toastT = setTimeout(() => (t.hidden = true), ms);
	}

	renderNav() {
		const groups = new Map();
		for (const c of this.colls) if (!c.hidden) { if (!groups.has(c.group || '')) groups.set(c.group || '', []); groups.get(c.group || '').push(c); }
		this.el.nav.replaceChildren(...[...groups].flatMap(([g, cs]) => [
			g ? h('div', { class: 'group' }, g) : null,
			...cs.map((c) => {
				const errs = this.errors.filter((e) => e.coll === c.id).length;
				return h('a', { href: `#${c.id}`, class: this.cur === c ? 'on' : '' }, c.title,
					h('span', { class: 'n' }, errs ? h('span', { class: 'bad' }, `⚠${errs} `) : null, String(c.entries().length)));
			}),
		]));
	}

	openColl(id, entryId) {
		const c = this.coll(id);
		if (!c) return;
		if (this.cur !== c) {
			this.cur = c;
			this.sort = '';
			this.renderFacets();
			this.renderNav();
		}
		this.selected = entryId ?? (c.type === 'single' ? c.entries()[0]?.[0] : null);
		this.renderList();
		this.renderEntry();
	}

	fromHash() {
		const [cid, ...rest] = decodeURIComponent(location.hash.slice(1)).split('/');
		if (!cid || !this.coll(cid)) return false;
		this.openColl(cid, rest.length ? rest.join('/') : undefined);
		return true;
	}

	go(cid, id) {
		const hash = '#' + encodeURIComponent(cid) + (id != null ? '/' + encodeURIComponent(id) : '');
		if (location.hash === hash) this.fromHash();
		else location.hash = hash;
	}

	renderFacets() {
		const c = this.cur;
		const fs = (this.filters[c.id] ||= {});
		const sel = (f) => {
			if (f.kind === 'range') {
				const v = fs[f.p] || ['', ''];
				const inp = (j, ph) => h('input', { type: 'number', step: 'any', placeholder: ph, value: v[j], oninput: (e) => { v[j] = e.target.value; fs[f.p] = v; this.renderList(); } });
				return h('label', { class: 'facet range' }, f.label, inp(0, `от ${f.min}`), inp(1, `до ${f.max}`));
			}
			const opts = f.kind === 'bool' ? [['true', 'да'], ['false', 'нет']] : f.opts.map((o) => [String(o), this.optLabel(c, f.p, o)]);
			if (f.missing) opts.push(['∅', '— не задано']);
			const s = h('select', { onchange: (e) => { fs[f.p] = e.target.value; this.renderList(); } },
				h('option', { value: '' }, `${f.label}: все`),
				opts.map(([v, l]) => h('option', { value: v, selected: fs[f.p] === v }, `${f.label}: ${l}`)));
			return h('label', { class: 'facet' + (fs[f.p] ? ' set' : '') }, s);
		};
		const reset = h('button', { class: 'link', onclick: () => { this.filters[c.id] = {}; this.renderFacets(); this.renderList(); } }, 'сбросить фильтры');
		// With a preferred list, the rest of the filters wait behind «ещё».
		const pref = c.filterOrder ? c.facets.filter((f) => c.filterOrder.includes(f.p)) : c.facets.slice(0, 8);
		const rest = c.facets.filter((f) => !pref.includes(f));
		const showAll = this.allFacets === c.id || rest.some((f) => fs[f.p]);
		const more = rest.length && !showAll ? h('button', { class: 'link', onclick: () => { this.allFacets = c.id; this.renderFacets(); } }, `ещё ${rest.length}…`) : '';
		this.el.facets.replaceChildren(...pref.map(sel), ...(showAll ? rest.map(sel) : []), more, c.facets.length ? reset : '');
		const sorts = [['', 'порядок файла'], ['name', 'по названию'], ['id', 'по id'], ...c.facets.filter((f) => f.kind === 'range' || (f.kind === 'eq' && typeof f.opts[0] === 'number')).map((f) => [f.p, `по: ${f.label}`])];
		this.el.sortSel.replaceChildren(...sorts.map(([v, l]) => h('option', { value: v }, l)));
		this.el.create.hidden = c.type === 'single' || c.readonly;
	}

	optLabel(c, p, v) {
		const ref = this.refFor(c, p.split('.'));
		const t = ref && this.coll(ref)?.get(String(v));
		return t ? `${this.entryName(this.coll(ref), String(v), t)}` : String(v);
	}

	renderList() {
		const c = this.cur;
		if (!c) return;
		const list = this.visible(c);
		this.el.count.textContent = `${list.length} из ${c.entries().length}`;
		const bad = new Set(this.errors.filter((e) => e.coll === c.id).map((e) => e.id));
		const max = 600;
		this.el.list.replaceChildren(...list.slice(0, max).map(([id, e]) => {
			const sub = c.sub ? c.sub(e, id) : typeof e !== 'object' ? String(e).slice(0, 120) : '';
			return h('li', { class: (id === this.selected ? 'on' : '') + (bad.has(id) ? ' bad' : ''), onclick: () => this.go(c.id, id) },
				h('div', { class: 'row1' }, h('span', {}, this.entryName(c, id, e)), h('code', {}, id)),
				sub ? h('div', { class: 'row2' }, sub) : null);
		}), list.length > max ? h('li', { class: 'more' }, `…ещё ${list.length - max}, уточните поиск`) : '');
	}

	/* ----- one entry ----- */

	renderEntry() {
		const c = this.cur, id = this.selected;
		const main = this.el.main;
		if (!c || id == null) {
			main.replaceChildren(h('div', { class: 'welcome' }, c?.title ? h('h2', {}, c.title) : null, c?.note ? h('p', {}, c.note) : null, c ? this.bannerFor(c, null) : null, h('p', { class: 'muted' }, 'Выберите запись слева или нажмите «Создать».')));
			return;
		}
		const e = c.get(id);
		if (e === undefined) { main.replaceChildren(h('div', { class: 'welcome' }, `Нет записи ${id} в «${c.title}».`)); return; }
		if (this.snapFor !== c.id + '/' + id) { this.snap = structuredClone(e); this.snapFor = c.id + '/' + id; }
		const scroll = main.scrollTop;
		const tabs = h('div', { class: 'tabs' });
		const body = h('div', { class: 'tabbody' });
		const showForm = () => { body.replaceChildren(this.form(c, id)); mark(0); };
		const showJson = () => { body.replaceChildren(this.jsonTab(c, id)); mark(1); };
		const mark = (n) => [...tabs.children].forEach((b, j) => b.classList.toggle('on', j === n));
		tabs.append(h('button', { onclick: showForm }, 'Форма'), h('button', { onclick: showJson }, 'JSON'));
		const head = h('div', { class: 'entryhead' },
			h('h2', {}, this.entryName(c, id, e)),
			h('code', { class: 'id' }, id),
			h('span', { class: 'grow' }),
			c.type !== 'single' && !c.readonly ? h('button', { onclick: () => this.rename(c, id) }, 'Переименовать id') : null,
			c.type !== 'single' && !c.readonly ? h('button', { onclick: () => this.create(e) }, 'Копия') : null,
			h('button', { onclick: () => this.revert(c, id) }, 'Отменить правки'),
			c.type !== 'single' && !c.readonly ? h('button', { class: 'danger', onclick: () => this.remove(c, id) }, 'Удалить') : null);
		const actions = (this.cfg.actions?.(this, c, id, e) || []).map((a) => h('button', { onclick: a.run, title: a.title || '' }, a.label));
		const errs = this.errors.filter((x) => x.coll === c.id && x.id === id);
		main.replaceChildren(...[head,
			this.bannerFor(c, id, e),
			actions.length ? h('div', { class: 'actions' }, ...actions) : null,
			errs.length ? h('ul', { class: 'errs' }, errs.map((x) => h('li', {}, x.msg))) : null,
			this.links(c, id, e),
			tabs, body].filter(Boolean));
		showForm();
		main.scrollTop = scroll;
	}

	bannerFor(c, id, e) {
		const b = this.cfg.banner?.(this, c, id, e);
		return b ? h('div', { class: 'banner', html: b }) : null;
	}

	changed(c, structural) {
		const f = this.files.get(c.file);
		f.touched = true;
		const id = this.selected;
		const e = c.get(id);
		if (e !== undefined) c.text.set(id, (id + ' ' + JSON.stringify(e)).toLowerCase());
		if (c === this.cur && e !== undefined) { const t = this.el.main.querySelector('.entryhead h2'); if (t) t.textContent = this.entryName(c, id, e); }
		this.updateDirty();
		clearTimeout(this.relistT);
		this.relistT = setTimeout(() => { this.revalidate(); this.renderList(); }, 300);
		if (structural) this.renderEntry();
	}

	dirtyFiles() {
		return [...this.files.values()].filter((f) => f.touched && (f.created || !Fmt.equal(f.data, f.tree.root.val)));
	}

	updateDirty() {
		const n = this.dirtyFiles().length;
		this.el.save.disabled = !n;
		this.el.diff.disabled = !n;
		this.el.save.textContent = n ? `Сохранить (${n})` : 'Сохранить';
		document.title = (n ? '● ' : '') + this.cfg.title;
	}

	revalidate() {
		if (!this.cfg.validate) return;
		this.errors = this.cfg.validate(this);
		this.renderNav();
		this.cfg.onValidate?.(this);
	}

	/* ----- the form ----- */

	refFor(c, segs) {
		const ns = normSegs(segs);
		for (const r of c.refs || []) if (matchPath(r.p, ns)) return typeof r.to === 'function' ? r.to(segs) : r.to;
		return null;
	}

	refIds(target) {
		const t = this.coll(target);
		return t ? t.entries().map(([k, e]) => [k, this.entryName(t, k, e)]) : [];
	}

	datalist(ids) {
		const key = ids.map(([v, l]) => v + '\u0002' + l).join('\u0001');
		this.lists ||= new Map();
		let dl = this.lists.get(key);
		if (!dl) {
			dl = h('datalist', { id: 'dl' + this.lists.size }, ids.map(([v, l]) => h('option', { value: v }, l !== v ? l : null)));
			document.body.append(dl);
			this.lists.set(key, dl);
		}
		return dl.id;
	}

	// Values met at the same place in other entries: suggestions for a text field.
	seen(c, segs) {
		const ns = normSegs(segs.slice(1)).join('.');
		if (!c.keyUnion) {
			c.keyUnion = { vals: new Map(), keys: new Map() };
			const walk = (v, p) => {
				const k = Fmt.kind(v);
				const key = p.join('.');
				if (k === 's') {
					if (typeof v === 'string' && v.length < 60) { if (!c.keyUnion.vals.has(key)) c.keyUnion.vals.set(key, new Set()); c.keyUnion.vals.get(key).add(v); }
					return;
				}
				if (k === 'a') { v.forEach((x) => walk(x, [...p, '[]'])); return; }
				if (!c.keyUnion.keys.has(key)) c.keyUnion.keys.set(key, new Map());
				for (const [kk, x] of Object.entries(v)) { if (!c.keyUnion.keys.get(key).has(kk)) c.keyUnion.keys.get(key).set(kk, x); walk(x, [...p, kk]); }
			};
			for (const [, e] of c.entries()) walk(e, []);
		}
		return { vals: c.keyUnion.vals.get(ns), keys: c.keyUnion.keys.get(ns) };
	}

	form(c, id) {
		const box = c.type === 'single' ? { [id]: c.container() } : c.container();
		const holderKey = c.type === 'array' ? c.container().findIndex((x) => String(x?.[c.idKey]) === id) : id;
		const holder = c.type === 'single' ? box : c.container();
		const wrap = h('div', { class: 'form' });
		wrap.append(this.field(c, holder, holderKey, [id], 0, true));
		return wrap;
	}

	label(c, key) {
		const l = (c.labels || {})[key] || LABELS[key];
		return h('span', { class: 'key', title: String(key) }, typeof key === 'number' ? `#${key + 1}` : key, l ? h('small', {}, l) : null);
	}

	field(c, holder, key, segs, depth, root = false) {
		const v = holder[key];
		const k = Fmt.kind(v);
		const ro = c.readonly;
		const set = (nv, structural = false) => {
			if (c.type === 'single' && root) this.replace(c, key, nv);
			holder[key] = nv;
			this.changed(c, structural);
		};
		if (k === 'o') return this.objField(c, v, segs, depth, root);
		if (k === 'a') return this.arrField(c, v, segs, depth, set);
		const ref = this.refFor(c, segs.slice(1));
		if (typeof v === 'boolean') return h('input', { type: 'checkbox', checked: v, disabled: ro, onchange: (e) => set(e.target.checked) });
		if (typeof v === 'number') {
			return h('input', { type: 'number', step: 'any', value: v, disabled: ro, class: 'num',
				onchange: (e) => { const n = Number(e.target.value); if (e.target.value !== '' && Number.isFinite(n)) set(n); else e.target.value = holder[key]; } });
		}
		if (v === null) {
			return h('input', { value: 'null', class: 'mono', disabled: ro, title: 'null; введите JSON-значение',
				onchange: (e) => { try { set(JSON.parse(e.target.value), true); } catch { e.target.value = 'null'; } } });
		}
		const long = v.length > 70 || /desc|description|story|text|lore|personality|tone|magic/.test(String(key));
		if (long && !ref) {
			const ta = h('textarea', { value: v, disabled: ro, rows: Math.min(14, Math.max(2, Math.ceil(v.length / 90) + v.split('\n').length - 1)), oninput: (e) => set(e.target.value) });
			return ta;
		}
		const sugg = ref ? this.refIds(ref) : [...(this.seen(c, segs).vals || [])].sort().map((x) => [x, x]);
		const inp = h('input', { value: v, disabled: ro, list: sugg.length ? this.datalist(sugg) : null, oninput: (e) => { set(e.target.value); if (ref) chip.replaceChildren(...this.refChip(ref, e.target.value)); } });
		const chip = h('span', { class: 'chip' });
		if (!ref) return inp;
		chip.append(...this.refChip(ref, v));
		return h('span', { class: 'refrow' }, inp, chip);
	}

	refChip(ref, v) {
		if (!v) return [];
		const t = this.coll(ref);
		const e = t?.get(v);
		if (!t) return [];
		if (e === undefined) return [h('span', { class: 'bad' }, '⚠ нет такого')];
		const [lc, lid] = this.resolve(ref, v);
		const name = this.entryName(t, v, e);
		return [this.coll(lc)?.hidden ? h('span', { class: 'muted' }, name) : h('a', { href: `#${lc}/${encodeURIComponent(lid)}` }, '→ ' + name)];
	}

	// A hidden lookup (merged items, encounters) may point at a visible entry to open.
	resolve(cid, id) { return this.cfg.resolve?.(this, cid, id) || [cid, id]; }

	objField(c, v, segs, depth, root) {
		const ro = c.readonly;
		const keyRef = this.refFor(c, [...segs.slice(1), '{}']);
		const rows = Object.keys(v).map((k) => {
			const sub = this.field(c, v, k, [...segs, k], depth + 1);
			const kref = keyRef ? this.refChip(keyRef, k) : [];
			const del = ro ? null : h('button', { class: 'x', title: 'Убрать поле', onclick: () => { delete v[k]; this.changed(c, true); } }, '×');
			const big = sub.tagName === 'DETAILS' || sub.classList?.contains('arr');
			return h('div', { class: 'kv' + (big ? ' big' : '') }, h('div', { class: 'k' }, this.label(c, k), ...kref, del), h('div', { class: 'v' }, sub));
		});
		const add = ro ? null : this.addKey(c, v, segs, keyRef);
		if (root) return h('div', { class: 'obj' }, ...rows, add);
		const sum = v.name || v.id || v.title || v.monster || v.text || '';
		return h('details', { open: depth < 3 }, h('summary', {}, `{${Object.keys(v).length}} `, h('span', { class: 'muted' }, String(sum).slice(0, 80))), h('div', { class: 'obj' }, ...rows, add));
	}

	addKey(c, v, segs, keyRef) {
		const { keys } = this.seen(c, segs);
		const known = keyRef ? this.refIds(keyRef).filter(([k]) => !(k in v)) : [...(keys || new Map()).keys()].filter((k) => !(k in v)).map((k) => [k, (c.labels || {})[k] || LABELS[k] || k]);
		const name = h('input', { placeholder: keyRef ? 'id' : 'новое поле', list: known.length ? this.datalist(known) : null, class: 'mono small' });
		const sample = () => keys?.get(name.value.trim());
		const type = h('select', { class: 'small' }, ...[['auto', 'тип как у других'], ['s', 'строка'], ['n', 'число'], ['b', 'да/нет'], ['a', 'список'], ['o', 'объект']].map(([x, l]) => h('option', { value: x }, l)));
		const go = () => {
			const k = name.value.trim();
			if (!k) return;
			if (k in v) return this.toast(`Поле ${k} уже есть`);
			const t = type.value;
			const s = sample();
			v[k] = t === 'auto' ? (keyRef && keys && keys.size ? blank([...keys.values()][0]) : s !== undefined ? blank(s) : '') : { s: '', n: 0, b: false, a: [], o: {} }[t];
			if (keyRef && t === 'auto' && typeof v[k] === 'number') v[k] = 1;
			this.changed(c, true);
		};
		return h('div', { class: 'addkey' }, name, type, h('button', { onclick: go }, '+ поле'));
	}

	arrField(c, v, segs, depth, set) {
		const ro = c.readonly;
		const scalars = v.every((x) => Fmt.kind(x) === 's');
		const move = (j, d) => { const t = v[j]; v.splice(j, 1); v.splice(j + d, 0, t); this.changed(c, true); };
		const tools = (j) => ro ? null : h('span', { class: 'tools' },
			j > 0 ? h('button', { class: 'x', title: 'Выше', onclick: () => move(j, -1) }, '↑') : null,
			j < v.length - 1 ? h('button', { class: 'x', title: 'Ниже', onclick: () => move(j, 1) }, '↓') : null,
			h('button', { class: 'x', title: 'Убрать', onclick: () => { v.splice(j, 1); this.changed(c, true); } }, '×'));
		const add = ro ? null : h('button', { class: 'small', onclick: () => {
			const sample = v.at(-1) ?? this.sampleItem(c, segs);
			v.push(sample !== undefined ? blank(sample) : '');
			this.changed(c, true);
		} }, '+ элемент');
		if (scalars) {
			const rows = v.map((x, j) => h('div', { class: 'item' }, this.field(c, v, j, [...segs, j], depth + 1), tools(j)));
			return h('div', { class: 'arr flat' }, ...rows, add);
		}
		const rows = v.map((x, j) => {
			const body = this.field(c, v, j, [...segs, j], depth + 1);
			return h('div', { class: 'item' }, body, tools(j));
		});
		return h('div', { class: 'arr' }, ...rows, add);
	}

	sampleItem(c, segs) {
		const ns = normSegs([...segs.slice(1), 0]).join('.');
		let found;
		const walk = (v, p) => {
			if (found !== undefined) return;
			if (p.join('.') === ns) { found = v; return; }
			if (Fmt.kind(v) === 'a') v.forEach((x) => walk(x, [...p, '[]']));
			else if (Fmt.kind(v) === 'o') for (const [k, x] of Object.entries(v)) walk(x, [...p, k]);
		};
		for (const [, e] of c.entries()) walk(e, []);
		return found;
	}

	jsonTab(c, id) {
		const e = c.get(id);
		const ta = h('textarea', { class: 'json', value: JSON.stringify(e, null, '\t'), spellcheck: false, readOnly: !!c.readonly });
		const msg = h('span', { class: 'muted' });
		const apply = () => {
			let nv;
			try { nv = JSON.parse(ta.value); } catch (err) { msg.textContent = err.message; msg.className = 'bad'; return; }
			this.replace(c, id, nv);
			this.changed(c, true);
		};
		return h('div', {}, ta, c.readonly ? null : h('div', { class: 'actions' }, h('button', { onclick: apply }, 'Применить JSON'), msg));
	}

	replace(c, id, nv) {
		const box = c.container();
		if (c.type === 'single') {
			if (!c.at.length) this.files.get(c.file).data = nv;
			else getAt(this.files.get(c.file).data, c.at.slice(0, -1))[c.at.at(-1)] = nv;
			return;
		}
		if (c.type === 'array') { box[box.findIndex((x) => String(x?.[c.idKey]) === id)] = nv; return; }
		box[id] = nv;
	}

	revert(c, id) {
		if (this.snapFor !== c.id + '/' + id) return;
		this.replace(c, id, structuredClone(this.snap));
		this.changed(c, true);
	}

	/* ----- create, rename, delete ----- */

	async create(copyOf) {
		const c = this.cur;
		if (!c || c.type === 'single') return;
		if (!this.files.has(c.file)) await this.ensureFile(c.file);
		let box = c.container();
		if (box == null) {
			// An optional section (world.services) appears on its first entry.
			const parent = getAt(this.files.get(c.file).data, c.at.slice(0, -1));
			box = parent[c.at.at(-1)] = c.type === 'array' ? [] : {};
		}
		const id = (prompt(`id новой записи в «${c.title}»${c.idHint ? ' (' + c.idHint + ')' : ''}:`) || '').trim();
		if (!id) return;
		if (c.get(id) !== undefined) return this.toast(`id ${id} уже занят`);
		if (c.idPattern && !new RegExp(c.idPattern).test(id)) return this.toast(`id должен подходить под ${c.idPattern}`);
		let nv = copyOf ? structuredClone(copyOf) : this.cfg.newEntry?.(this, c, id) ?? this.skeleton(c);
		if (c.type === 'array') { nv = { [c.idKey]: id, ...nv }; nv[c.idKey] = id; box.push(nv); }
		else if (c.sorted) this.sortedInsert(c, box, id, nv);
		else box[id] = nv;
		this.files.get(c.file).touched = true;
		this.reindex();
		this.renderNav();
		this.updateDirty();
		this.go(c.id, id);
	}

	// A new entry gets the fields at least half of the entries have, empty; optional blocks are added by «+ поле».
	skeleton(c) {
		const all = c.entries().map(([, e]) => e);
		const objs = all.filter((e) => Fmt.kind(e) === 'o');
		if (!objs.length) return all.length ? blank(all[0]) : {};
		const count = new Map();
		for (const e of objs) for (const k of Object.keys(e)) count.set(k, (count.get(k) || 0) + 1);
		const out = {};
		for (const [k, n] of count) if (n * 2 >= objs.length) out[k] = blank(objs.find((e) => k in e)[k]);
		return out;
	}

	sortedInsert(c, box, id, nv) {
		const all = Object.entries(box);
		all.push([id, nv]);
		all.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
		for (const k of Object.keys(box)) delete box[k];
		for (const [k, x] of all) box[k] = x;
	}

	rename(c, id) {
		const nid = (prompt(`Новый id вместо ${id}. Ссылки на старый id в других записях не меняются — проверьте их после.`, id) || '').trim();
		if (!nid || nid === id) return;
		if (c.get(nid) !== undefined) return this.toast(`id ${nid} уже занят`);
		const box = c.container();
		if (c.type === 'array') box.find((x) => String(x?.[c.idKey]) === id)[c.idKey] = nid;
		else {
			const all = Object.entries(box).map(([k, x]) => [k === id ? nid : k, x]);
			if (c.sorted) all.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
			for (const k of Object.keys(box)) delete box[k];
			for (const [k, x] of all) box[k] = x;
		}
		this.files.get(c.file).touched = true;
		this.reindex();
		this.updateDirty();
		this.revalidate();
		const back = this.incoming(c.id, id);
		if (back.length) this.toast(`На старый id ${id} ссылаются: ${back.slice(0, 6).map((b) => b.id).join(', ')}${back.length > 6 ? '…' : ''}`, 10000);
		this.go(c.id, nid);
	}

	remove(c, id) {
		const back = this.incoming(c.id, id);
		if (!confirm(`Удалить ${id} из «${c.title}»?${back.length ? `\nНа запись ссылаются: ${back.map((b) => b.id).join(', ')}` : ''}`)) return;
		const box = c.container();
		if (c.type === 'array') box.splice(box.findIndex((x) => String(x?.[c.idKey]) === id), 1);
		else delete box[id];
		this.files.get(c.file).touched = true;
		this.reindex();
		this.renderNav();
		this.updateDirty();
		this.revalidate();
		this.go(c.id);
	}

	/* ----- cross-links ----- */

	// Every reference an entry holds, by the collection's ref patterns: [{to, id, path}].
	outgoing(c, e) {
		const out = [];
		const walk = (v, segs) => {
			const k = Fmt.kind(v);
			if (k === 'a') { v.forEach((x, j) => walk(x, [...segs, j])); return; }
			if (k === 'o') {
				const kref = this.refFor(c, [...segs, '{}']);
				for (const [kk, x] of Object.entries(v)) {
					if (kref) out.push({ to: kref, id: kk, path: [...segs, kk] });
					walk(x, [...segs, kk]);
				}
				return;
			}
			if (typeof v !== 'string' || !v) return;
			const to = this.refFor(c, segs);
			if (to) out.push({ to, id: c.refValue ? c.refValue(to, v) : v, path: segs });
		};
		walk(e, []);
		return out;
	}

	incoming(cid, id) {
		const out = [];
		for (const c of this.colls) {
			if (!c.refs?.length || c.hidden) continue;
			for (const [eid, e] of c.entries()) {
				for (const r of this.outgoing(c, e)) if (r.to === cid && r.id === id) out.push({ coll: c.id, id: eid, path: r.path });
			}
		}
		return out;
	}

	links(c, id, e) {
		if (!this.cfg.showLinks) return null;
		const out = this.outgoing(c, e);
		const inc = this.incoming(c.id, id);
		const extra = this.cfg.extraLinks?.(this, c, id, e) || [];
		if (!out.length && !inc.length && !extra.length) return null;
		const chip = (cid, rid, path) => {
			const t = this.coll(cid);
			const te = t?.get(rid);
			const name = te !== undefined ? this.entryName(t, rid, te) : rid;
			const where = path ? path.filter((x) => typeof x !== 'number').join('.') : '';
			if (te === undefined) return h('span', { class: 'chip bad', title: where }, `⚠ ${t?.title || cid}: ${rid}`);
			const [lc, lid] = this.resolve(cid, rid);
			if (this.coll(lc)?.hidden) return h('span', { class: 'chip', title: where }, name);
			return h('a', { class: 'chip', href: `#${lc}/${encodeURIComponent(lid)}`, title: `${t.title} · ${where}` }, name);
		};
		const groupBy = (list, key) => {
			const m = new Map();
			for (const x of list) { const k = key(x); if (!m.has(k)) m.set(k, []); m.get(k).push(x); }
			return m;
		};
		const uniq = (list, key) => [...new Map(list.map((x) => [key(x), x])).values()];
		const outRows = [...groupBy(uniq(out, (r) => r.to + '/' + r.id), (r) => r.to)].map(([to, rs]) =>
			h('div', { class: 'linkrow' }, h('span', { class: 'muted' }, (this.coll(to)?.title || to) + ':'), ...rs.map((r) => chip(to, r.id, r.path))));
		const inRows = [...groupBy(uniq(inc, (r) => r.coll + '/' + r.id), (r) => r.coll)].map(([from, rs]) =>
			h('div', { class: 'linkrow' }, h('span', { class: 'muted' }, '← ' + (this.coll(from)?.title || from) + ':'), ...rs.map((r) => chip(from, r.id, r.path))));
		return h('details', { class: 'links', open: true }, h('summary', {}, 'Связи'), ...outRows, ...inRows, ...extra);
	}

	/* ----- saving ----- */

	async save() {
		const dirty = this.dirtyFiles();
		if (!dirty.length) return this.toast('Нет изменений');
		if (this.cfg.validate) {
			this.revalidate();
			if (this.errors.length && !confirm(`Найдено ошибок: ${this.errors.length}. Всё равно сохранить?`)) return;
		}
		const done = [];
		for (const f of dirty) {
			if (!this.store.canWrite(f.path)) { this.toast(`${f.path} вне открытой папки — откройте корень репозитория`); continue; }
			const text = f.created ? Fmt.fresh(f.data) : Fmt.dump(f);
			try {
				JSON.parse(text);
				await this.store.write(f.path, text);
			} catch (e) {
				this.toast(`${f.path}: ${e.message}`);
				continue;
			}
			const n = Fmt.load(text);
			Object.assign(f, n, { data: f.data, touched: false, created: false });
			done.push(f.path);
		}
		this.updateDirty();
		const tail = this.store.kind === 'files' ? ' (скачаны: положите их на место в репозитории)' : '';
		if (done.length) this.toast(`Сохранено: ${done.join(', ')}${tail}${this.cfg.afterSave ? '. ' + this.cfg.afterSave(done) : ''}`, 12000);
	}

	showDiff() {
		const dirty = this.dirtyFiles();
		const box = h('div', { class: 'modal' });
		const close = () => box.remove();
		box.append(h('div', { class: 'modalbody' },
			h('div', { class: 'entryhead' }, h('h2', {}, 'Изменения'), h('span', { class: 'grow' }), h('button', { onclick: close }, 'Закрыть')),
			...dirty.map((f) => {
				const text = (f.created ? Fmt.fresh(f.data) : Fmt.dump(f)).replace(/\r\n/g, '\n');
				const d = lineDiff(f.created ? '' : f.norm, text);
				return h('div', {}, h('h3', {}, f.path + (f.created ? ' (новый файл)' : '')),
					h('pre', { class: 'diff' }, ...d.split('\n').map((l) => h('div', { class: l[0] === '+' ? 'add' : l[0] === '-' ? 'del' : '' }, l))));
			})));
		box.addEventListener('click', (e) => { if (e.target === box) close(); });
		document.body.append(box);
	}
}
