import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruspex/main.dart';
import 'package:haruspex/src/app/font_names.dart';
import 'package:haruspex/src/app/platform.dart';
import 'package:haruspex/src/app/settings.dart';
import 'package:haruspex/src/editor/org_editor.dart';
import 'package:haruspex/src/ui/menus.dart';

Future<void> keys(WidgetTester tester, LogicalKeyboardKey key, {bool meta = false, bool alt = false, bool ctrl = false}) async {
  final held = [
    if (meta) LogicalKeyboardKey.metaLeft,
    if (alt) LogicalKeyboardKey.altLeft,
    if (ctrl) LogicalKeyboardKey.controlLeft,
  ];
  for (final k in held) {
    await tester.sendKeyDownEvent(k);
  }
  await tester.sendKeyEvent(key);
  for (final k in held.reversed) {
    await tester.sendKeyUpEvent(k);
  }
  await tester.pump();
}

void main() {
  test('key names read the Mac way', () {
    expect(macKeys('Ctrl+S / Ctrl+Shift+S'), 'Cmd+S / Cmd+Shift+S');
    expect(macKeys('Ctrl+F / Ctrl+H'), 'Cmd+F / Cmd+Shift+F');
    expect(macKeys('Ctrl+C T'), 'Ctrl+C T');
    expect(macKeys('Ctrl+C Ctrl+C'), 'Ctrl+C Ctrl+C');
    expect(macKeys('Ctrl+Enter'), 'Ctrl+Enter');
    expect(macKeys('Ctrl+Tab'), 'Ctrl+Tab');
    expect(macKeys('Ctrl+click or Ctrl+C then O'), 'Cmd+click or Ctrl+C then O');
    expect(macKeys('Alt+Shift+Left'), 'Option+Shift+Left');
  });

  test('font family names are read from the font file', () {
    expect(fontFamilies(File('assets/fonts/PCDOS-Regular.ttf')), contains('PC DOS'));
    final dir = Directory('assets/fonts');
    expect(fontFamiliesIn([dir.path]), contains('PC DOS'));
  });

  test('separators become groups in the Mac menu bar', () {
    final menus = platformMenus([
      MenuGroup('File', [
        MenuAction('New', () {}, shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true)),
        const MenuSeparator(),
        const MenuAction('Save', null),
        MenuGroup('Recent', [MenuAction('a.org', () {})]),
      ]),
    ]);
    final file = menus.single as PlatformMenu;
    expect(file.label, 'File');
    expect(file.menus, hasLength(2));
    expect(file.menus.every((m) => m is PlatformMenuItemGroup), isTrue);
    final second = (file.menus[1] as PlatformMenuItemGroup).members;
    expect(second.first.label, 'Save');
    expect(second.first.onSelected, isNull);
    expect(second[1], isA<PlatformMenu>());
  });

  testWidgets('on a Mac: Cmd for commands, Option for words, Ctrl+C for Org', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      final settings = AppSettings()..tutorialShown = true;
      await tester.pumpWidget(HaruspexApp(settings: settings, initialFiles: const []));
      await tester.pumpAndSettle();
      expect(isMac, isTrue);

      // Cmd+N leaves the dashboard with a new buffer.
      await keys(tester, LogicalKeyboardKey.keyN, meta: true);
      await tester.pumpAndSettle();
      final state = tester.state<OrgEditorState>(find.byType(OrgEditor).first);
      final c = state.doc.controller;
      c.value = const TextEditingValue(text: 'one two three\nnext line', selection: TextSelection.collapsed(offset: 0));
      state.doc.focusNode.requestFocus();
      await tester.pump();

      // Option+Right: next word. Cmd+Right: end of the line.
      await keys(tester, LogicalKeyboardKey.arrowRight, alt: true);
      expect(c.selection.extentOffset, 3);
      await keys(tester, LogicalKeyboardKey.arrowRight, meta: true);
      expect(c.selection.extentOffset, 13);
      // Option+Backspace deletes a word.
      await keys(tester, LogicalKeyboardKey.backspace, alt: true);
      expect(c.text.startsWith('one two \n'), isTrue);
      // Cmd+Z undoes it.
      await keys(tester, LogicalKeyboardKey.keyZ, meta: true);
      expect(c.text, 'one two three\nnext line');
      // Cmd+Down: end of the document.
      await keys(tester, LogicalKeyboardKey.arrowDown, meta: true);
      expect(c.selection.extentOffset, c.text.length);
      // Cmd+A selects everything.
      await keys(tester, LogicalKeyboardKey.keyA, meta: true);
      expect(c.selection.start, 0);
      expect(c.selection.end, c.text.length);
      // Ctrl+C starts the Org prefix even with a selection.
      await keys(tester, LogicalKeyboardKey.keyC, ctrl: true);
      expect(find.text('C-c-'), findsOneWidget);
      await keys(tester, LogicalKeyboardKey.escape);
      expect(find.text('C-c-'), findsNothing);
      // Cmd+B opens a scratch buffer.
      await keys(tester, LogicalKeyboardKey.keyB, meta: true);
      await tester.pumpAndSettle();
      expect(find.text('*scratch*'), findsWidgets);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
