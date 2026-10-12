import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app/settings.dart';

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
          label: Text(label),
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
          child: Text('* TODO The quick brown fox  :tag:', style: TextStyle(fontFamily: value, fontSize: 15)),
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
              const _Label('Theme'),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => s.update((x) => x.themeMode = v.first),
              ),
              const _Label('Editor font'),
              _fontPicker(s, 'Text', s.fontFamily, (v) => s.update((x) => x.fontFamily = v)),
              const _Label('Code and table font'),
              _fontPicker(s, 'Code', s.codeFontFamily, (v) => s.update((x) => x.codeFontFamily = v)),
              _Label('Font size: ${s.fontSize.round()}'),
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
              _Label('Text column width: ${s.maxWidth.round()} px'),
              Slider(
                min: 500,
                max: 2000,
                divisions: 30,
                value: s.maxWidth.clamp(500.0, 2000.0),
                onChanged: (v) => s.update((x) => x.maxWidth = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hide markup away from the caret'),
                subtitle: const Text('Link brackets and emphasis markers show only on the current line'),
                value: s.hideMarkup,
                onChanged: (v) => s.update((x) => x.hideMarkup = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Indent text under its heading (org-indent)'),
                value: s.indentBody,
                onChanged: (v) => s.update((x) => x.indentBody = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bullets instead of stars (org-superstar)'),
                value: s.superstar,
                onChanged: (v) => s.update((x) => x.superstar = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Larger top-level headings'),
                value: s.scaleHeadings,
                onChanged: (v) => s.update((x) => x.scaleHeadings = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fold drawers when opening files'),
                value: s.foldDrawers,
                onChanged: (v) => s.update((x) => x.foldDrawers = v),
              ),
              const _Label('Agenda files'),
              const Text('Open documents are always included.', style: TextStyle(fontSize: 12)),
              for (final f in s.agendaFiles)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(f, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => s.update((x) => x.agendaFiles = [...x.agendaFiles]..remove(f)),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add files…'),
                  onPressed: () async {
                    final files = await openFiles(acceptedTypeGroups: const [
                      XTypeGroup(label: 'Org', extensions: ['org', 'txt']),
                    ]);
                    if (files.isEmpty) return;
                    s.update((x) => x.agendaFiles = {...x.agendaFiles, ...files.map((f) => f.path)}.toList());
                  },
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

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}
