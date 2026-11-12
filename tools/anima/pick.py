#!/usr/bin/env python3
"""The author's pick of painted variants in a browser: one page, a button per kind (spells, abilities, acts…), each
icon's variants side by side, a click picks one.

A kind is read from its own set (`SETS`): the folder it was drawn into and the picks file of that folder — the acts
are drawn by FLUX into out_painted_flux/ and picked into picks_flux.json, the rest by Anima into out_painted/ and
picks_painted.json. A pick is written at once into the `variant` of that file (variant 1 is left out, as install.py
reads it); which icons were looked at is kept beside the drawings, in <out>/<kind>/seen.json. Only the icons with two
variants at least are shown; up to six (the seeds 11 … 66 of `anima_gen.py --seeds`). The interface's frames in the
lines style are a kind of their own (`frames`: a part's seeds of ui/paint.py, picked into ui/picks_lines.json); the
icons of the lines style are sets of their own (`lines_spells`…: out_lines/, the acts out_lines_flux/, picked into
picks_lines_icons.json), and
«Превью» lays the game's screens out of every pick at the moment it is opened (ui/preview.py). A card's box
«перерисовать» puts the icon under `redraw` of its picks file with what the author wrote is wrong with it — not `redo`:
install.py still lays the picked variant until the icon is drawn again. Local only (127.0.0.1).

    python tools/anima/pick.py                                 # http://127.0.0.1:8791/ — every kind drawn
    python tools/anima/pick.py --kind spells,acts              # only these kinds
    python tools/anima/pick.py --kind lines_spells,lines_features,lines_acts,lines_traits   # the lines style alone
    http://127.0.0.1:8791/#acts                                # opens on the acts
    http://127.0.0.1:8791/?ids=knock,magic_weapon#spells       # only these, after a redraw
    python tools/anima/pick.py --marked                        # the icons marked «перерисовать», with the notes

Restart it after drawing new variants: the list of files is read once.
"""
from __future__ import annotations

import argparse
import io
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(1, str(HERE / "ui"))
import anima_gen as gen  # noqa: E402
import overlays  # noqa: E402
import preview as pv  # noqa: E402

SEEDS = [11, 22, 33, 44, 55, 66]
# a set → its title on the button, the folder it is drawn into, its picks file, and the kind of the jobs when the set
# is not named by it (in the order of the buttons). The lines style is a trial of its own (the author, 2026-11-12):
# its sets are the same kinds drawn into out_lines/ (the acts by FLUX into out_lines_flux/, as the painted ones: Anima's
# hands pray where FLUX's clasp forearms) and picked into picks_lines_icons.json, apart from the painted.
SETS = {
    "spells": ("Заклинания", "out_painted", "picks_painted.json"),
    "features": ("Умения", "out_painted", "picks_painted.json"),
    "acts": ("Действия", "out_painted_flux", "picks_flux.json"),
    "traits": ("Черты рас", "out_painted", "picks_painted.json"),
    "conditions": ("Состояния", "out_painted", "picks_painted.json"),
    "ui": ("Интерфейс", "out_painted", "picks_painted.json"),
    "groups": ("Группы вещей", "out_painted", "picks_painted.json"),
    "items": ("Вещи", "out_painted", "picks_painted.json"),
    "frames": ("Рамки интерфейса", "out_ui", "ui/picks_lines.json"),
    "lines_spells": ("Заклинания · линии", "out_lines", "picks_lines_icons.json", "spells"),
    "lines_features": ("Умения · линии", "out_lines", "picks_lines_icons.json", "features"),
    "lines_acts": ("Действия · линии", "out_lines_flux", "picks_lines_icons.json", "acts"),
    "lines_traits": ("Черты рас · линии", "out_lines", "picks_lines_icons.json", "traits"),
}


def kind_of_set(name: str) -> str:
    """The kind of the jobs a set shows: its fourth field, else its own name."""
    return SETS[name][3] if len(SETS[name]) > 3 else name


def variants(jobs: list[dict], kind: str, out: Path, picks: dict,
             name: str = "") -> tuple[list[dict], dict[str, Path | bytes]]:
    """The icons of a kind with their drawn variants, and the file behind each picture's address (with the mark of
    `overlay` laid over, as the game gets it); an icon laid from another's (`same`) or drawn by code (`drawn`) is not
    picked on its own. The addresses go under the set's `name` (a kind drawn in two styles is two sets)."""
    items, files = [], {}
    for j in (j for j in jobs if j["kind"] == kind):
        key = f"{kind}/{j['id']}"
        cuts = {n: gen.paths(out, j, n, s)[1] for n, s in enumerate(gen.seeds_of(j, SEEDS), 1)}
        have = [n for n, c in cuts.items() if c.exists()]
        if len(have) >= 2 and key not in picks.get("same", {}) and key not in picks.get("drawn", {}):
            mark = picks.get("overlay", {}).get(key)
            items.append({"key": key, "name": j["name"], "variants": have})
            files.update({f"/img/{name or kind}/{j['id']}/{n}.png": overlays.apply(mark, cuts[n]) if mark else cuts[n]
                          for n in have})
    return sorted(items, key=lambda x: x["name"]), files


def frames(raw: Path) -> tuple[list[dict], dict[str, bytes]]:
    """The parts of the lines interface with a variant per seed drawn, each shown alone as the game would lay it."""
    kits = {n: pv.Kit(raw, {p: s for p in pv.PARTS}) for n, s in enumerate(pv.SEEDS, 1)
            if all((raw / f"{p}_lines_{s}.png").exists() for p in pv.PARTS)}
    items = [{"key": f"frames/{p}", "name": pv.NAMES[p], "variants": list(kits)} for p in pv.PARTS] if len(kits) > 1 else []
    return items, {f"/img/frames/{p}/{n}.png": png(k.sample(p)) for n, k in kits.items() for p in pv.PARTS}


def png(img) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--jobs", type=Path, default=HERE / "jobs" / "icons.json")
    p.add_argument("--kind", default="", help="sets, comma-separated (spells, lines_spells…); every set drawn by default")
    p.add_argument("--port", type=int, default=8791)
    p.add_argument("--marked", action="store_true", help="print the icons marked to redraw, with the notes, and quit")
    a = p.parse_args()
    if a.marked:
        for f in sorted({HERE / s[2] for s in SETS.values()}):
            for k, note in (json.loads(f.read_text(encoding="utf-8")).get("redraw", {}) if f.exists() else {}).items():
                print(f"{k}\t{note}")
        return
    jobs = json.loads(a.jobs.read_text(encoding="utf-8"))["jobs"]
    wanted = [k for k in (a.kind.split(",") if a.kind else SETS) if k in SETS]
    sets, files = {}, {}
    for name in wanted:
        title, out, picks = SETS[name][:3]
        kind = kind_of_set(name)
        given = json.loads((HERE / picks).read_text(encoding="utf-8")) if (HERE / picks).exists() else {}
        items, pics = frames(HERE / out / "raw") if kind == "frames" else variants(jobs, kind, HERE / out, given, name)
        if items:
            sets[name] = {"title": title, "out": HERE / out, "picks": HERE / picks, "items": items,
                          "big": kind == "frames", "kind": kind}
            files.update(pics)
    page = HERE / "pick.html"
    lock = threading.Lock()  # two sets share one picks file: one save at a time

    def picks_of(path: Path) -> dict:
        return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"variant": {}}

    def seen_of(name: str) -> list:
        f = sets[name]["out"] / sets[name]["kind"] / "seen.json"
        return json.loads(f.read_text(encoding="utf-8")) if f.exists() else []

    def kind_of(k: str, s: dict) -> dict:
        """A kind for the page: its icons, the picks, the marks to redraw and what was looked at."""
        whole = picks_of(s["picks"])
        mine = [it["key"] for it in s["items"]]
        return {"kind": k, "title": s["title"], "items": s["items"], "seen": seen_of(k), "big": s["big"],
                "picks": {key: whole.get("variant", {}).get(key, 1) for key in mine},
                "redraw": {key: whole["redraw"][key] for key in mine if key in whole.get("redraw", {})}}

    def icon_of(ref: str) -> Path | None:
        """An icon as picked: the chosen variant of a kind on the page, else what the game has now."""
        kind, _, iid = ref.partition("/")
        s = sets.get(kind)
        n = picks_of(s["picks"])["variant"].get(ref, 1) if s else 0
        f = files.get(f"/img/{kind}/{iid}/{n}.png")
        return f if isinstance(f, Path) else pv.game_icon(ref)

    def screen(name: str) -> bytes:
        frame_picks = sets["frames"]["picks"] if "frames" in sets else pv.PICKS
        return png(pv.render(name, pv.Kit(HERE / "out_ui" / "raw", pv.seeds_of(frame_picks), icon_of)))

    class Handler(BaseHTTPRequestHandler):
        def _send(self, code: int, body: bytes, kind: str) -> None:
            self.send_response(code)
            self.send_header("Content-Type", kind)
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            path = self.path.split("?")[0]
            if path in ("/", "/index.html"):
                self._send(200, page.read_bytes(), "text/html; charset=utf-8")
            elif path == "/data":
                body = {"kinds": [kind_of(k, s) for k, s in sets.items()],
                        "screens": [{"id": k, "title": v} for k, v in pv.SCREENS.items()] if "frames" in sets else []}
                self._send(200, json.dumps(body, ensure_ascii=False).encode("utf-8"), "application/json")
            elif path in files:
                f = files[path]
                self._send(200, f.read_bytes() if isinstance(f, Path) else f, "image/png")
            elif path.startswith("/preview/") and path.endswith(".png") and path[9:-4] in pv.SCREENS:
                self._send(200, screen(path[9:-4]), "image/png")
            else:
                self._send(404, b"no", "text/plain")

        def do_POST(self) -> None:
            if self.path != "/save":
                return self._send(404, b"no", "text/plain")
            got = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            s = sets.get(got.get("kind"))
            if s is None:
                return self._send(400, b"no such kind", "text/plain")
            mine = {it["key"] for it in s["items"]}
            with lock:
                whole = picks_of(s["picks"])
                variant = {k: v for k, v in whole.get("variant", {}).items() if k not in mine}
                variant.update({k: int(v) for k, v in got["picks"].items() if k in mine and int(v) != 1})
                whole["variant"] = dict(sorted(variant.items()))
                redraw = {k: v for k, v in whole.pop("redraw", {}).items() if k not in mine}
                redraw.update({k: str(v).strip() for k, v in got.get("redraw", {}).items() if k in mine})
                if redraw:
                    whole["redraw"] = dict(sorted(redraw.items()))
                s["picks"].write_text(json.dumps(whole, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
                seen = s["out"] / s["kind"] / "seen.json"
                seen.parent.mkdir(parents=True, exist_ok=True)  # the frames have no folder of their own drawn
                seen.write_text(json.dumps(sorted(got["seen"]), ensure_ascii=False, indent=1) + "\n",
                                encoding="utf-8")
            self._send(200, b"ok", "text/plain")

        def log_message(self, *args) -> None:
            pass

    shown = ", ".join(f"{s['title']} {len(s['items'])}" for s in sets.values())
    print(f"{shown} on http://127.0.0.1:{a.port}/", flush=True)
    ThreadingHTTPServer(("127.0.0.1", a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
