#!/usr/bin/env python3
"""Live terminal mirror bridge for the JuliaCon 2026 deck (EXPERIMENT).

Polls a tmux pane and streams its visible tail to the deck's terminal band
over Server-Sent Events. Stdlib only — no pip installs.

Usage:
    tmux new-session -s sturmdemo        # the REAL terminal you type into
    python3 bridge.py                    # in another shell
    # then open http://127.0.0.1:8123/  (serves talk-live.html, same-origin)
    # or open talk-live.html via file:// (CORS header * is sent for that)

Endpoints:
    /        -> talk-live.html (so the deck and the stream share an origin)
    /stream  -> text/event-stream; one event per pane change + heartbeats
    /health  -> "ok <session>" or 500 if the tmux session is gone

The mirror is READ-ONLY by design: you type in the real terminal, the deck
shows it. If this process dies mid-talk the deck silently falls back to its
scripted shadow content — the failure mode is "the deck behaves as before".
"""
import argparse
import http.server
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent


def capture(session: str) -> str | None:
    """Visible content of the session's active pane, or None if unreachable."""
    try:
        out = subprocess.run(
            ["tmux", "capture-pane", "-p", "-t", session],
            capture_output=True, text=True, timeout=2,
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    if out.returncode != 0:
        return None
    # capture-pane returns the full pane height; drop trailing blank rows so
    # the band's flex-end layout shows the action, not empty scrollback.
    lines = out.stdout.rstrip("\n").split("\n")
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines)


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "SturmDeckBridge/0.1"
    session = "sturmdemo"
    poll_s = 0.1
    tail = 12

    def log_message(self, fmt, *args):  # quiet; talk-time stderr noise helps no one
        pass

    def _cors(self):
        # file:// pages have origin "null"; * admits them for GET/SSE.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")

    def do_GET(self):  # noqa: N802  (http.server API)
        path = self.path.split("?", 1)[0]  # ?livealways etc. ride the deck URL
        if path in ("/", "/talk-live.html"):
            return self._serve_deck()
        if path == "/health":
            return self._serve_health()
        if path == "/stream":
            return self._serve_stream()
        self.send_error(404)

    def _serve_deck(self):
        deck = HERE / "talk-live.html"
        if not deck.exists():
            return self.send_error(404, "talk-live.html not built — run make_live.py")
        body = deck.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _serve_health(self):
        pane = capture(self.session)
        ok = pane is not None
        body = (f"ok {self.session}" if ok else f"unreachable {self.session}").encode()
        self.send_response(200 if ok else 500)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _serve_stream(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self._cors()
        self.end_headers()
        last = None
        last_beat = time.monotonic()
        while True:
            pane = capture(self.session)
            now = time.monotonic()
            try:
                if pane is not None and pane != last:
                    last = pane
                    tail = pane.split("\n")[-self.tail:]
                    payload = json.dumps({"lines": tail})
                    self.wfile.write(f"data: {payload}\n\n".encode())
                    self.wfile.flush()
                    last_beat = now
                elif now - last_beat > 15:
                    # comment-line heartbeat keeps proxies/EventSource alive
                    self.wfile.write(b": beat\n\n")
                    self.wfile.flush()
                    last_beat = now
            except (BrokenPipeError, ConnectionResetError):
                return  # client went away; this thread ends
            time.sleep(self.poll_s)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--session", default="sturmdemo", help="tmux session to mirror")
    ap.add_argument("--port", type=int, default=8123)
    ap.add_argument("--lines", type=int, default=12, help="max tail lines pushed")
    ap.add_argument("--poll", type=float, default=0.1, help="poll interval seconds")
    args = ap.parse_args()

    if shutil.which("tmux") is None:
        print("bridge: tmux not found on PATH", file=sys.stderr)
        return 1
    if capture(args.session) is None:
        print(f"bridge: tmux session '{args.session}' not reachable — "
              f"start it with: tmux new-session -s {args.session}", file=sys.stderr)
        return 1

    Handler.session = args.session
    Handler.tail = args.lines
    Handler.poll_s = args.poll
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"bridge: mirroring tmux '{args.session}' on http://127.0.0.1:{args.port}/ "
          f"(deck at /, stream at /stream)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
