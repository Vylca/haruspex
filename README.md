# OrgPad

A plain text editor for Linux (Android later) that uses Org mode as its
backbone. Files stay ordinary `.org` / `.txt` text, compatible with Emacs.

## Build and run (Linux)

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
   ./build.sh            # app ends up in build/linux/x64/release/bundle/orgpad
   ./build.sh --install  # also installs to ~/.local with a menu entry
   ```

3. Run: `orgpad notes.org` (or from the app menu after `--install`).

No Flutter on your machine? Push the folder to a GitHub repository: the
included workflow (`.github/workflows/build.yml`) builds the app, runs the
tests and attaches `orgpad-linux-x64.tar.gz` to the run.

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
  `orgpad ~/notes`. File tree with new/rename/trash, Ctrl+P quick switcher,
  `[[Note name]]` links to other notes, open tabs restored, agenda over the
  whole folder. The folder gets a small `.orgpad` directory for its state.
- Any installed font (Settings), monospace by default

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
lib/src/ui/       window, menus, dialogs, agenda, outline
test/             unit and widget tests (flutter test)
```
