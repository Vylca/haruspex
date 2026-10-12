const tutorialText = r'''#+TITLE: Welcome to OrgPad
#+TODO: TODO NEXT WAITING | DONE CANCELED
#+STARTUP: showall

OrgPad is a plain text editor that understands Org mode. Everything you see
is ordinary text saved to an .org or .txt file. Put the caret on a heading
and press Tab to fold it. Shift+Tab cycles the whole document.

* Headings and folding
Headings start with stars. More stars, deeper level.
** Tab on a heading cycles FOLDED, CHILDREN, SUBTREE
Try it on the heading above.
** Alt+Left / Alt+Right promote and demote
Add Shift to move the whole subtree.
** Alt+Up / Alt+Down move a subtree past its siblings
** Alt+Enter inserts a new heading
Ctrl+Enter inserts one after the current subtree.

* TODO Keywords, priorities and tags                                  :demo:
Ctrl+C then T cycles the keyword. Shift+Left/Right does the same when the
caret is on the stars or keyword. Shift+Up/Down there changes the priority.
Ctrl+C then Q edits tags.
** NEXT [#A] Write the introduction                              :writing:
** WAITING Reply from the editor
** DONE Pick a title
   CLOSED: [2026-10-01 Thu 18:20]

* Lists and checkboxes [1/3]
- [X] Alt+Enter on an item adds a new item
- [ ] Ctrl+C Ctrl+C toggles a checkbox
- [ ] Shift+Left/Right on a bullet changes its type
  1. Alt+Left/Right indents and outdents items
  2. Alt+Up/Down reorders them

- term :: description lists work too

* Dates and the agenda
** TODO Weekly review
   SCHEDULED: <2026-10-12 Mon +1w>
Ctrl+C then S schedules, Ctrl+C then D sets a deadline, Ctrl+C then . inserts
a timestamp. Shift+arrows on a timestamp change it. Ctrl+C then A opens the
agenda.
** TODO Hand in the draft
   DEADLINE: <2026-10-20 Tue -5d>

* Tables
Type | to start a row. Tab realigns and moves to the next cell, Enter
goes to the next row, Alt+arrows move rows and columns.

| Item     | Qty | Price |
|----------+-----+-------|
| Notebook |   2 |  4.50 |
| Pencils  |  12 |  0.80 |

* Markup and links
You can write *bold*, /italic/, _underline_, +strike+, =verbatim= and ~code~.
Markup characters hide when the caret leaves the line.

Links: [[https://orgmode.org][the Org mode site]] or [[*Tables][a heading in this file]].
Ctrl+click or Ctrl+C then O opens a link. Ctrl+C then L inserts one.

#+BEGIN_SRC python
def hello():
    print("Blocks fold with Tab on the BEGIN line")
#+END_SRC

#+BEGIN_QUOTE
Quotes, examples and other blocks are highlighted too.
#+END_QUOTE

* Folders
File > Open folder as vault turns a folder of .org files into a notebook
with a file tree. Ctrl+P finds or creates a note, and a link like
[[Other note]] opens the note with that name.

* Drawers
:PROPERTIES:
:CUSTOM_ID: drawers
:CREATED:  [2026-10-11 Sun]
:END:
Property drawers start folded. Put the caret on :PROPERTIES: and press Tab.
''';
