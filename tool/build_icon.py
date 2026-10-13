#!/usr/bin/env python3
"""Draws the Haruspex logo, the alchemical symbol for earth (a downward
triangle crossed by a bar), as pixel art.

    python3 tool/build_icon.py assets/icon/haruspex.png   # 256 px app icon
    python3 tool/build_icon.py --rows                      # dashboard logo
    python3 tool/build_icon.py --small-rows                # title bar logo

Needs Pillow for the PNG.
"""
import sys

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


def small_rows():
    """One pixel strokes, for the title bar."""
    return rows(width=13, stroke=1, bar=5, over=2)


def icon(path):
    """The app icon: the thin logo in orange on a dark grey rounded square,
    transparent around it. The logo's squares sit on whole pixels."""
    from PIL import Image, ImageDraw

    size, margin, radius, px = 256, 16, 48, 5
    box, fg = (45, 43, 40), (255, 159, 28)
    # The rounded square, drawn 4 times larger and scaled down for smooth corners.
    k = 4
    big = Image.new("RGBA", (size * k, size * k), (0, 0, 0, 0))
    ImageDraw.Draw(big).rounded_rectangle(
        (margin * k, margin * k, (size - margin) * k - 1, (size - margin) * k - 1),
        radius=radius * k, fill=box + (255,))
    img = big.resize((size, size), Image.LANCZOS)
    art = thin_rows()
    w, h = len(art[0]) * px, len(art) * px
    # A downward triangle looks high when its box is centered: nudge it down.
    ox, oy = (size - w) // 2, (size - h) // 2 + 4
    draw = ImageDraw.Draw(img)
    for y, row in enumerate(art):
        for x, ch in enumerate(row):
            if ch == "#":
                draw.rectangle((ox + x * px, oy + y * px, ox + x * px + px - 1, oy + y * px + px - 1), fill=fg + (255,))
    img.save(path)


if __name__ == "__main__":
    if sys.argv[1] == "--rows":
        for r in thin_rows():
            print(f"  '{r}',")
    elif sys.argv[1] == "--small-rows":
        for r in small_rows():
            print(f"  '{r}',")
    else:
        icon(sys.argv[1])
