#!/usr/bin/env python3
"""Draws the OrgPad app icon: 16 x 16 pixel art scaled up without smoothing.

    python3 tool/build_icon.py assets/icon/orgpad.png
"""
import sys

from PIL import Image

ART = """
################
#..............#
#.OOO..OOOOOOO.#
#.O.O..........#
#.OOO..........#
#..............#
#....tttttttt..#
#....tttttt....#
#..............#
#..AA..AAAAA...#
#..AA..........#
#..............#
#.....ttttttt..#
#.....tttt.CC..#
#..............#
################
"""

COLORS = {
    "#": (255, 159, 28),   # frame, orange
    ".": (15, 14, 12),     # background
    "O": (255, 159, 28),   # level 1 bullet and heading
    "A": (255, 200, 87),   # level 2, amber
    "t": (122, 110, 92),   # body text
    "C": (255, 241, 214),  # caret
}


def main():
    rows = ART.strip().split("\n")
    img = Image.new("RGBA", (16, 16))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            img.putpixel((x, y), COLORS[ch] + (255,))
    img.resize((256, 256), Image.NEAREST).save(sys.argv[1])


if __name__ == "__main__":
    main()
