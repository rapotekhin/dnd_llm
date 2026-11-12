#!/usr/bin/env python3
"""The author's pick of painted variants in a browser: each icon's variants side by side, a click picks one.

A pick is written at once into the `variant` of picks_painted.json (variant 1 is left out, as install.py reads it);
which icons were looked at is kept beside the drawings, in out_painted/<kind>/seen.json. Only the icons with two
variants at least are shown; up to six (the seeds 11 … 66 of `anima_gen.py --seeds`). Local only (127.0.0.1).

    python tools/anima/pick.py --kind spells                  # http://127.0.0.1:8791/
    http://127.0.0.1:8791/?ids=knock,magic_weapon             # only these, after a redraw

Restart it after drawing new variants: the list of files is read once.
"""
from __future__ import annotations

import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import anima_gen as gen  # noqa: E402

SEEDS = [11, 22, 33, 44, 55, 66]


def variants(jobs: list[dict], kind: str, out: Path) -> tuple[list[dict], dict[str, Path]]:
    """The icons of a kind with their drawn variants, and the file behind each picture's address."""
    items, files = [], {}
    for j in (j for j in jobs if j["kind"] == kind):
        cuts = {n: gen.paths(out, j, n, s)[1] for n, s in enumerate(gen.seeds_of(j, SEEDS), 1)}
        have = [n for n, c in cuts.items() if c.exists()]
        if len(have) >= 2:
            items.append({"key": f"{kind}/{j['id']}", "name": j["name"], "variants": have})
            files.update({f"/img/{j['id']}/{n}.png": cuts[n] for n in have})
    return sorted(items, key=lambda x: x["name"]), files


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--jobs", type=Path, default=HERE / "jobs" / "icons.json")
    p.add_argument("--kind", default="spells")
    p.add_argument("--picks", type=Path, default=HERE / "picks_painted.json")
    p.add_argument("--out", type=Path, default=HERE / "out_painted")
    p.add_argument("--port", type=int, default=8791)
    a = p.parse_args()
    jobs = json.loads(a.jobs.read_text(encoding="utf-8"))["jobs"]
    items, files = variants(jobs, a.kind, a.out)
    seen_path = a.out / a.kind / "seen.json"
    page = HERE / "pick.html"

    def picks() -> dict:
        return json.loads(a.picks.read_text(encoding="utf-8"))

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
                variant = picks()["variant"]
                seen = json.loads(seen_path.read_text(encoding="utf-8")) if seen_path.exists() else []
                body = {"kind": a.kind, "items": items, "seen": seen,
                        "picks": {it["key"]: variant.get(it["key"], 1) for it in items}}
                self._send(200, json.dumps(body, ensure_ascii=False).encode("utf-8"), "application/json")
            elif path in files:
                self._send(200, files[path].read_bytes(), "image/png")
            else:
                self._send(404, b"no", "text/plain")

        def do_POST(self) -> None:
            if self.path != "/save":
                return self._send(404, b"no", "text/plain")
            got = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            whole = picks()
            mine = {it["key"] for it in items}
            variant = {k: v for k, v in whole["variant"].items() if k not in mine}
            variant.update({k: int(v) for k, v in got["picks"].items() if k in mine and int(v) != 1})
            whole["variant"] = dict(sorted(variant.items()))
            a.picks.write_text(json.dumps(whole, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
            seen_path.write_text(json.dumps(sorted(got["seen"]), ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
            self._send(200, b"ok", "text/plain")

        def log_message(self, *args) -> None:
            pass

    print(f"{len(items)} {a.kind} on http://127.0.0.1:{a.port}/ -> {a.picks.name}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
