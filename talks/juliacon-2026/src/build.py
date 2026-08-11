#!/usr/bin/env python3
"""Splice the deck sources into the single self-contained talk.html.

Usage: python3 src/build.py   (from talks/juliacon-2026/ or repo root)

Assets are inlined from the sibling Bennett.jl checkout:
  - three SVGs inlined as markup (ids NAMESPACED per asset — pipeline.svg and
    circuit_x_plus_1.svg both define id="arrow"; unprefixed they'd collide)
  - demo.svg as a base64 <img> (it carries generic CSS classes in an internal
    <style>; as an <img> its styles stay isolated from the deck's)
"""
import base64
import pathlib
import re
import sys

SRC = pathlib.Path(__file__).resolve().parent
OUT = SRC.parent / "talk.html"
BENNETT_ASSETS = SRC.parent.parent.parent.parent / "Bennett.jl" / "docs" / "src" / "assets"


def namespace_svg(svg: str, prefix: str, extra_class: str = "") -> str:
    """Prefix every id and its references so multiple inline SVGs coexist."""
    ids = set(re.findall(r'\bid="([^"]+)"', svg))
    for i in sorted(ids, key=len, reverse=True):
        svg = svg.replace(f'id="{i}"', f'id="{prefix}-{i}"')
        svg = svg.replace(f'url(#{i})', f'url(#{prefix}-{i})')
        svg = svg.replace(f'href="#{i}"', f'href="#{prefix}-{i}"')
        svg = svg.replace(f'begin="{i}.', f'begin="{prefix}-{i}.')  # SMIL timing refs
    if extra_class:
        svg = re.sub(r"<svg\b", f'<svg class="{extra_class}"', svg, count=1)
    return svg


def main() -> None:
    frame = (SRC / "frame.html").read_text()
    slides = (SRC / "slides-a.html").read_text() + "\n" + (SRC / "slides-b.html").read_text()
    engine = (SRC / "engine.js").read_text()
    components = (SRC / "components.js").read_text()
    circuits = (SRC / "circuits.json").read_text()

    assets = {
        "{{SVG:pipeline}}": namespace_svg((BENNETT_ASSETS / "pipeline.svg").read_text(), "pipe"),
        "{{SVG:circuit23}}": namespace_svg((BENNETT_ASSETS / "circuit_x_plus_1.svg").read_text(), "cx1"),
        "{{SVG:bennett}}": namespace_svg((BENNETT_ASSETS / "bennett_construction.svg").read_text(), "bc", "smil"),
        "{{IMG:democast}}": (
            '<img alt="recorded demo run" style="width:100%;height:auto" src="data:image/svg+xml;base64,'
            + base64.b64encode((BENNETT_ASSETS / "demo.svg").read_bytes()).decode()
            + '">'
        ),
    }
    for marker, markup in assets.items():
        n = slides.count(marker)
        if n > 1:
            sys.exit(f"build.py: expected at most one {marker} in slides, found {n}")
        if n == 0:
            print(f"build.py: note — {marker} unused")
            continue
        slides = slides.replace(marker, markup)

    for marker, content in [
        ("{{SLIDES}}", slides),
        ("{{ENGINE_JS}}", engine),
        ("{{COMPONENTS_JS}}", components),
        ("{{CIRCUITS_JSON}}", circuits),
    ]:
        if frame.count(marker) != 1:
            sys.exit(f"build.py: expected exactly one {marker} in frame.html, found {frame.count(marker)}")
        frame = frame.replace(marker, content)

    leftover = re.findall(r"\{\{[A-Z_]+(?::[a-z0-9_]+)?\}\}", frame)
    if leftover:
        sys.exit(f"build.py: unspliced markers remain: {leftover}")

    OUT.write_text(frame)
    print(f"wrote {OUT} ({OUT.stat().st_size/1024:.0f} KiB)")


if __name__ == "__main__":
    main()
