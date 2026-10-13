import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:haruspex/src/app/vault.dart';
import 'package:haruspex/src/org/agenda.dart';
import 'package:haruspex/src/org/analysis.dart';
import 'package:haruspex/src/org/edits.dart';
import 'package:haruspex/src/org/syntax.dart';
import 'package:haruspex/src/org/table.dart';
import 'package:haruspex/src/org/timestamp.dart';

int offsetOf(String text, String marker) {
  final i = text.indexOf(marker);
  if (i < 0) throw StateError('marker $marker not found');
  return i;
}

void main() {
  group('syntax', () {
    test('parses headings with keyword, priority and tags', () {
      final cfg = TodoConfig.defaults;
      final line = '** TODO [#A] Write the report   :work:urgent:';
      final h = HeadingInfo.parse(line, cfg)!;
      expect(h.level, 2);
      expect(h.keyword, 'TODO');
      expect(h.priority, 'A');
      expect(h.title(line), 'Write the report');
      expect(h.tags, ['work', 'urgent']);
      expect(HeadingInfo.parse('*bold* text', cfg), isNull);
    });

    test('reads custom TODO sequences', () {
      final cfg = TodoConfig.parse(['TODO(t) NEXT | DONE(d!) CANCELED']);
      expect(cfg.all, ['TODO', 'NEXT', 'DONE', 'CANCELED']);
      expect(cfg.next(null), 'TODO');
      expect(cfg.next('NEXT'), 'DONE');
      expect(cfg.next('CANCELED'), isNull);
      expect(cfg.isDone('CANCELED'), isTrue);
    });
  });

  group('analysis', () {
    const doc = '#+TITLE: T\n* A\ntext\n** A1\n** A2\n* B\n:PROPERTIES:\n:ID: x\n:END:\n';
    test('structure', () {
      final a = OrgAnalysis(doc);
      expect(a.headingLines, [1, 3, 4, 5]);
      expect(a.subtreeEnd(1), 5);
      expect(a.bodyEnd(1), 3);
      expect(a.childHeadings(1), [3, 4]);
      expect(a.keywords['TITLE'], 'T');
      expect(a.properties(5)['ID'], 'x');
      expect(a.infos[6].kind, LineKind.drawerBegin);
    });
  });

  group('timestamps', () {
    test('format and shift', () {
      final ts = OrgTimestamp.parse('<2026-10-11 Sun 09:30 +1w>')!;
      expect(ts.format(), '<2026-10-11 Sun 09:30 +1w>');
      expect(ts.addDays(1).format(), '<2026-10-12 Mon 09:30 +1w>');
      expect(ts.repeated(DateTime(2026, 10, 11))!.format(), '<2026-10-18 Sun 09:30 +1w>');
    });

    test('catch-up repeater', () {
      final ts = OrgTimestamp.parse('<2026-10-01 Thu ++1w>')!;
      expect(ts.repeated(DateTime(2026, 10, 20))!.format(), '<2026-10-22 Thu ++1w>');
    });
  });

  group('tables', () {
    test('aligns and moves to the next cell', () {
      final lines = ['|a|bb|', '|-', '|ccc|1|'];
      final r = tableOperation(lines, 0, 1, TableOp.nextField)!;
      expect(r.lines, ['| a   | bb |', '|-----+----|', '| ccc | 1  |']);
      expect(r.caretLine, 0);
      expect(r.caretCol, 8);
    });
  });

  group('edits', () {
    test('cycles TODO keywords', () {
      const text = '* Task\nbody';
      var r = cycleTodo(OrgAnalysis(text), 2)!;
      expect(r.text, '* TODO Task\nbody');
      r = cycleTodo(OrgAnalysis(r.text), 2)!;
      expect(r.text, '* DONE Task\nbody');
      r = cycleTodo(OrgAnalysis(r.text), 2)!;
      expect(r.text, '* Task\nbody');
    });

    test('repeating task goes back to TODO and shifts the date', () {
      const text = '* TODO Water plants\nSCHEDULED: <2026-10-11 Sun +1w>\n';
      final r = cycleTodo(OrgAnalysis(text), 3, now: DateTime(2026, 10, 11))!;
      expect(r.text.startsWith('* TODO Water plants\nSCHEDULED: <2026-10-18 Sun +1w>\n:PROPERTIES:\n:LAST_REPEAT:'), isTrue);
    });

    test('inserts a heading after the body', () {
      const text = '* A\nbody\n* B';
      final r = insertHeading(OrgAnalysis(text), 3);
      expect(r.text, '* A\nbody\n* \n* B');
      expect(r.selection.extent, offsetOf(r.text, '* \n* B') + 2);
    });

    test('moves a subtree down', () {
      const text = '* A\na\n* B\nb';
      final r = moveSubtree(OrgAnalysis(text), 0, up: false)!;
      expect(r.text, '* B\nb\n* A\na');
      expect(r.lineMap![0], 2);
    });

    test('demotes a subtree', () {
      const text = '* A\n** A1\n* B';
      final r = changeHeadingLevel(OrgAnalysis(text), 0, 1, subtree: true)!;
      expect(r.text, '** A\n*** A1\n* B');
    });

    test('checkbox toggle updates cookies', () {
      const text = '* List [0/2]\n- [ ] one\n- [ ] two';
      final r = toggleCheckbox(OrgAnalysis(text), offsetOf(text, 'one'))!;
      expect(r.text, '* List [1/2]\n- [X] one\n- [ ] two');
    });

    test('new list item renumbers', () {
      const text = '1. one\n2. two';
      final r = insertItem(OrgAnalysis(text), offsetOf(text, 'one') + 3)!;
      expect(r.text, '1. one\n2. \n3. two');
    });

    test('sets scheduling', () {
      const text = '* TODO X\nbody';
      final ts = OrgTimestamp(active: true, date: DateTime(2026, 10, 12));
      final r = setPlanning(OrgAnalysis(text), 0, 'SCHEDULED', ts)!;
      expect(r.text, '* TODO X\nSCHEDULED: <2026-10-12 Mon>\nbody');
    });

    test('sets tags aligned to column 77', () {
      const text = '* Title';
      final r = setTags(OrgAnalysis(text), 0, ['a', 'b'])!;
      expect(r.text.length, 77);
      expect(r.text.endsWith(' :a:b:'), isTrue);
    });
  });

  group('agenda', () {
    test('scheduled, overdue and deadline warnings', () {
      const text = '* TODO A\nSCHEDULED: <2026-10-05 Mon>\n* TODO B\nDEADLINE: <2026-10-15 Thu>\n';
      final days = buildAgenda([AgendaSource('1', 'f', text)], DateTime(2026, 10, 12), 7,
          today: DateTime(2026, 10, 12));
      final today = days.first.items.map((i) => '${i.title}:${i.label}').toList();
      expect(today, containsAll(['A:Sched. 7x', 'B:In 3 d.']));
      expect(days[3].items.single.label, 'Deadline');
    });
  });

  group('files', () {
    test('rename keeps the extension and never replaces a file', () async {
      final dir = await Directory.systemTemp.createTemp('haruspex');
      try {
        final a = File('${dir.path}/a.org')..writeAsStringSync('a');
        File('${dir.path}/b.org').writeAsStringSync('b');
        final c = await renameEntry(a.path, 'c');
        expect(c, '${dir.path}/c.org');
        expect(File(c).readAsStringSync(), 'a');
        await expectLater(renameEntry(c, 'b'), throwsA(isA<FileSystemException>()));
        await expectLater(renameEntry(c, 'x/y'), throwsA(isA<FileSystemException>()));
        expect(File('${dir.path}/b.org').readAsStringSync(), 'b');
        expect(await renameEntry(c, 'notes.txt'), '${dir.path}/notes.txt');
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('incremental analysis', () {
    String doc() {
      final b = StringBuffer('#+TITLE: T\n#+TODO: TODO NEXT | DONE\n');
      for (var i = 0; i < 400; i++) {
        b.writeln('* TODO Heading $i  :t:');
        b.writeln(':PROPERTIES:');
        b.writeln(':ID: $i');
        b.writeln(':END:');
        b.writeln('Body text $i with *bold*.');
        b.writeln('#+BEGIN_SRC dart');
        b.writeln('code $i');
        b.writeln('#+END_SRC');
        b.writeln('- item');
        b.writeln('| a | b |');
        b.writeln('');
      }
      return b.toString();
    }

    void same(OrgAnalysis inc, OrgAnalysis full, String what) {
      expect(inc.lines, full.lines, reason: '$what: lines');
      expect(inc.lineStarts, full.lineStarts, reason: '$what: starts');
      expect([for (final i in inc.infos) '${i.kind}|${i.blockType}|${i.heading?.level}'],
          [for (final i in full.infos) '${i.kind}|${i.blockType}|${i.heading?.level}'],
          reason: '$what: kinds');
      expect(inc.headingLines, full.headingLines, reason: '$what: headings');
      expect(inc.regionEnd, full.regionEnd, reason: '$what: regions');
      expect(inc.keywords, full.keywords, reason: '$what: keywords');
    }

    test('matches a full parse after random edits', () {
      final rnd = Random(7);
      const pieces = ['x', ' ', '\n', '\n\n', '*', '* New', '#+', '#+END_SRC', ':END:', ':FOO:', '|', '- ', 'abc\ndef'];
      var a = OrgAnalysis(doc());
      expect(a.lineCount, greaterThan(2000));
      for (var n = 0; n < 400; n++) {
        final t = a.text;
        final at = rnd.nextInt(t.length);
        String next;
        switch (rnd.nextInt(3)) {
          case 0:
            next = t.replaceRange(at, at, pieces[rnd.nextInt(pieces.length)]);
          case 1:
            next = t.replaceRange(at, (at + 1 + rnd.nextInt(30)).clamp(0, t.length), '');
          default:
            next = t.replaceRange(at, (at + rnd.nextInt(5)).clamp(0, t.length), pieces[rnd.nextInt(pieces.length)]);
        }
        final inc = OrgAnalysis.update(a, next);
        same(inc, OrgAnalysis(next), 'edit $n at $at');
        a = inc;
      }
    });
  });
}
