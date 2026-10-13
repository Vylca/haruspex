// Stress tests: large documents, long lines, big tables and big vaults.
// They print timings (see the CI log) and fail only on runaway slowness.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruspex/main.dart';
import 'package:haruspex/src/app/settings.dart';
import 'package:haruspex/src/app/vault.dart';
import 'package:haruspex/src/editor/org_editor.dart';
import 'package:haruspex/src/org/analysis.dart';
import 'package:haruspex/src/org/table.dart';

/// About 14 lines per section, with most Org features on every section.
String bigOrg(int sections) {
  final b = StringBuffer('#+TITLE: Stress\n#+TODO: TODO NEXT | DONE\n\n');
  for (var i = 0; i < sections; i++) {
    b.writeln('* ${i.isEven ? 'TODO' : 'DONE'} [#A] Heading number $i with some words  :tag$i:work:');
    b.writeln('  SCHEDULED: <2026-10-${(i % 28 + 1).toString().padLeft(2, '0')} Tue +1w>');
    b.writeln('  :PROPERTIES:');
    b.writeln('  :ID: id-$i');
    b.writeln('  :END:');
    b.writeln('** Sub heading $i');
    b.writeln('Some *bold* and /italic/ text, a [[https://example.com/$i][link]] and =code= number $i.');
    b.writeln('- [ ] first item [1/2]');
    b.writeln('- [X] second item');
    b.writeln('| a | b | c |');
    b.writeln('|---+---+---|');
    b.writeln('| $i | ${i * 2} | x |');
    b.writeln();
  }
  return b.toString();
}

void report(String what, Stopwatch sw, [int count = 1]) {
  final ms = sw.elapsedMicroseconds / 1000;
  final per = count > 1 ? ', ${(ms / count).toStringAsFixed(2)} ms each' : '';
  print('STRESS $what: ${ms.toStringAsFixed(1)} ms$per');
}

Future<OrgEditorState> openEditor(WidgetTester tester, String text) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  final settings = AppSettings()..tutorialShown = true;
  await tester.pumpWidget(HaruspexApp(settings: settings, initialFiles: const []));
  await tester.pumpAndSettle();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  final state = tester.state<OrgEditorState>(find.byType(OrgEditor).first);
  final sw = Stopwatch()..start();
  state.doc.controller.value = TextEditingValue(text: text, selection: const TextSelection.collapsed(offset: 0));
  state.doc.focusNode.requestFocus();
  await tester.pump();
  report('load ${text.length ~/ 1024} KB into the editor', sw);
  return state;
}

Future<void> type(WidgetTester tester, OrgEditorState state, String chars) async {
  for (final ch in chars.split('')) {
    final v = state.doc.controller.value;
    final at = v.selection.extentOffset;
    final text = v.text.replaceRange(at, at, ch);
    state.updateEditingValue(TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at + 1)));
    await tester.pump();
  }
}

Future<void> key(WidgetTester tester, LogicalKeyboardKey k, {bool ctrl = false, bool shift = false}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(k);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  test('parsing a 140k line document', () {
    final text = bigOrg(10000);
    final sw = Stopwatch()..start();
    final a = OrgAnalysis(text);
    report('parse ${a.lineCount} lines (${text.length ~/ 1024} KB)', sw);
    expect(a.headingLines.length, 20000);
    expect(sw.elapsedMilliseconds, lessThan(5000));
  });

  test('aligning a 2000 row table', () {
    final lines = [
      '| name | value | note |',
      '|-',
      for (var i = 0; i < 2000; i++) '| row $i | ${i * 37} | ${'x' * (i % 40)} |',
    ];
    final sw = Stopwatch()..start();
    final r = tableOperation(lines, 5, 3, TableOp.align);
    report('align a ${lines.length} row table', sw);
    expect(r, isNotNull);
    expect(sw.elapsedMilliseconds, lessThan(5000));
  });

  test('scanning a vault of 3000 notes', () async {
    final dir = await Directory.systemTemp.createTemp('haruspex_vault');
    try {
      for (var d = 0; d < 30; d++) {
        final sub = await Directory('${dir.path}/folder $d/inner').create(recursive: true);
        for (var n = 0; n < 50; n++) {
          await File('${dir.path}/folder $d/note $n.org').writeAsString('* Note $n\n');
          await File('${sub.path}/deep $n.org').writeAsString('* Deep $n\n');
        }
      }
      final v = Vault(dir.path);
      final sw = Stopwatch()..start();
      await v.init();
      report('scan a vault of ${v.notes.length} notes', sw);
      expect(v.notes.length, 3000);
      v.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  testWidgets('editing a large document', (tester) async {
    final state = await openEditor(tester, bigOrg(5000));
    final c = state.doc.controller;

    var sw = Stopwatch()..start();
    await type(tester, state, 'typed at the top ');
    report('type 17 characters at the top', sw, 17);

    sw = Stopwatch()..start();
    await key(tester, LogicalKeyboardKey.end, ctrl: true);
    report('jump to the end', sw);
    expect(c.selection.extentOffset, c.text.length);

    sw = Stopwatch()..start();
    await type(tester, state, 'typed at the end ');
    report('type 17 characters at the end', sw, 17);

    sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await key(tester, LogicalKeyboardKey.backspace);
    }
    report('20 backspaces', sw, 20);

    sw = Stopwatch()..start();
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.tab, shift: true);
    }
    report('cycle global visibility 3 times', sw, 3);

    sw = Stopwatch()..start();
    for (var i = 0; i < 40; i++) {
      await key(tester, LogicalKeyboardKey.pageUp);
    }
    report('40 page ups', sw, 40);

    sw = Stopwatch()..start();
    state.undo();
    await tester.pump();
    report('undo', sw);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single very long line', (tester) async {
    final line = List.generate(20000, (i) => 'word$i').join(' ');
    final state = await openEditor(tester, '* Long\n$line\n* After');
    final sw = Stopwatch()..start();
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.end);
    await type(tester, state, ' tail');
    report('move and type on a ${line.length} character line', sw);
    expect(state.doc.controller.text.contains('tail'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('many open buffers', (tester) async {
    final state = await openEditor(tester, bigOrg(200));
    final sw = Stopwatch()..start();
    for (var i = 0; i < 40; i++) {
      await key(tester, LogicalKeyboardKey.keyB, ctrl: true);
    }
    await tester.pumpAndSettle();
    report('open 40 scratch buffers', sw, 40);
    expect(find.byType(OrgEditor), findsNWidgets(41));
    expect(state.mounted, isTrue);
    expect(tester.takeException(), isNull);
  });
}
