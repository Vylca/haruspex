#!/usr/bin/env python3
"""Draws the Haruspex logo, the alchemical symbol for earth (a downward
triangle crossed by a bar), as pixel art.

    python3 tool/build_icon.py assets/icon/haruspex.png   # 256 px app icon
    python3 tool/build_icon.py --rows                      # rows for the app

Needs Pillow for the PNG.
"""
import sys

N = 32       # icon grid
WIDTH = 26   # width of the triangle's top edge
STROKE = 2   # line thickness
BAR = 9      # first row of the crossing bar (two rows thick)


def rows():
    """The symbol as rows of '#' and '.'. The sides step in by two pixels
    every three rows, a regular staircase close to an equilateral slope."""
    out = []
    r = 0
    while True:
        left = (r * 2) // 3
        right = WIDTH - left
        if right - left < STROKE:
            break
        row = ["."] * WIDTH
        full = r < STROKE or BAR <= r < BAR + STROKE
        for x in range(left, right):
            if full or x < left + STROKE or x >= right - STROKE:
                row[x] = "#"
        out.append("".join(row))
        r += 1
    return out


def icon(path):
    from PIL import Image

    art = rows()
    bg, fg, frame = (15, 14, 12), (255, 159, 28), (44, 37, 28)
    img = Image.new("RGBA", (N, N), bg + (255,))
    for x in range(N):
        img.putpixel((x, 0), frame + (255,))
        img.putpixel((x, N - 1), frame + (255,))
        img.putpixel((0, x), frame + (255,))
        img.putpixel((N - 1, x), frame + (255,))
    ox = (N - len(art[0])) // 2
    oy = (N - len(art)) // 2
    for y, row in enumerate(art):
        for x, ch in enumerate(row):
            if ch == "#":
                img.putpixel((ox + x, oy + y), fg + (255,))
    img.resize((256, 256), Image.NEAREST).save(path)


if __name__ == "__main__":
    if sys.argv[1] == "--rows":
        for r in rows():
            print(f"    '{r}',")
    else:
        icon(sys.argv[1])
