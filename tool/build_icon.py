#!/usr/bin/env python3
"""Draws the Haruspex logo, the alchemical symbol for earth (a downward
triangle crossed by a bar): as a vector for the app icon, and as pixel art
for the dashboard.

    python3 tool/build_icon.py assets/icon   # haruspex.svg and haruspex.png
    python3 tool/build_icon.py --rows        # dashboard logo, pixel art

The vector geometry matches EarthLogo in lib/src/ui/pixel_widgets.dart.
Needs Pillow for the PNG.
"""
import math
import sys
from pathlib import Path

def rows(width=26, stroke=2, bar=9, over=3):
    """The symbol as rows of '#' and '.'. The sides step in by two pixels
    every three rows, a regular staircase close to an equilateral slope. The
    bar reaches [over] pixels past the sides."""
    out = []
    r = 0
    while True:
        left = (r * 2) // 3
        right = width - left
        if right - left < stroke:
            break
        row = ["."] * width
        is_bar = bar <= r < bar + stroke
        lo, hi = (max(0, left - over), min(width, right + over)) if is_bar else (left, right)
        for x in range(lo, hi):
            if r < stroke or is_bar or x < left + stroke or x >= right - stroke:
                row[x] = "#"
        out.append("".join(row))
        r += 1
    return out


def thin_rows():
    """One pixel strokes, for the dashboard and the app icon."""
    return rows(width=27, stroke=1, bar=9, over=3)


# Proportions of the vector logo, relative to the side of the triangle.
BAR_AT = 0.42  # bar position, from the top edge down to the point
OVERHANG = 0.106  # how far the bar reaches past the sides


def logo_shapes(width, stroke, left=0.0, top=0.0):
    """The vector logo whose outer edges span [width], with lines [stroke]
    thick: (outer triangle, inner triangle, bar rectangle). The outline is the
    outer triangle minus the inner one, which gives mitered corners."""
    d = stroke / 2
    side = width - 2 * math.sqrt(3) * d  # side of the centre line
    r = side / (2 * math.sqrt(3))  # inradius
    h = side * math.sqrt(3) / 2
    cx, y0 = left + width / 2, top + d
    cy = y0 + r  # centroid
    tri = [(cx - side / 2, y0), (cx + side / 2, y0), (cx, y0 + h)]

    def scaled(k):
        return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in tri]

    bar_y = y0 + BAR_AT * h
    half = side / 2 * (1 - BAR_AT) + OVERHANG * side
    bar = (cx - half, bar_y - d, cx + half, bar_y + d)
    return scaled((r + d) / r), scaled((r - d) / r), bar


ICON = dict(size=256, margin=16, radius=48, width=140, stroke=11, nudge=4,
            box="#2D2B28", fg="#FF9F1C")


def _icon_shapes():
    c = ICON
    h = c["width"] * math.sqrt(3) / 2
    left = (c["size"] - c["width"]) / 2
    # A downward triangle looks high when its box is centered: nudge it down.
    top = (c["size"] - h) / 2 + c["nudge"]
    return logo_shapes(c["width"], c["stroke"], left, top)


def icon_svg(path):
    c = ICON
    outer, inner, bar = _icon_shapes()

    def pts(p):
        return " ".join(f"{x:.2f},{y:.2f}" for x, y in p)

    m, w = c["margin"], c["size"] - 2 * c["margin"]
    Path(path).write_text(f"""<svg xmlns="http://www.w3.org/2000/svg" width="{c['size']}" height="{c['size']}" viewBox="0 0 {c['size']} {c['size']}">
  <rect x="{m}" y="{m}" width="{w}" height="{w}" rx="{c['radius']}" fill="{c['box']}"/>
  <path fill="{c['fg']}" fill-rule="evenodd" d="M{pts(outer)}Z M{pts(inner)}Z"/>
  <rect x="{bar[0]:.2f}" y="{bar[1]:.2f}" width="{bar[2] - bar[0]:.2f}" height="{bar[3] - bar[1]:.2f}" fill="{c['fg']}"/>
</svg>
""")


def icon_png(path):
    from PIL import Image, ImageDraw

    c = ICON
    k = 8  # drawn 8 times larger, then scaled down for smooth edges
    rgb = lambda h: tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
    big = Image.new("RGBA", (c["size"] * k, c["size"] * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    m = c["margin"] * k
    d.rounded_rectangle((m, m, c["size"] * k - m - 1, c["size"] * k - m - 1), radius=c["radius"] * k,
                        fill=rgb(c["box"]) + (255,))
    outer, inner, bar = _icon_shapes()
    sc = lambda p: [(x * k, y * k) for x, y in p]
    d.polygon(sc(outer), fill=rgb(c["fg"]) + (255,))
    d.polygon(sc(inner), fill=rgb(c["box"]) + (255,))
    d.rectangle(tuple(v * k for v in bar), fill=rgb(c["fg"]) + (255,))
    big.resize((c["size"], c["size"]), Image.LANCZOS).save(path)


if __name__ == "__main__":
    if sys.argv[1] == "--rows":
        for r in thin_rows():
            print(f"  '{r}',")
    else:
        out = Path(sys.argv[1])
        icon_svg(out / "haruspex.svg")
        icon_png(out / "haruspex.png")
