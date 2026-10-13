import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruspex/src/app/spelling.dart';
import 'package:haruspex/src/org/analysis.dart';
import 'package:haruspex/src/org/spell_scan.dart';
import 'package:haruspex_hunspell/haruspex_hunspell.dart';

import 'widget_test.dart' show startEditor;

/// The words spellWords picks from line [i] of [text].
List<String> words(String text, [int i = 0]) {
  final a = OrgAnalysis(text);
  final line = a.lines[i];
  return [for (final r in spellWords(a.infos[i], line)) line.substring(r.start, r.end)];
}

/// The library built by `flutter build linux` (CI builds before testing).
const _built = 'build/linux/x64/release/bundle/lib/libharuspex_hunspell.so';

void main() {
  group('words to check', () {
    test('plain text, with elisions and compounds kept whole', () {
      expect(words("Il dit qu'il viendra peut-être, l’opposition aussi."),
          ['Il', 'dit', "qu'il", 'viendra', 'peut-être', 'l’opposition', 'aussi']);
    });

    test('heading: only the title', () {
      expect(words('** TODO [#A] Écrire le rapport [1/3]   :travail:urgent:'), ['Écrire', 'le', 'rapport']);
    });

    test('list items skip bullets and checkboxes', () {
      expect(words('- [X] premier élément'), ['premier', 'élément']);
      expect(words('  1. second item'), ['second', 'item']);
    });

    test('markup: emphasis is checked, code and links are not', () {
      expect(words('un mot *gras* et /italique/ mais pas =codeX= ni ~verbatimX~'),
          ['un', 'mot', 'gras', 'et', 'italique', 'mais', 'pas', 'ni']);
      expect(words('voir [[https://exemple.org/xyz][la page]] et [[fichierX]]'), ['voir', 'la', 'page', 'et']);
      expect(words('lien https://exemple.org/abcdef ici'), ['lien', 'ici']);
    });

    test('names, numbers, files and acronyms are left alone', () {
      expect(words('le 5ème, notes.org, a@b.fr, HTML et API, x_y'), ['le', 'et']);
    });

    test('timestamps, footnotes and macros are skipped', () {
      expect(words('rendez-vous <2026-10-13 Tue 10:00> note[fn:1] {{{macro}}}'), ['rendez-vous', 'note']);
    });

    test('code blocks, drawers, properties and keywords', () {
      const doc = '#+TITLE: Mon carnet\n#+STARTUP: overview\n#+begin_src dart\nvar xyz;\n#+end_src\n'
          ':PROPERTIES:\n:ID: abc\n:END:\n#+begin_quote\nUne citation\n#+end_quote';
      expect(words(doc, 0), ['Mon', 'carnet']);
      expect(words(doc, 1), isEmpty);
      expect(words(doc, 3), isEmpty);
      expect(words(doc, 6), isEmpty);
      expect(words(doc, 9), ['Une', 'citation']);
    });
  });

  group('dictionaries', () {
    test('a #+LANGUAGE tag finds the closest dictionary', () async {
      final dir = await Directory.systemTemp.createTemp('haruspex_dicts');
      try {
        for (final code in ['en_US', 'en_GB', 'fr_FR', 'pt_BR', 'pt_PT']) {
          File('${dir.path}/$code.aff').writeAsStringSync('SET UTF-8\n');
          File('${dir.path}/$code.dic').writeAsStringSync('0\n');
        }
        final svc = SpellService.instance;
        await svc.init(bundledDir: dir.path, systemDirs: const [], personalPath: '${dir.path}/words.txt');
        expect(svc.match('fr'), 'fr_FR');
        expect(svc.match('fr-CA'), 'fr_FR');
        expect(svc.match('en'), 'en_US');
        expect(svc.match('en-GB'), 'en_GB');
        expect(svc.match('pt-BR'), 'pt_BR');
        expect(svc.match('pt'), 'pt_PT');
        expect(svc.match('ja'), isNull);
        expect(svc.resolve(null, 'fr_FR'), 'fr_FR');
        expect(svc.resolve('en', 'fr_FR'), 'en_US');
        expect(svc.resolve('ja', 'fr_FR'), isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('hunspell', () {
    final built = File(_built).existsSync();
    setUpAll(() => Hunspell.libraryPath = File(_built).absolute.path);

    test('checks and corrects French and English', () async {
      final dir = await Directory.systemTemp.createTemp('haruspex_words');
      try {
        final svc = SpellService.instance;
        await svc.init(bundledDir: 'assets/dictionaries', systemDirs: const [], personalPath: '${dir.path}/words.txt');
        expect(Hunspell.available, isTrue);
        final fr = svc.loadNow('fr_FR')!;
        for (final w in ['élève', "l'opposition", 'l’opposition', 'peut-être', 'lui-même', 'Bonjour']) {
          expect(fr.check(w), isTrue, reason: w);
        }
        expect(fr.check('éléve'), isFalse);
        expect(fr.suggest('derangeants'), contains('dérangeants'));
        final en = svc.loadNow('en_US')!;
        expect(en.check('receive'), isTrue);
        expect(en.check('recieve'), isFalse);
        expect(en.suggest('recieve').first, 'receive');

        // The personal word list is shared by every language and saved.
        expect(fr.check('Kenzi'), isFalse);
        await svc.addWord('Kenzi');
        expect(fr.check('Kenzi'), isTrue);
        expect(en.check('Kenzi'), isTrue);
        expect(File('${dir.path}/words.txt').readAsStringSync(), 'Kenzi\n');
        await svc.removeWord('Kenzi');
        expect(fr.check('Kenzi'), isFalse);

        for (final code in bundledDictionaries.keys) {
          expect(svc.loadNow(code), isNotNull, reason: code);
        }
      } finally {
        await dir.delete(recursive: true);
      }
    }, skip: built ? false : 'needs the library from flutter build linux');

    testWidgets('the editor finds misspelled words', (tester) async {
      final svc = SpellService.instance;
      await tester.runAsync(() => svc.init(bundledDir: 'assets/dictionaries', systemDirs: const []));
      svc.loadNow('fr_FR');
      final state = await startEditor(tester, '#+LANGUAGE: fr\nUn élève trés sérieux.');
      state.doc.focusNode.unfocus();
      await tester.pump();
      final o = state.doc.controller.text.indexOf('trés');
      final typo = state.misspelledAt(o + 1);
      expect(typo?.$2, 'trés');
      expect(state.misspelledAt(state.doc.controller.text.indexOf('élève')), isNull);
      expect(svc.checker('fr_FR')!.suggest('trés'), contains('très'));
    }, skip: !built);
  });
}
