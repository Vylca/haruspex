import 'package:flutter/material.dart';

const keyBindings = <(String, List<(String, String)>)>[
  ('Visibility', [
    ('Tab', 'Cycle heading / drawer / block, next table cell'),
    ('Shift+Tab', 'Cycle whole document: overview, contents, all'),
  ]),
  ('Structure', [
    ('Alt+Enter', 'New heading, item or table row'),
    ('Alt+Shift+Enter', 'New TODO heading or checkbox item'),
    ('Ctrl+Enter', 'New heading after the current subtree'),
    ('Alt+Left / Right', 'Promote / demote heading or item'),
    ('Alt+Shift+Left / Right', 'Promote / demote subtree'),
    ('Alt+Up / Down', 'Move subtree, item, table row or line'),
    ('Ctrl+C *', 'Toggle heading'),
  ]),
  ('TODO and metadata', [
    ('Ctrl+C T', 'Cycle TODO keyword'),
    ('Shift+Left / Right', 'Cycle TODO (caret on stars or keyword)'),
    ('Shift+Up / Down', 'Change priority (caret on stars or keyword)'),
    ('Ctrl+C ,', 'Set priority'),
    ('Ctrl+C Q', 'Set tags'),
    ('Ctrl+C S / D', 'Schedule / deadline'),
    ('Ctrl+C . / !', 'Insert or edit active / inactive timestamp'),
    ('Shift+arrows on a date', 'Change day / field'),
  ]),
  ('Lists and checkboxes', [
    ('Ctrl+C Ctrl+C', 'Toggle checkbox, align table, update cookie, tags on heading'),
    ('Ctrl+C X', 'Add or remove a checkbox'),
    ('Ctrl+C -', 'Cycle bullet type / insert table rule'),
    ('Ctrl+C #', 'Update statistics cookies'),
  ]),
  ('Tables', [
    ('|', 'Start a table row'),
    ('Ctrl+C |', 'Insert a new table'),
    ('Tab / Shift+Tab', 'Next / previous cell (realigns)'),
    ('Enter', 'Next row (at end of line: plain newline)'),
    ('Alt+arrows', 'Move column / row'),
    ('Alt+Shift+arrows', 'Insert / delete column / row'),
  ]),
  ('Links and navigation', [
    ('Ctrl+C L', 'Insert or edit link'),
    ('Ctrl+C O, Ctrl+click', 'Open link'),
    ('Ctrl+C N / P', 'Next / previous heading'),
    ('Ctrl+C F / B', 'Next / previous sibling'),
    ('Ctrl+C U', 'Parent heading'),
    ('Ctrl+C A', 'Agenda'),
  ]),
  ('Files and view', [
    ('Ctrl+N', 'New note (in the open folder) or new file'),
    ('Ctrl+O', 'Open file'),
    ('Ctrl+P', 'Quick switcher: find or create a note in the folder'),
    ('Ctrl+Shift+E', 'Toggle the file tree'),
    ('Ctrl+S / Ctrl+Shift+S', 'Save / save as'),
    ('Ctrl+W / Ctrl+Q', 'Close tab / quit'),
    ('Ctrl+Tab', 'Next tab'),
    ('Ctrl+F / Ctrl+H', 'Find / replace'),
    ('Ctrl+Z / Ctrl+Shift+Z', 'Undo / redo'),
    ('Ctrl+= / Ctrl+- / Ctrl+0', 'Zoom in / out / reset'),
    ('Ctrl+Shift+O', 'Toggle outline'),
    ('Right click', 'Cut, copy, paste; in the file tree: new, rename, trash'),
  ]),
];

Future<void> showKeyBindings(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: ListView(children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Ctrl+C with no selection starts an Org command (like C-c in Emacs). '
                'With a selection it copies. Escape cancels.'),
          ),
          for (final (section, rows) in keyBindings) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(section, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final (k, d) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 200, child: Text(k, style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
                  Expanded(child: Text(d)),
                ]),
              ),
          ],
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
    ),
  );
}
