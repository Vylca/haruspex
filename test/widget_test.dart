import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruspex/main.dart';
import 'package:haruspex/src/app/settings.dart';
import 'package:haruspex/src/editor/org_controller.dart';
import 'package:haruspex/src/editor/org_editor.dart';

Future<OrgEditorState> startEditor(WidgetTester tester, String text) async {
  await tester.binding.setSurfaceSize(const Size(1200, 800));
  final settings = AppSettings()..tutorialShown = true;
  await tester.pumpWidget(HaruspexApp(settings: settings, initialFiles: const []));
  await tester.pumpAndSettle();
  // The dashboard shows at start. Ctrl+N opens an empty buffer.
  if (find.byType(OrgEditor).evaluate().isEmpty) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }
  final state = tester.state<OrgEditorState>(find.byType(OrgEditor).first);
  state.doc.controller.value = TextEditingValue(text: text, selection: const TextSelection.collapsed(offset: 0));
  state.doc.focusNode.requestFocus();
  await tester.pump();
  return state;
}

void main() {
  testWidgets('folding, structure editing and global cycling', (tester) async {
    final state = await startEditor(tester, '* A\nbody\n\nmore\n* B\n| a | b |');
    final OrgController c = state.doc.controller;

    c.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.folds, contains(0));
    expect(c.hiddenLines, [(1, 4)]);
    expect(c.visibleLines, [0, 4, 5]);

    // Right arrow at the end of the folded heading skips the hidden lines.
    c.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.selection.extentOffset, c.text.indexOf('* B'));

    // Demote keeps the fold.
    c.selection = const TextSelection.collapsed(offset: 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(c.text.startsWith('** A\n'), isTrue);
    expect(c.folds, contains(0));

    // Global cycling.
    c.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(c.globalVisibility, GlobalVisibility.overview);
    expect(c.folds, containsAll([0, 4]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing keys, newline, backspace and undo', (tester) async {
    final state = await startEditor(tester, 'ab');
    final c = state.doc.controller;
    c.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    state.updateEditingValue(const TextEditingValue(text: 'abc', selection: TextSelection.collapsed(offset: 3)));
    await tester.pump();
    expect(c.text, 'abc');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.text, 'abc\n');

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(c.text, 'abc');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(c.selection.extentOffset, 2);

    state.undo();
    await tester.pump();
    expect(c.text, 'abc\n');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+C prefix runs Org commands', (tester) async {
    final state = await startEditor(tester, '* Task');
    final c = state.doc.controller;
    c.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.text, '* TODO Task');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+mouse wheel zooms instead of scrolling', (tester) async {
    final state = await startEditor(tester, List.generate(200, (i) => 'line $i').join('\n'));
    final settings = state.widget.settings;
    final before = settings.fontSize;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(tester.getCenter(find.byType(OrgEditor)));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -53)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(settings.fontSize, before + 1);
    expect(state.doc.scroll.offset, 0);

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 53)));
    await tester.pump();
    expect(settings.fontSize, before + 1);
    expect(state.doc.scroll.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
