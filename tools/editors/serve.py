"""Serves the repo for the data editors in tools/editors on localhost: any browser, no folder picker.

GET serves files of the repo, PUT writes a .json under game/data or tools/srd, GET /__list?dir=<path> lists folders.

    python tools/editors/serve.py            # http://127.0.0.1:8790/tools/editors/assets.html and world.html
    python tools/editors/serve.py --port 9000
"""

from __future__ import annotations

import argparse
import json
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

ROOT = Path(__file__).resolve().parents[2]
WRITABLE = (ROOT / "game" / "data", ROOT / "tools" / "srd")


class Handler(SimpleHTTPRequestHandler):
    def target(self) -> Path | None:
        p = (ROOT / unquote(urlparse(self.path).path).lstrip("/")).resolve()
        return p if p.is_relative_to(ROOT) else None

    def do_GET(self) -> None:
        url = urlparse(self.path)
        if url.path != "/__list":
            return super().do_GET()
        d = (ROOT / parse_qs(url.query).get("dir", [""])[0]).resolve()
        names = sorted(x.name for x in d.iterdir() if x.is_dir()) if d.is_relative_to(ROOT) and d.is_dir() else []
        body = json.dumps(names).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_PUT(self) -> None:
        p = self.target()
        if p is None or p.suffix != ".json" or not any(p.is_relative_to(w) for w in WRITABLE):
            return self.send_error(403, "only .json under game/data or tools/srd")
        text = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8")
        try:
            json.loads(text)
        except ValueError as exc:
            return self.send_error(400, f"not JSON: {exc}")
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(text.encode("utf-8"))  # bytes: the page already chose the line endings
        self.send_response(204)
        self.end_headers()

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8790)
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    server = ThreadingHTTPServer(("127.0.0.1", args.port), partial(Handler, directory=str(ROOT)))
    base = f"http://127.0.0.1:{args.port}/tools/editors"
    print(f"Редактор ассетов: {base}/assets.html\nРедактор мира:    {base}/world.html\nCtrl+C — остановить")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
