# Haruspex

![Haruspex](assets/icon/haruspex.png)

The logo is the alchemical symbol for earth.

A plain text editor for Linux (Android later) that uses Org mode as its
backbone. Files stay ordinary `.org` / `.txt` text, compatible with Emacs.

## Install (Linux)

Every push to `main` is built on GitHub. Download `haruspex-linux-x64.tar.gz`
from the [latest release](../../releases/tag/latest), then:

```sh
cd /tmp && tar -xzf ~/Downloads/haruspex-linux-x64.tar.gz && ./haruspex/install.sh
```

The same command updates an existing install.

## Build and run from source (Linux)

1. Install the toolchain and Flutter.

   Arch:

   ```sh
   sudo pacman -S --needed base-devel clang cmake ninja gtk3 git
   git clone https://github.com/flutter/flutter.git -b stable ~/flutter
   echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
   flutter doctor
   ```

   Debian/Ubuntu: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev`
   plus Flutter as above.

2. Build:

   ```sh
   ./build.sh            # app ends up in build/linux/x64/release/bundle/haruspex
   ./build.sh --install  # also installs to ~/.local with a menu entry
   ```

3. Run: `haruspex notes.org` (or from the app menu after `--install`).

No Flutter on your machine? Push the folder to a GitHub repository: the
included workflow (`.github/workflows/build.yml`) builds the app, runs the
tests and attaches `haruspex-linux-x64.tar.gz` to the run.

## What works in this proof of concept

- Opening and saving `.org` / `.txt` files, tabs, recent files, CRLF kept
- Highlighting: headings by level, TODO keywords (including `#+TODO:`),
  priorities, tags, emphasis, links, timestamps, planning lines, drawers,
  blocks, tables, lists, checkboxes, statistics cookies, footnotes, comments
- Folding: Tab cycles headings, drawers and blocks; Shift+Tab cycles the whole
  document; `#+STARTUP:` folding options; drawers start folded
- Structure editing: insert, promote, demote and move headings and subtrees;
  list items with renumbering; checkboxes with parent and cookie updates
- TODO cycling, priorities, tags, SCHEDULED / DEADLINE, CLOSED with
  `#+STARTUP: logdone`, repeaters (`+1w`, `++1m`, `.+2d`) with `LAST_REPEAT`
- Timestamps: insert via date picker, Shift+arrows to adjust
- Tables: auto-align, cell navigation, move / insert / delete rows and columns
- Links: http(s), `file:`, `*Heading`, `#custom-id`, `id:`, `<<targets>>`
- Agenda: day / week view with overdue items and deadline warnings, TODO list,
  search, plus extra agenda files from Settings
- Outline sidebar, find and replace, zoom, light and dark themes
- org-superstar look: bullets for headings and list items (toggle in Settings)
- org-indent look: text lines up under its heading, wrapped lines included
- Folders as vaults (like Obsidian): File > Open folder as vault, or
  `haruspex ~/notes`. File tree with new/rename/trash, Ctrl+P quick switcher,
  `[[Note name]]` links to other notes, open tabs restored, agenda over the
  whole folder. The folder gets a small `.haruspex` directory for its state.
- Look: black and orange, square and flat, after Doom Emacs. Line numbers,
  current line highlight, a mode line and echo area, a dashboard with one key
  shortcuts when nothing is open
- Bundled pixel font (Spleen 8x16), sharpest at 16 and 32 px. Any installed
  font can be picked in Settings

Shortcuts are listed under Help > Keyboard shortcuts. `Ctrl+C` with no
selection acts as Emacs's `C-c` prefix, so `C-c C-t` is Ctrl+C then T.

## Not yet

Export (HTML, PDF, Markdown), Babel code execution, clocking, capture
templates, refile and archive, table formulas, LaTeX preview, inline images,
the Android build.

## Layout

```
lib/src/org/      Org logic without UI: parsing, tables, lists, timestamps,
                  structure edits, agenda
lib/src/editor/   text controller, highlighter, folding, key handling
lib/src/ui/       window, menus, dialogs, agenda, outline, theme
assets/           pixel font and logo
tool/             scripts that generate the font and the icon
test/             unit and widget tests (flutter test)
```

## Credits

The pixel font is [Spleen](https://github.com/fcambus/spleen) by Frederic
Cambus (BSD 2-Clause, see `assets/fonts/LICENSE-Spleen.txt`), converted to
outlines by `tool/build_font.py`.
