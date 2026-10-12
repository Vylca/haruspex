/// Plain lists: item parsing, item extents, siblings and renumbering.
library;

import 'syntax.dart';

class ListItemInfo {
  ListItemInfo({
    required this.line,
    required this.indent,
    required this.indentStr,
    required this.bullet,
    required this.bulletStart,
    required this.bulletEnd,
    required this.checkbox,
    required this.cbStart,
    required this.cbEnd,
    required this.contentStart,
  });

  final int line;
  final int indent;
  final String indentStr;
  final String bullet;
  final int bulletStart;
  final int bulletEnd;

  /// ' ', 'X' or '-' when the item has a checkbox.
  final String? checkbox;
  final int cbStart;
  final int cbEnd;
  final int contentStart;

  bool get ordered => bullet.endsWith('.') || bullet.endsWith(')');
  bool get numeric => ordered && RegExp(r'^\d+').hasMatch(bullet);
  int get number => int.tryParse(RegExp(r'^\d+').stringMatch(bullet) ?? '') ?? 1;
  String get delimiter => ordered ? bullet.substring(bullet.length - 1) : '';

  /// Column where child items/continuation text should start.
  int get childIndent => indent + bullet.length + 1;

  static ListItemInfo? parse(String text, int line) {
    final m = listItemRe.firstMatch(text) ?? starItemRe.firstMatch(text);
    if (m == null) return null;
    final indentStr = m.group(1)!;
    final bullet = m.group(2)!;
    final bStart = indentStr.length;
    final bEnd = bStart + bullet.length;
    String? cb;
    var cbStart = -1, cbEnd = -1;
    final cbGroup = m.group(5);
    if (cbGroup != null) {
      cbStart = m.end - cbGroup.length;
      cbEnd = cbStart + 3;
      cb = text[cbStart + 1].toUpperCase() == 'X' ? 'X' : text[cbStart + 1];
    }
    return ListItemInfo(
      line: line,
      indent: indentWidth(text),
      indentStr: indentStr,
      bullet: bullet,
      bulletStart: bStart,
      bulletEnd: bEnd,
      checkbox: cb,
      cbStart: cbStart,
      cbEnd: cbEnd,
      contentStart: m.end,
    );
  }
}

ListItemInfo? itemAt(List<String> lines, int line) =>
    line >= 0 && line < lines.length ? ListItemInfo.parse(lines[line], line) : null;

/// The item whose body contains [line] (the item itself if [line] is an item).
ListItemInfo? owningItem(List<String> lines, int line) {
  final direct = itemAt(lines, line);
  if (direct != null) return direct;
  if (line < 0 || line >= lines.length) return null;
  var ind = blankRe.hasMatch(lines[line]) ? 1 << 30 : indentWidth(lines[line]);
  for (var j = line - 1; j >= 0; j--) {
    final l = lines[j];
    if (blankRe.hasMatch(l)) continue;
    if (HeadingInfo.isHeading(l)) return null;
    final it = ListItemInfo.parse(l, j);
    final w = indentWidth(l);
    if (it != null && w < ind) {
      final end = itemEnd(lines, j);
      return end > line ? it : null;
    }
    if (it == null && w < ind) ind = w;
    if (w == 0 && it == null) return null;
  }
  return null;
}

/// Exclusive end line of the item at [i] including its children, excluding
/// trailing blank lines.
int itemEnd(List<String> lines, int i) {
  final ind = indentWidth(lines[i]);
  var j = i + 1;
  var last = i;
  var blanks = 0;
  while (j < lines.length) {
    final l = lines[j];
    if (blankRe.hasMatch(l)) {
      blanks++;
      if (blanks >= 2) break;
      j++;
      continue;
    }
    if (HeadingInfo.isHeading(l)) break;
    if (indentWidth(l) <= ind) break;
    blanks = 0;
    last = j;
    j++;
  }
  return last + 1;
}

/// Line indices of all items in the same list and at the same level as [i].
List<int> siblingItems(List<String> lines, int i) {
  final it = itemAt(lines, i);
  if (it == null) return const [];
  final ind = it.indent;
  var first = i;
  var j = i - 1;
  while (j >= 0) {
    final l = lines[j];
    if (blankRe.hasMatch(l)) {
      j--;
      continue;
    }
    if (HeadingInfo.isHeading(l)) break;
    final w = indentWidth(l);
    if (w < ind) break;
    if (w == ind) {
      if (ListItemInfo.parse(l, j) != null) {
        first = j;
        j--;
        continue;
      }
      break;
    }
    j--;
  }
  final result = <int>[];
  var k = first;
  while (k < lines.length) {
    final item = itemAt(lines, k);
    if (item == null || item.indent != ind) break;
    result.add(k);
    k = itemEnd(lines, k);
    var blanks = 0;
    while (k < lines.length && blankRe.hasMatch(lines[k])) {
      k++;
      blanks++;
    }
    if (blanks >= 2) break;
  }
  return result;
}

/// Direct child items of the item at [i].
List<int> childItems(List<String> lines, int i) {
  final it = itemAt(lines, i);
  if (it == null) return const [];
  final end = itemEnd(lines, i);
  var minIndent = 1 << 30;
  final candidates = <int>[];
  for (var j = i + 1; j < end; j++) {
    final c = itemAt(lines, j);
    if (c != null && c.indent > it.indent) {
      candidates.add(j);
      if (c.indent < minIndent) minIndent = c.indent;
    }
  }
  return [
    for (final j in candidates)
      if (indentWidth(lines[j]) == minIndent) j
  ];
}

/// Renumbers the ordered list containing the item at [i]. Returns true when
/// anything changed. [onReplace] is called for each changed bullet so callers
/// can track the caret.
bool renumberList(List<String> lines, int i, void Function(int line, int start, int end, String text) onReplace) {
  final sibs = siblingItems(lines, i);
  if (sibs.isEmpty) return false;
  final first = itemAt(lines, sibs.first)!;
  if (!first.numeric) return false;
  var n = first.number;
  var changed = false;
  for (final s in sibs) {
    final it = itemAt(lines, s)!;
    if (!it.ordered) continue;
    final counter = RegExp(r'\[@(\d+)\]').firstMatch(lines[s].substring(it.bulletEnd));
    if (counter != null && s != sibs.first) n = int.parse(counter.group(1)!);
    final want = '$n${it.delimiter.isEmpty ? '.' : it.delimiter}';
    if (want != it.bullet) {
      onReplace(s, it.bulletStart, it.bulletEnd, want);
      changed = true;
    }
    n++;
  }
  return changed;
}

const bulletCycle = ['-', '+', '*', '1.', '1)'];
