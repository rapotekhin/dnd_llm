#!/usr/bin/env python3
"""The author's pick of painted variants in a browser: one page, a button per kind (spells, abilities, acts…), each
icon's variants side by side, a click picks one.

A kind is read from its own set (`SETS`): the folder it was drawn into and the picks file of that folder — the acts
are drawn by FLUX into out_painted_flux/ and picked into picks_flux.json, the rest by Anima into out_painted/ and
picks_painted.json. A pick is written at once into the `variant` of that file (variant 1 is left out, as install.py
reads it); which icons were looked at is kept beside the drawings, in <out>/<kind>/seen.json. Only the icons with two
variants at least are shown; up to six (the seeds 11 … 66 of `anima_gen.py --seeds`). Local only (127.0.0.1).

    python tools/anima/pick.py                                 # http://127.0.0.1:8791/ — every kind drawn
    python tools/anima/pick.py --kind spells,acts              # only these kinds
    http://127.0.0.1:8791/#acts                                # opens on the acts
    http://127.0.0.1:8791/?ids=knock,magic_weapon#spells       # only these, after a redraw

Restart it after drawing new variants: the list of files is read once.
"""
from __future__ import annotations

import argparse
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import anima_gen as gen  # noqa: E402

SEEDS = [11, 22, 33, 44, 55, 66]
# a kind → its title on the button, the folder it is drawn into, its picks file (in the order of the buttons)
SETS = {
    "spells": ("Заклинания", "out_painted", "picks_painted.json"),
    "features": ("Умения", "out_painted", "picks_painted.json"),
    "acts": ("Действия", "out_painted_flux", "picks_flux.json"),
    "traits": ("Черты рас", "out_painted", "picks_painted.json"),
    "conditions": ("Состояния", "out_painted", "picks_painted.json"),
    "ui": ("Интерфейс", "out_painted", "picks_painted.json"),
    "groups": ("Группы вещей", "out_painted", "picks_painted.json"),
    "items": ("Вещи", "out_painted", "picks_painted.json"),
}


def variants(jobs: list[dict], kind: str, out: Path) -> tuple[list[dict], dict[str, Path]]:
    """The icons of a kind with their drawn variants, and the file behind each picture's address."""
    items, files = [], {}
    for j in (j for j in jobs if j["kind"] == kind):
        cuts = {n: gen.paths(out, j, n, s)[1] for n, s in enumerate(gen.seeds_of(j, SEEDS), 1)}
        have = [n for n, c in cuts.items() if c.exists()]
        if len(have) >= 2:
            items.append({"key": f"{kind}/{j['id']}", "name": j["name"], "variants": have})
            files.update({f"/img/{kind}/{j['id']}/{n}.png": cuts[n] for n in have})
    return sorted(items, key=lambda x: x["name"]), files


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--jobs", type=Path, default=HERE / "jobs" / "icons.json")
    p.add_argument("--kind", default="", help="kinds, comma-separated; every kind drawn by default")
    p.add_argument("--port", type=int, default=8791)
    a = p.parse_args()
    jobs = json.loads(a.jobs.read_text(encoding="utf-8"))["jobs"]
    wanted = [k for k in (a.kind.split(",") if a.kind else SETS) if k in SETS]
    sets, files = {}, {}
    for kind in wanted:
        title, out, picks = SETS[kind]
        items, pics = variants(jobs, kind, HERE / out)
        if items:
            sets[kind] = {"title": title, "out": HERE / out, "picks": HERE / picks, "items": items}
            files.update(pics)
    page = HERE / "pick.html"
    lock = threading.Lock()  # two kinds share one picks file: one save at a time

    def picks_of(path: Path) -> dict:
        return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"variant": {}}

    def seen_of(kind: str) -> list:
        f = sets[kind]["out"] / kind / "seen.json"
        return json.loads(f.read_text(encoding="utf-8")) if f.exists() else []

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
                body = {"kinds": [{"kind": k, "title": s["title"], "items": s["items"], "seen": seen_of(k),
                                   "picks": {it["key"]: picks_of(s["picks"])["variant"].get(it["key"], 1)
                                             for it in s["items"]}}
                                  for k, s in sets.items()]}
                self._send(200, json.dumps(body, ensure_ascii=False).encode("utf-8"), "application/json")
            elif path in files:
                self._send(200, files[path].read_bytes(), "image/png")
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
                s["picks"].write_text(json.dumps(whole, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
                seen = s["out"] / got["kind"] / "seen.json"
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
