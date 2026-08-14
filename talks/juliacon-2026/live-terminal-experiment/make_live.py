#!/usr/bin/env python3
"""Build talk-live.html = ../talk.html + the live-mirror client (EXPERIMENT).

The main deck stays untouched; rerun this after any rebuild of ../talk.html.
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent
DECK = HERE.parent / "talk.html"
OUT = HERE / "talk-live.html"

html = DECK.read_text(encoding="utf-8")
live = (HERE / "live.js").read_text(encoding="utf-8")
inject = f"<script>\n{live}\n</script>\n</body>"
assert html.count("</body>") == 1, "expected exactly one </body> in talk.html"
OUT.write_text(html.replace("</body>", inject), encoding="utf-8")
print(f"wrote {OUT} ({OUT.stat().st_size} bytes) from {DECK}")
