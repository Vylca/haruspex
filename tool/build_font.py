#!/usr/bin/env python3
"""Builds the OrgPad pixel font from Spleen 8x16 (BSD 2-Clause, Frederic
Cambus, https://github.com/fcambus/spleen).

Every pixel of the bitmap becomes a square in the outline, so at 16 px (and
32 px, 48 px...) the text renders as crisp pixels. A few symbols OrgPad uses
for bullets are added in the same style.

    python3 tool/build_font.py path/to/spleen-8x16.bdf assets/fonts

Needs fontTools (pip install fonttools).
"""

import re
import sys
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

PX = 64  # font units per pixel: 16 px = 1024 units = 1 em
CELL_W, ASCENT, DESCENT = 8, 12, 4

# Extra glyphs, 8 x 16 cells drawn top to bottom. Row 11 sits on the
# baseline, rows 12 to 15 are below it.
EXTRA = {
    0x25C9: """
........
........
........
........
..####..
.######.
##....##
##.##.##
##.##.##
##....##
.######.
..####..
........
........
........
........""",  # ◉ level 1 heading
    0x2738: """
........
........
........
........
...##...
.#.##.#.
..####..
########
########
..####..
.#.##.#.
...##...
........
........
........
........""",  # ✸ level 3 heading
    0x273F: """
........
........
........
........
.##..##.
########
.##..##.
..#..#..
..#..#..
.##..##.
########
.##..##.
........
........
........
........""",  # ✿ level 4 heading
    0x27A4: """
........
........
........
........
........
.##.....
.####...
.######.
.######.
.####...
.##.....
........
........
........
........
........""",  # ➤ "+" list item
    0x25B8: """
........
........
........
........
........
..##....
..###...
..####..
..####..
..###...
..##....
........
........
........
........
........""",  # ▸ closed folder
    0x25BE: """
........
........
........
........
........
........
.######.
.######.
..####..
...##...
........
........
........
........
........
........""",  # ▾ open folder, folded heading
}


def parse_bdf(path):
    """Returns {codepoint: set of (x, y) pixels}, y up from the baseline."""
    text = Path(path).read_text(encoding="latin-1")
    glyphs = {}
    for m in re.finditer(r"STARTCHAR .*?\nENCODING (-?\d+)\n(.*?)BITMAP\n(.*?)ENDCHAR", text, re.S):
        enc, header, bitmap = m.groups()
        cp = int(enc)
        if cp < 0:
            continue
        w, h, xoff, yoff = map(int, re.search(r"BBX (-?\d+) (-?\d+) (-?\d+) (-?\d+)", header).groups())
        pixels = set()
        for r, row in enumerate(bitmap.split()):
            bits = len(row) * 4
            v = int(row, 16)
            for c in range(w):
                if v >> (bits - 1 - c) & 1:
                    pixels.add((xoff + c, yoff + (h - 1 - r)))
        glyphs[cp] = pixels
    return glyphs


def parse_art(art):
    rows = art.strip("\n").split("\n")
    assert len(rows) == ASCENT + DESCENT, len(rows)
    pixels = set()
    for r, row in enumerate(rows):
        assert len(row) == CELL_W, row
        for c, ch in enumerate(row):
            if ch == "#":
                pixels.add((c, ASCENT - 1 - r))
    return pixels


def outlines(pixels):
    """Traces the union of the pixel squares into closed contours: clockwise
    outer contours and counter-clockwise holes, as TrueType expects."""
    edges = set()
    for x, y in pixels:
        for e in (((x, y + 1), (x + 1, y + 1)), ((x + 1, y + 1), (x + 1, y)),
                  ((x + 1, y), (x, y)), ((x, y), (x, y + 1))):
            rev = (e[1], e[0])
            if rev in edges:
                edges.remove(rev)
            else:
                edges.add(e)
    out = {}
    for a, b in edges:
        out.setdefault(a, []).append(b)
    loops = []
    while out:
        start = next(iter(out))
        loop = [start]
        prev, cur = None, start
        while True:
            nexts = out[cur]
            if len(nexts) == 1 or prev is None:
                nxt = nexts[0]
            else:
                # Where two pixel corners touch, turn right so the shapes stay apart.
                dx, dy = cur[0] - prev[0], cur[1] - prev[1]
                right = (dy, -dx)
                nxt = next((n for n in nexts if (n[0] - cur[0], n[1] - cur[1]) == right), nexts[0])
            nexts.remove(nxt)
            if not nexts:
                del out[cur]
            prev, cur = cur, nxt
            if cur == start:
                break
            loop.append(cur)
        # Drop points in the middle of straight runs.
        simple = []
        n = len(loop)
        for i in range(n):
            p0, p1, p2 = loop[i - 1], loop[i], loop[(i + 1) % n]
            if (p1[0] - p0[0]) * (p2[1] - p1[1]) != (p1[1] - p0[1]) * (p2[0] - p1[0]):
                simple.append(p1)
        loops.append(simple)
    return loops


def build(glyphs, out_path, bold):
    order = [".notdef"]
    cmap = {}
    shapes = {".notdef": set()}
    for cp in sorted(glyphs):
        name = "space" if cp == 0x20 else f"uni{cp:04X}" if cp <= 0xFFFF else f"u{cp:05X}"
        order.append(name)
        cmap[cp] = name
        px = glyphs[cp]
        if bold:
            # Classic bitmap bold: every pixel smeared one to the right.
            px = px | {(x + 1, y) for x, y in px}
        shapes[name] = px

    fb = FontBuilder(PX * 16, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    glyf = {}
    for name in order:
        pen = TTGlyphPen(None)
        for loop in outlines(shapes[name]):
            pen.moveTo((loop[0][0] * PX, loop[0][1] * PX))
            for x, y in loop[1:]:
                pen.lineTo((x * PX, y * PX))
            pen.closePath()
        glyf[name] = pen.glyph()
    fb.setupGlyf(glyf)
    metrics = {}
    table = fb.font["glyf"]
    for name in order:
        g = table[name]
        g.recalcBounds(table)
        metrics[name] = (CELL_W * PX, getattr(g, "xMin", 0) if g.numberOfContours else 0)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=ASCENT * PX, descent=-DESCENT * PX, lineGap=0)
    style = "Bold" if bold else "Regular"
    fb.setupNameTable({
        "familyName": "Spleen",
        "styleName": style,
        "uniqueFontIdentifier": f"Spleen-{style}-OrgPad",
        "fullName": f"Spleen {style}",
        "psName": f"Spleen-{style}",
        "version": "Version 2.2.0",
        "copyright": "Copyright (c) 2018-2026, Frederic Cambus. Outline conversion for OrgPad.",
        "licenseDescription": "BSD 2-Clause License",
    })
    fb.setupOS2(
        sTypoAscender=ASCENT * PX, sTypoDescender=-DESCENT * PX, sTypoLineGap=0,
        usWinAscent=ASCENT * PX, usWinDescent=DESCENT * PX,
        sxHeight=7 * PX, sCapHeight=10 * PX,
        usWeightClass=700 if bold else 400,
        fsSelection=0x20 if bold else 0x40,
        achVendID="ORGP",
    )
    fb.font["OS/2"].panose.bProportion = 9  # monospaced
    fb.font["head"].macStyle = 1 if bold else 0
    fb.setupPost(isFixedPitch=1, underlinePosition=-2 * PX, underlineThickness=PX)
    fb.save(out_path)


def main():
    bdf, out_dir = sys.argv[1], Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    glyphs = parse_bdf(bdf)
    for cp, art in EXTRA.items():
        glyphs.setdefault(cp, parse_art(art))
    build(glyphs, out_dir / "Spleen-Regular.ttf", bold=False)
    build(glyphs, out_dir / "Spleen-Bold.ttf", bold=True)
    print(f"{len(glyphs)} glyphs written to {out_dir}")


if __name__ == "__main__":
    main()
