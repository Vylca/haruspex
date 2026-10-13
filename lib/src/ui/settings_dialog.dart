import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app/settings.dart';
import '../editor/org_theme.dart';

Future<List<String>>? _fontList;

Widget _fontPicker(AppSettings s, String label, String value, void Function(String) onChanged) {
  return FutureBuilder<List<String>>(
    future: _fontList ??= systemFontFamilies(),
    builder: (context, snap) {
      final fonts = <String>{...?snap.data, value}.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownMenu<String>(
          key: ValueKey('$label|$value|${fonts.length}'),
          width: 440,
          menuHeight: 320,
          enableFilter: true,
          requestFocusOnTap: true,
          initialSelection: value,
          dropdownMenuEntries: [
            for (final f in fonts) DropdownMenuEntry<String>(value: f, label: f),
          ],
          onSelected: (v) {
            if (v != null) onChanged(v);
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text('* TODO The quick brown fox  :tag:', style: TextStyle(fontFamily: value, fontSize: s.fontSize)),
        ),
      ]);
    },
  );
}

Future<void> showSettingsDialog(BuildContext context, AppSettings settings) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: settings,
      builder: (ctx, _) {
        final s = settings;
        return AlertDialog(
          title: const Text('Settings'),
          content: SizedBox(
            width: 480,
            child: ListView(shrinkWrap: true, children: [
              const _Label('Editor font'),
              _fontPicker(s, 'Text', s.fontFamily, (v) => s.update((x) => x.fontFamily = v)),
              const _Label('Code and table font'),
              _fontPicker(s, 'Code', s.codeFontFamily, (v) => s.update((x) => x.codeFontFamily = v)),
              _Label('Font size: ${s.fontSize.round()}  (the pixel font is sharpest at 16 and 32)'),
              Slider(
                min: 9,
                max: 40,
                divisions: 31,
                value: s.fontSize.clamp(9.0, 40.0),
                onChanged: (v) => s.update((x) => x.fontSize = v),
              ),
              _Label('Line spacing: ${s.lineHeight.toStringAsFixed(2)}'),
              Slider(
                min: 1.0,
                max: 2.2,
                divisions: 24,
                value: s.lineHeight.clamp(1.0, 2.2),
                onChanged: (v) => s.update((x) => x.lineHeight = v),
              ),
              const _Label('Display'),
              _check('Line numbers', s.lineNumbers, (v) => s.update((x) => x.lineNumbers = v)),
              _check('Hide markup away from the caret', s.hideMarkup, (v) => s.update((x) => x.hideMarkup = v)),
              _check('Indent text under its heading (org-indent)', s.indentBody, (v) => s.update((x) => x.indentBody = v)),
              _check('Bullets instead of stars (org-superstar)', s.superstar, (v) => s.update((x) => x.superstar = v)),
              _check('Larger top-level headings', s.scaleHeadings, (v) => s.update((x) => x.scaleHeadings = v)),
              _check('Fold drawers when opening files', s.foldDrawers, (v) => s.update((x) => x.foldDrawers = v)),
              const _Label('Agenda files'),
              const Text('Open documents and the open folder are always included.'),
              for (final f in s.agendaFiles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(f, overflow: TextOverflow.ellipsis),
                  trailing: TextButton(
                    onPressed: () => s.update((x) => x.agendaFiles = [...x.agendaFiles]..remove(f)),
                    child: const Text('remove'),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () async {
                    final files = await openFiles(acceptedTypeGroups: const [
                      XTypeGroup(label: 'Org', extensions: ['org', 'txt']),
                    ]);
                    if (files.isEmpty) return;
                    s.update((x) => x.agendaFiles = {...x.agendaFiles, ...files.map((f) => f.path)}.toList());
                  },
                  child: const Text('Add files…'),
                ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
        );
      },
    ),
  );
}

Widget _check(String label, bool value, ValueChanged<bool> onChanged) => CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
      value: value,
      onChanged: (v) => onChanged(v ?? false),
    );

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(text, style: TextStyle(color: OrgTheme.hev.levels[1])),
      );
}
