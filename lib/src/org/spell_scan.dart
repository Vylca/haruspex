import 'package:flutter/services.dart' show TextRange;

import 'analysis.dart';
import 'edits.dart' show cookieRe, linkRe, plainUrlRe;
import 'lists.dart';
import 'syntax.dart';
import 'timestamp.dart';

/// A word: letters, with apostrophes and hyphens inside (l'opposition,
/// lui-même, don’t). Hunspell knows these forms.
final RegExp _wordRe = RegExp(r"[\p{L}\p{M}]+(?:['’\-][\p{L}\p{M}]+)*", unicode: true);

final RegExp _verbRe = RegExp(r'''(?<=^|[\s\-('"{])([=~])(?=\S)(.+?)(?<=\S)\1(?=$|[\s\-.,:!?;'")}\[])''');
final RegExp _footRe = RegExp(r'\[fn:[^\]\s]*\]');
final RegExp _targetRe = RegExp(r'<<<?[^<>\n]+>>>?');
final RegExp _macroRe = RegExp(r'\{\{\{[^}]+\}\}\}');
final RegExp _entityRe = RegExp(r'\\[A-Za-z]+(?:\{\})?');

/// Something in a chunk of text that marks it as a name rather than words:
/// digits, paths, e-mail addresses, file names (letter.letter).
final RegExp _technical = RegExp(r'[0-9_/\\@#$%&=<>|]|\p{L}\.\p{L}', unicode: true);

/// Keywords whose value is prose.
const _proseKeywords = {'TITLE', 'SUBTITLE', 'CAPTION', 'DESCRIPTION'};

/// Block types whose content is not prose.
const _codeBlocks = {'src', 'example', 'export', 'comment'};

/// The words of [line] to spell check, as ranges of the line. Leaves out Org
/// syntax (stars, TODO keywords, tags, bullets, checkboxes), code, links,
/// timestamps, URLs, numbers, words in all capitals (acronyms) and anything
/// that looks like a file name or an address.
List<TextRange> spellWords(LineInfo info, String line) {
  var start = 0;
  var end = line.length;
  switch (info.kind) {
    case LineKind.text:
    case LineKind.table:
      break;
    case LineKind.heading:
      final h = info.heading;
      if (h == null) return const [];
      start = h.titleStart;
      end = h.titleEnd;
    case LineKind.listItem:
      final item = ListItemInfo.parse(line, 0);
      if (item != null) start = item.contentStart;
    case LineKind.footnote:
      final m = footnoteDefRe.firstMatch(line);
      if (m != null) start = m.end;
    case LineKind.keyword:
      final m = keywordRe.firstMatch(line);
      final value = m?.group(2);
      if (m == null || value == null || !_proseKeywords.contains(m.group(1)!.toUpperCase())) return const [];
      start = line.length - value.length;
    case LineKind.blockContent:
      if (_codeBlocks.contains(info.blockType)) return const [];
    default:
      return const [];
  }
  if (end <= start) return const [];

  // Parts of the line that are not prose.
  final skip = <TextRange>[];
  void skipAll(RegExp re) {
    for (final m in re.allMatches(line)) {
      if (m.end > m.start) skip.add(TextRange(start: m.start, end: m.end));
    }
  }

  if (line.contains('[[')) {
    for (final m in linkRe.allMatches(line)) {
      final target = m.group(1)!;
      final desc = m.group(2);
      if (desc == null) {
        skip.add(TextRange(start: m.start, end: m.end));
      } else {
        // Check the description, not the target.
        skip.add(TextRange(start: m.start, end: m.start + 2 + target.length + 2));
      }
    }
  }
  for (final (m, _) in OrgTimestamp.findAll(line)) {
    skip.add(TextRange(start: m.start, end: m.end));
  }
  if (line.contains('[fn:')) skipAll(_footRe);
  if (line.contains('[')) skipAll(cookieRe);
  if (line.contains('<<')) skipAll(_targetRe);
  if (line.contains('{{{')) skipAll(_macroRe);
  if (line.contains('=') || line.contains('~')) skipAll(_verbRe);
  if (line.contains(':')) skipAll(plainUrlRe);
  if (line.contains('\\')) skipAll(_entityRe);

  // The line with everything that is not prose blanked out, so a word next
  // to a link or a footnote is judged on its own.
  var text = line;
  if (skip.isNotEmpty) {
    final units = line.codeUnits.toList();
    for (final r in skip) {
      units.fillRange(r.start, r.end, 0x20);
    }
    text = String.fromCharCodes(units);
  }

  final out = <TextRange>[];
  for (final m in _wordRe.allMatches(text, start)) {
    if (m.start >= end) break;
    final s = m.start, e = m.end > end ? end : m.end;
    final word = text.substring(s, e);
    // Acronyms and shouting.
    if (word.length > 1 && word == word.toUpperCase() && word != word.toLowerCase()) continue;
    // The run of non-space characters around the word.
    var cs = s, ce = e;
    while (cs > 0 && !_isSpace(text.codeUnitAt(cs - 1))) {
      cs--;
    }
    while (ce < text.length && !_isSpace(text.codeUnitAt(ce))) {
      ce++;
    }
    // Markup and punctuation at its ends do not count: /italique/, (voir).
    while (cs < s && _edge.contains(text[cs])) {
      cs++;
    }
    while (ce > e && _edge.contains(text[ce - 1])) {
      ce--;
    }
    if (_technical.hasMatch(text.substring(cs, ce))) continue;
    out.add(TextRange(start: s, end: e));
  }
  return out;
}

const _edge = '*/_+~=([{<"\'«»“”‘’.,;:!?)]}>…';

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0xA0;
