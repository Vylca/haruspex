/// Structure editing commands. Each command takes the current text and
/// selection and returns an [EditResult] (or null when it does not apply).
library;

import 'analysis.dart';
import 'lists.dart';
import 'syntax.dart';
import 'table.dart';
import 'timestamp.dart';

class Sel {
  const Sel(this.base, this.extent);
  const Sel.collapsed(int offset)
      : base = offset,
        extent = offset;
  final int base;
  final int extent;
  int get start => base < extent ? base : extent;
  int get end => base < extent ? extent : base;
  bool get isCollapsed => base == extent;
}

class EditResult {
  EditResult(this.text, this.selection, {this.lineMap, this.message});
  final String text;
  final Sel selection;

  /// Old line index -> new line index for lines that were moved as a block,
  /// used to carry fold state along.
  final Map<int, int>? lineMap;
  final String? message;
}

/// Mutable line buffer that keeps track of the caret while it is edited.
class Doc {
  Doc(List<String> lines, this.caretLine, this.caretCol) : lines = [...lines];

  factory Doc.of(OrgAnalysis a, int caretOffset) {
    final line = a.lineOfOffset(caretOffset);
    return Doc(a.lines, line, caretOffset - a.lineStarts[line]);
  }

  final List<String> lines;
  int caretLine;
  int caretCol;
  String? message;
  Map<int, int>? lineMap;

  String get text => lines.join('\n');

  void insertLines(int at, List<String> ls) {
    lines.insertAll(at, ls);
    if (caretLine >= at) caretLine += ls.length;
  }

  void removeLines(int start, int end) {
    if (end <= start) return;
    lines.removeRange(start, end);
    if (caretLine >= end) {
      caretLine -= end - start;
    } else if (caretLine >= start) {
      caretLine = start < lines.length ? start : lines.length - 1;
      caretCol = 0;
    }
    if (lines.isEmpty) {
      lines.add('');
      caretLine = 0;
      caretCol = 0;
    }
  }

  void replaceInLine(int i, int start, int end, String rep) {
    final l = lines[i];
    lines[i] = l.substring(0, start) + rep + l.substring(end);
    if (caretLine == i) {
      if (caretCol >= end) {
        caretCol += rep.length - (end - start);
      } else if (caretCol > start) {
        caretCol = start + rep.length;
      }
    }
  }

  void setLine(int i, String s) {
    lines[i] = s;
    if (caretLine == i && caretCol > s.length) caretCol = s.length;
  }

  void moveCaret(int line, int col) {
    caretLine = line;
    caretCol = col;
  }

  OrgAnalysis analyze() => OrgAnalysis(text);

  EditResult result() {
    var o = 0;
    final line = caretLine.clamp(0, lines.length - 1);
    for (var i = 0; i < line; i++) {
      o += lines[i].length + 1;
    }
    final col = caretCol.clamp(0, lines[line].length);
    return EditResult(text, Sel.collapsed(o + col), lineMap: lineMap, message: message);
  }
}

String headingStars(int level) => '*' * level;

// ---------------------------------------------------------------------------
// Headings
// ---------------------------------------------------------------------------

/// Cycles (or sets) the TODO keyword of the entry containing the caret.
EditResult? cycleTodo(OrgAnalysis a, int caret, {bool backward = false, String? setTo, bool useSetTo = false, DateTime? now}) {
  final caretLine = a.lineOfOffset(caret);
  final h = a.headingAtOrAbove(caretLine);
  if (h == null) return null;
  final info = a.headingInfo(h)!;
  final old = info.keyword;
  final newKw = useSetTo ? setTo : (backward ? a.todo.previous(old) : a.todo.next(old));
  final d = Doc.of(a, caret);
  _setKeyword(d, h, info, newKw);
  final clock = now ?? DateTime.now();
  final becameDone = a.todo.isDone(newKw) && !a.todo.isDone(old);
  final leftDone = !a.todo.isDone(newKw) && a.todo.isDone(old);
  if (becameDone) {
    final repeated = _applyRepeaters(d, h, clock);
    if (repeated) {
      final back = a.todo.isTodo(old) ? old : a.todo.firstTodo;
      final a2 = d.analyze();
      _setKeyword(d, h, a2.headingInfo(h)!, back);
      _setProperty(d, h, 'LAST_REPEAT', OrgTimestamp.now(active: false, withTime: true).format());
    } else if (a.logDone) {
      _setPlanningKey(d, h, 'CLOSED', OrgTimestamp.now(active: false, withTime: true));
    }
  } else if (leftDone) {
    _setPlanningKey(d, h, 'CLOSED', null);
  }
  _updateStatistics(d);
  return d.result();
}

void _setKeyword(Doc d, int h, HeadingInfo info, String? kw) {
  if (info.kwStart >= 0) {
    if (kw == null) {
      var end = info.kwEnd;
      final line = d.lines[h];
      while (end < line.length && line[end] == ' ') {
        end++;
      }
      d.replaceInLine(h, info.kwStart, end, '');
    } else {
      d.replaceInLine(h, info.kwStart, info.kwEnd, kw);
    }
  } else if (kw != null) {
    final line = d.lines[h];
    if (line.length <= info.level + 1) {
      d.replaceInLine(h, info.level, line.length, ' $kw');
    } else {
      d.replaceInLine(h, info.level + 1, info.level + 1, '$kw ');
    }
  }
}

final RegExp _planningItemRe = RegExp(r'(SCHEDULED|DEADLINE|CLOSED):[ \t]*([<\[][^>\]]*[>\]])');

/// Shifts all repeating timestamps in the entry. Returns true if any.
bool _applyRepeaters(Doc d, int h, DateTime now) {
  final a = d.analyze();
  final end = a.bodyEnd(h);
  var any = false;
  for (var l = h + 1; l < end; l++) {
    final kind = a.infos[l].kind;
    if (kind == LineKind.blockContent || kind == LineKind.property) continue;
    final found = OrgTimestamp.findAll(d.lines[l]);
    for (final (m, ts) in found.reversed) {
      if (!ts.active || ts.repeater == null) continue;
      final next = ts.repeated(now);
      if (next == null) continue;
      d.replaceInLine(l, m.start, m.end, next.format());
      any = true;
    }
  }
  if (any) {
    d.message = 'Entry repeats';
  }
  return any;
}

/// Sets (or removes when [ts] is null) SCHEDULED/DEADLINE/CLOSED of entry [h].
void _setPlanningKey(Doc d, int h, String key, OrgTimestamp? ts) {
  final a = d.analyze();
  final pl = a.planningLine(h);
  if (pl == null) {
    if (ts == null) return;
    d.insertLines(h + 1, ['$key: ${ts.format()}']);
    return;
  }
  final line = d.lines[pl];
  final indent = leadingWhitespace(line);
  final entries = <String, String>{};
  final order = <String>[];
  for (final m in _planningItemRe.allMatches(line)) {
    entries[m.group(1)!] = m.group(2)!;
    order.add(m.group(1)!);
  }
  if (ts == null) {
    entries.remove(key);
    order.remove(key);
  } else {
    if (!entries.containsKey(key)) order.add(key);
    entries[key] = ts.format();
  }
  if (order.isEmpty) {
    d.removeLines(pl, pl + 1);
  } else {
    d.setLine(pl, indent + order.map((k) => '$k: ${entries[k]}').join(' '));
  }
}

/// Sets a property in the entry's property drawer, creating it if needed.
void _setProperty(Doc d, int h, String key, String? value) {
  final a = d.analyze();
  final drawer = a.propertyDrawer(h);
  final upper = key.toUpperCase();
  if (drawer == null) {
    if (value == null) return;
    final at = a.planningLine(h) != null ? h + 2 : h + 1;
    d.insertLines(at, [':PROPERTIES:', ':$key: $value', ':END:']);
    return;
  }
  for (var l = drawer.$1 + 1; l < drawer.$2; l++) {
    final m = propertyRe.firstMatch(d.lines[l]);
    if (m != null && m.group(1)!.toUpperCase() == upper) {
      if (value == null) {
        d.removeLines(l, l + 1);
      } else {
        d.setLine(l, '${leadingWhitespace(d.lines[l])}:${m.group(1)}: $value');
      }
      return;
    }
  }
  if (value != null) {
    d.insertLines(drawer.$2, ['${leadingWhitespace(d.lines[drawer.$1])}:$key: $value']);
  }
}

EditResult? setProperty(OrgAnalysis a, int caret, String key, String? value) {
  final h = a.headingAtOrAbove(a.lineOfOffset(caret));
  if (h == null) return null;
  final d = Doc.of(a, caret);
  _setProperty(d, h, key, value);
  return d.result();
}

EditResult? setPlanning(OrgAnalysis a, int caret, String key, OrgTimestamp? ts) {
  final h = a.headingAtOrAbove(a.lineOfOffset(caret));
  if (h == null) return null;
  final d = Doc.of(a, caret);
  _setPlanningKey(d, h, key, ts);
  return d.result();
}

/// Priority shift on the entry heading. Cycle: none -> default -> ... -> none.
EditResult? shiftPriority(OrgAnalysis a, int caret, bool up) {
  final h = a.headingAtOrAbove(a.lineOfOffset(caret));
  if (h == null) return null;
  final info = a.headingInfo(h)!;
  final all = a.priorities.all; // highest first
  String? next;
  if (info.priority == null) {
    next = a.priorities.defaultPriority;
  } else {
    final i = all.indexOf(info.priority!);
    if (i < 0) {
      next = a.priorities.defaultPriority;
    } else {
      final j = up ? i - 1 : i + 1;
      next = (j < 0 || j >= all.length) ? null : all[j];
    }
  }
  return _withPriority(a, caret, h, info, next);
}

EditResult? setPriority(OrgAnalysis a, int caret, String? p) {
  final h = a.headingAtOrAbove(a.lineOfOffset(caret));
  if (h == null) return null;
  return _withPriority(a, caret, h, a.headingInfo(h)!, p);
}

EditResult _withPriority(OrgAnalysis a, int caret, int h, HeadingInfo info, String? p) {
  final d = Doc.of(a, caret);
  final line = d.lines[h];
  if (info.prioStart >= 0) {
    if (p == null) {
      var end = info.prioEnd;
      while (end < line.length && line[end] == ' ') {
        end++;
      }
      d.replaceInLine(h, info.prioStart, end, '');
    } else {
      d.replaceInLine(h, info.prioStart, info.prioEnd, '[#$p]');
    }
  } else if (p != null) {
    final at = info.kwEnd >= 0 ? info.kwEnd : info.level;
    if (at >= line.length) {
      d.replaceInLine(h, at, at, ' [#$p]');
    } else {
      d.replaceInLine(h, at, at + 1, ' [#$p] ');
    }
  }
  return d.result();
}

/// Promote (delta < 0) or demote (delta > 0) a heading, optionally with its
/// subtree.
EditResult? changeHeadingLevel(OrgAnalysis a, int caret, int delta, {required bool subtree}) {
  final line = a.lineOfOffset(caret);
  final h = a.headingAtOrAbove(line);
  if (h == null) return null;
  final targets = subtree ? a.headingsIn(h, a.subtreeEnd(h)) : [h];
  for (final t in targets) {
    if (a.levelOf(t) + delta < 1) {
      final d = Doc.of(a, caret)..message = 'Cannot promote to level 0';
      return d.result();
    }
  }
  final d = Doc.of(a, caret);
  for (final t in targets) {
    final lv = a.levelOf(t);
    d.replaceInLine(t, 0, lv, headingStars(lv + delta));
  }
  return d.result();
}

/// Moves the subtree at the caret past its previous/next sibling.
EditResult? moveSubtree(OrgAnalysis a, int caret, {required bool up}) {
  final line = a.lineOfOffset(caret);
  final h = a.headingAtOrAbove(line);
  if (h == null) return null;
  int aStart, aEnd, bStart, bEnd;
  if (up) {
    final prev = a.previousSibling(h);
    if (prev == null) {
      return (Doc.of(a, caret)..message = 'Cannot move past superior level or buffer limit').result();
    }
    aStart = prev;
    aEnd = h;
    bStart = h;
    bEnd = a.subtreeEnd(h);
  } else {
    final next = a.nextSibling(h);
    if (next == null) {
      return (Doc.of(a, caret)..message = 'Cannot move past superior level or buffer limit').result();
    }
    aStart = h;
    aEnd = next;
    bStart = next;
    bEnd = a.subtreeEnd(next);
  }
  return _swapBlocks(a, caret, aStart, aEnd, bStart, bEnd);
}

/// Swaps two adjacent line blocks [aStart, aEnd) and [bStart, bEnd) where
/// aEnd == bStart.
EditResult _swapBlocks(OrgAnalysis a, int caret, int aStart, int aEnd, int bStart, int bEnd) {
  final lines = [...a.lines];
  final blockA = lines.sublist(aStart, aEnd);
  final blockB = lines.sublist(bStart, bEnd);
  final newLines = [...lines.sublist(0, aStart), ...blockB, ...blockA, ...lines.sublist(bEnd)];
  final map = <int, int>{};
  for (var i = bStart; i < bEnd; i++) {
    map[i] = i - (aEnd - aStart);
  }
  for (var i = aStart; i < aEnd; i++) {
    map[i] = i + (bEnd - bStart);
  }
  final caretLine = a.lineOfOffset(caret);
  final col = caret - a.lineStarts[caretLine];
  final d = Doc(newLines, map[caretLine] ?? caretLine, col);
  d.lineMap = map;
  return d.result();
}

/// M-RET and friends: insert a heading.
EditResult insertHeading(OrgAnalysis a, int caret, {bool todo = false, bool respectContent = false, bool folded = false}) {
  final line = a.lineOfOffset(caret);
  final col = caret - a.lineStarts[line];
  final h = a.headingAtOrAbove(line);
  final level = h == null ? 1 : a.levelOf(h);
  final kw = todo ? '${a.todo.firstTodo} ' : '';
  final stars = headingStars(level);
  final d = Doc.of(a, caret);
  final text = a.lines[line];

  if (h != null && (respectContent || (h == line && folded))) {
    final end = a.subtreeEnd(h);
    final newLine = '$stars $kw';
    d.insertLines(end, [newLine]);
    d.moveCaret(end, newLine.length);
    return d.result();
  }
  if (h != null && h == line) {
    final info = a.headingInfo(h)!;
    if (col == 0) {
      final newLine = '$stars $kw';
      d.insertLines(h, [newLine]);
      d.moveCaret(h, newLine.length);
      return d.result();
    }
    final restText = col < text.length ? text.substring(col).trim() : '';
    final inTitle = col > info.prefixEnd && col < info.titleEnd;
    if (inTitle && restText.isNotEmpty) {
      final rest = text.substring(col, info.titleEnd).trim();
      d.replaceInLine(h, col, info.titleEnd, '');
      final newLine = '$stars $kw$rest';
      d.insertLines(h + 1, [newLine]);
      d.moveCaret(h + 1, '$stars $kw'.length);
      return d.result();
    }
    final end = a.bodyEnd(h);
    final newLine = '$stars $kw';
    d.insertLines(end, [newLine]);
    d.moveCaret(end, newLine.length);
    return d.result();
  }
  // On a non-heading line.
  if (col == 0 && text.trim().isNotEmpty) {
    d.replaceInLine(line, 0, 0, '$stars $kw');
    d.moveCaret(line, d.lines[line].length);
    return d.result();
  }
  final rest = col < text.length ? text.substring(col).trimLeft() : '';
  if (rest.isNotEmpty) d.replaceInLine(line, col, text.length, '');
  final newLine = '$stars $kw$rest';
  d.insertLines(line + 1, [newLine]);
  d.moveCaret(line + 1, '$stars $kw'.length);
  return d.result();
}

/// C-c *: turn a line into a heading or a heading into a line.
EditResult? toggleHeading(OrgAnalysis a, int caret) {
  final line = a.lineOfOffset(caret);
  final d = Doc.of(a, caret);
  final info = a.headingInfo(line);
  if (info != null) {
    var end = info.level;
    final t = a.lines[line];
    while (end < t.length && t[end] == ' ') {
      end++;
    }
    d.replaceInLine(line, 0, end, '');
    return d.result();
  }
  final parent = a.headingAtOrAbove(line);
  final level = parent == null ? 1 : a.levelOf(parent) + 1;
  final t = a.lines[line];
  final item = ListItemInfo.parse(t, line);
  if (item != null) {
    d.replaceInLine(line, 0, item.contentStart, '${headingStars(level)} ');
  } else {
    final ws = leadingWhitespace(t).length;
    d.replaceInLine(line, 0, ws, '${headingStars(level)} ');
  }
  return d.result();
}

/// Sets the tags of the entry, aligning them at column 77 like Org.
EditResult? setTags(OrgAnalysis a, int caret, List<String> tags) {
  final h = a.headingAtOrAbove(a.lineOfOffset(caret));
  if (h == null) return null;
  final info = a.headingInfo(h)!;
  final d = Doc.of(a, caret);
  final line = a.lines[h];
  final head = line.substring(0, info.titleEnd > info.titleStart ? info.titleEnd : info.titleStart).trimRight();
  final clean = tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  String newLine;
  if (clean.isEmpty) {
    newLine = head;
  } else {
    final tagStr = ':${clean.join(':')}:';
    var pad = 77 - head.length - tagStr.length;
    if (pad < 1) pad = 1;
    newLine = '$head${' ' * pad}$tagStr';
  }
  final caretCol = d.caretLine == h ? d.caretCol : -1;
  d.setLine(h, newLine);
  if (caretCol > head.length) d.caretCol = head.length;
  return d.result();
}

// ---------------------------------------------------------------------------
// Lists
// ---------------------------------------------------------------------------

void _renumber(Doc d, int line) {
  renumberList(d.lines, line, (l, s, e, t) => d.replaceInLine(l, s, e, t));
}

EditResult? insertItem(OrgAnalysis a, int caret, {bool checkbox = false}) {
  final line = a.lineOfOffset(caret);
  final col = caret - a.lineStarts[line];
  final item = owningItem(a.lines, line);
  if (item == null) return null;
  final d = Doc.of(a, caret);
  final bullet = item.ordered ? '${item.number + 1}${item.delimiter}' : item.bullet;
  final cb = (checkbox || item.checkbox != null) ? '[ ] ' : '';
  final prefix = '${item.indentStr}$bullet $cb';
  final text = a.lines[line];
  if (line == item.line && col <= item.bulletStart) {
    final p = '${item.indentStr}${item.bullet} $cb';
    d.insertLines(line, [p]);
    d.moveCaret(line, p.length);
    _renumber(d, line);
    return d.result();
  }
  if (line == item.line && col > item.contentStart && col < text.length && text.substring(col).trim().isNotEmpty) {
    final rest = text.substring(col).trim();
    d.replaceInLine(line, col, text.length, '');
    d.setLine(line, d.lines[line].trimRight());
    d.insertLines(line + 1, ['$prefix$rest']);
    d.moveCaret(line + 1, prefix.length);
    _renumber(d, line + 1);
    return d.result();
  }
  final end = itemEnd(a.lines, item.line);
  d.insertLines(end, [prefix]);
  d.moveCaret(end, prefix.length);
  _renumber(d, end);
  return d.result();
}

/// Indent (delta > 0) or outdent (delta < 0) the item at the caret.
EditResult? shiftItem(OrgAnalysis a, int caret, int delta, {required bool subtree}) {
  final line = a.lineOfOffset(caret);
  final item = owningItem(a.lines, line);
  if (item == null) return null;
  final lines = a.lines;
  final d = Doc.of(a, caret);
  int newIndent;
  if (delta > 0) {
    final sibs = siblingItems(lines, item.line);
    final idx = sibs.indexOf(item.line);
    if (idx <= 0) {
      d.message = 'Cannot indent the first item of a list';
      return d.result();
    }
    final prev = itemAt(lines, sibs[idx - 1])!;
    newIndent = prev.childIndent;
  } else {
    ListItemInfo? parent;
    for (var j = item.line - 1; j >= 0; j--) {
      final l = lines[j];
      if (blankRe.hasMatch(l)) continue;
      if (HeadingInfo.isHeading(l)) break;
      final w = indentWidth(l);
      if (w < item.indent) {
        parent = ListItemInfo.parse(l, j);
        break;
      }
    }
    if (parent == null) {
      d.message = 'Cannot outdent beyond margin';
      return d.result();
    }
    newIndent = parent.indent;
  }
  final shift = newIndent - item.indent;
  final hasChildren = childItems(lines, item.line).isNotEmpty;
  final end = (subtree || hasChildren) ? itemEnd(lines, item.line) : _itemOwnTextEnd(lines, item.line);
  for (var l = item.line; l < end; l++) {
    final t = d.lines[l];
    if (blankRe.hasMatch(t)) continue;
    final ws = leadingWhitespace(t);
    final w = indentWidth(t);
    final nw = (w + shift) < 0 ? 0 : w + shift;
    d.replaceInLine(l, 0, ws.length, ' ' * nw);
  }
  _renumberRegion(d, item.line - 200, end + 200);
  return d.result();
}

void _renumberRegion(Doc d, int from, int to) {
  final seen = <int>{};
  for (var l = from < 0 ? 0 : from; l < to && l < d.lines.length; l++) {
    if (itemAt(d.lines, l) == null) continue;
    final sibs = siblingItems(d.lines, l);
    if (sibs.isEmpty || seen.contains(sibs.first)) continue;
    seen.add(sibs.first);
    _renumber(d, sibs.first);
  }
}

int _itemOwnTextEnd(List<String> lines, int i) {
  final end = itemEnd(lines, i);
  for (var j = i + 1; j < end; j++) {
    if (itemAt(lines, j) != null) return j;
  }
  return end;
}

EditResult? moveItem(OrgAnalysis a, int caret, {required bool up}) {
  final line = a.lineOfOffset(caret);
  final item = owningItem(a.lines, line);
  if (item == null) return null;
  final sibs = siblingItems(a.lines, item.line);
  final idx = sibs.indexOf(item.line);
  if (idx < 0) return null;
  final otherIdx = up ? idx - 1 : idx + 1;
  if (otherIdx < 0 || otherIdx >= sibs.length) {
    return (Doc.of(a, caret)..message = 'Cannot move item further').result();
  }
  final first = up ? sibs[otherIdx] : item.line;
  final second = up ? item.line : sibs[otherIdx];
  final firstEnd = second; // blocks are adjacent (including blank separators)
  final secondEnd = itemEnd(a.lines, second);
  final r = _swapBlocks(a, caret, first, firstEnd, second, secondEnd);
  // Renumber after the swap.
  final a2 = OrgAnalysis(r.text);
  final d = Doc.of(a2, r.selection.extent);
  d.lineMap = r.lineMap;
  _renumber(d, first);
  return d.result();
}

EditResult? cycleBullet(OrgAnalysis a, int caret, {bool backward = false}) {
  final line = a.lineOfOffset(caret);
  final item = owningItem(a.lines, line);
  if (item == null) return null;
  final current = item.ordered ? '1${item.delimiter}' : item.bullet;
  var i = bulletCycle.indexOf(current);
  if (i < 0) i = 0;
  String next;
  var guard = 0;
  do {
    i = (i + (backward ? -1 : 1) + bulletCycle.length) % bulletCycle.length;
    next = bulletCycle[i];
    guard++;
  } while (next == '*' && item.indent == 0 && guard < 10);
  final d = Doc.of(a, caret);
  final sibs = siblingItems(a.lines, item.line);
  var n = 1;
  for (final s in sibs) {
    final it = itemAt(d.lines, s)!;
    final b = next.endsWith('.') || next.endsWith(')') ? '$n${next.substring(1)}' : next;
    d.replaceInLine(s, it.bulletStart, it.bulletEnd, b);
    n++;
  }
  return d.result();
}

/// Toggles the checkbox of the item at the caret.
EditResult? toggleCheckbox(OrgAnalysis a, int caret) {
  final line = a.lineOfOffset(caret);
  final item = owningItem(a.lines, line);
  if (item == null || item.checkbox == null) return null;
  final d = Doc.of(a, caret);
  final next = item.checkbox == 'X' ? ' ' : 'X';
  d.replaceInLine(item.line, item.cbStart + 1, item.cbStart + 2, next);
  _updateStatistics(d);
  return d.result();
}

/// Adds or removes the checkbox of the item at the caret.
EditResult? toggleCheckboxPresence(OrgAnalysis a, int caret) {
  final line = a.lineOfOffset(caret);
  final item = owningItem(a.lines, line);
  if (item == null) return null;
  final d = Doc.of(a, caret);
  if (item.checkbox != null) {
    final t = a.lines[item.line];
    var end = item.cbEnd;
    while (end < t.length && t[end] == ' ') {
      end++;
    }
    d.replaceInLine(item.line, item.cbStart, end, '');
  } else {
    final t = a.lines[item.line];
    final at = item.contentStart;
    if (at >= t.length) {
      final pad = t.endsWith(' ') ? '' : ' ';
      d.replaceInLine(item.line, t.length, t.length, '$pad[ ] ');
    } else {
      d.replaceInLine(item.line, at, at, '[ ] ');
    }
  }
  _updateStatistics(d);
  return d.result();
}

// ---------------------------------------------------------------------------
// Statistics cookies and hierarchical checkboxes
// ---------------------------------------------------------------------------

final RegExp cookieRe = RegExp(r'\[(\d*%|\d*/\d*)\]');

EditResult updateStatistics(OrgAnalysis a, int caret) {
  final d = Doc.of(a, caret);
  _updateStatistics(d);
  return d.result();
}

void _updateStatistics(Doc d) {
  // Parent checkboxes, bottom-up.
  for (var i = d.lines.length - 1; i >= 0; i--) {
    final it = itemAt(d.lines, i);
    if (it == null || it.checkbox == null) continue;
    final kids = childItems(d.lines, i).map((k) => itemAt(d.lines, k)!).where((k) => k.checkbox != null).toList();
    if (kids.isEmpty) continue;
    final done = kids.where((k) => k.checkbox == 'X').length;
    final state = done == kids.length ? 'X' : (done == 0 && kids.every((k) => k.checkbox == ' ') ? ' ' : '-');
    if (state != it.checkbox) d.replaceInLine(i, it.cbStart + 1, it.cbStart + 2, state);
  }
  // Cookies.
  final a = d.analyze();
  for (var i = 0; i < d.lines.length; i++) {
    final t = d.lines[i];
    if (!t.contains('[') || !cookieRe.hasMatch(t)) continue;
    int done = 0, total = 0;
    if (a.isHeading(i)) {
      final kids = a.childHeadings(i).where((k) => a.headingInfo(k)!.keyword != null).toList();
      if (kids.isNotEmpty) {
        total = kids.length;
        done = kids.where((k) => a.todo.isDone(a.headingInfo(k)!.keyword)).length;
      } else {
        final end = a.bodyEnd(i);
        var minIndent = 1 << 30;
        final boxes = <ListItemInfo>[];
        for (var l = i + 1; l < end; l++) {
          final it = itemAt(d.lines, l);
          if (it != null && it.checkbox != null) {
            boxes.add(it);
            if (it.indent < minIndent) minIndent = it.indent;
          }
        }
        for (final b in boxes) {
          if (b.indent != minIndent) continue;
          total++;
          if (b.checkbox == 'X') done++;
        }
      }
    } else {
      final it = itemAt(d.lines, i);
      if (it == null) continue;
      for (final k in childItems(d.lines, i)) {
        final c = itemAt(d.lines, k)!;
        if (c.checkbox == null) continue;
        total++;
        if (c.checkbox == 'X') done++;
      }
    }
    // Replace every cookie on the line (right to left).
    final matches = cookieRe.allMatches(t).toList().reversed;
    for (final m in matches) {
      final inner = m.group(1)!;
      final rep = inner.endsWith('%') ? '[${total == 0 ? 0 : (done * 100) ~/ total}%]' : '[$done/$total]';
      if (rep != m.group(0)) d.replaceInLine(i, m.start, m.end, rep);
    }
  }
}

// ---------------------------------------------------------------------------
// Timestamps
// ---------------------------------------------------------------------------

/// The timestamp under [col] in [line] (inclusive of the closing bracket).
(RegExpMatch, OrgTimestamp)? timestampAt(String line, int col) {
  for (final (m, ts) in OrgTimestamp.findAll(line)) {
    if (col >= m.start && col <= m.end) return (m, ts);
  }
  return null;
}

EditResult? shiftTimestampAt(OrgAnalysis a, int caret, {int days = 0, int fieldDelta = 0}) {
  final line = a.lineOfOffset(caret);
  final col = caret - a.lineStarts[line];
  final found = timestampAt(a.lines[line], col);
  if (found == null) return null;
  final (m, ts) = found;
  OrgTimestamp next;
  if (days != 0) {
    next = ts.addDays(days);
  } else {
    final field = ts.fieldAt(m.group(0)!, col - m.start);
    next = ts.shiftField(field, fieldDelta);
  }
  final d = Doc.of(a, caret);
  final rep = next.format();
  d.replaceInLine(line, m.start, m.end, rep);
  d.caretCol = col <= m.start + rep.length ? col : m.start + rep.length;
  return d.result();
}

/// Inserts a timestamp at the caret, or replaces the one under the caret.
EditResult insertTimestamp(OrgAnalysis a, int caret, OrgTimestamp ts) {
  final line = a.lineOfOffset(caret);
  final col = caret - a.lineStarts[line];
  final d = Doc.of(a, caret);
  final found = timestampAt(a.lines[line], col);
  final rep = ts.format();
  if (found != null) {
    final (m, _) = found;
    d.replaceInLine(line, m.start, m.end, rep);
    d.caretCol = m.start + rep.length;
  } else {
    d.replaceInLine(line, col, col, rep);
    d.caretCol = col + rep.length;
  }
  return d.result();
}

// ---------------------------------------------------------------------------
// Links
// ---------------------------------------------------------------------------

final RegExp linkRe = RegExp(r'\[\[([^\[\]]+)\](?:\[([^\[\]]+)\])?\]');
final RegExp plainUrlRe = RegExp(r'''(?:https?|ftp|mailto|file):[^\s<>\[\]"']*[^\s<>\[\]"'.,;:!?)]''');

class LinkAt {
  LinkAt(this.target, this.description, this.start, this.end);
  final String target;
  final String? description;
  final int start;
  final int end;
}

LinkAt? linkAt(String line, int col) {
  for (final m in linkRe.allMatches(line)) {
    if (col >= m.start && col <= m.end) return LinkAt(m.group(1)!, m.group(2), m.start, m.end);
  }
  for (final m in plainUrlRe.allMatches(line)) {
    if (col >= m.start && col <= m.end) return LinkAt(m.group(0)!, null, m.start, m.end);
  }
  return null;
}

EditResult insertLink(OrgAnalysis a, int caret, String target, String? description, {int? selStart, int? selEnd}) {
  final line = a.lineOfOffset(caret);
  final col = caret - a.lineStarts[line];
  final d = Doc.of(a, caret);
  final desc = (description == null || description.trim().isEmpty) ? null : description.trim();
  final rep = desc == null ? '[[$target]]' : '[[$target][$desc]]';
  final existing = linkAt(a.lines[line], col);
  if (existing != null) {
    d.replaceInLine(line, existing.start, existing.end, rep);
    d.caretCol = existing.start + rep.length;
  } else if (selStart != null && selEnd != null && selStart != selEnd) {
    final sLine = a.lineOfOffset(selStart);
    final eLine = a.lineOfOffset(selEnd);
    if (sLine == eLine) {
      final s = selStart - a.lineStarts[sLine], e = selEnd - a.lineStarts[sLine];
      d.replaceInLine(sLine, s, e, rep);
      d.moveCaret(sLine, s + rep.length);
    } else {
      d.replaceInLine(line, col, col, rep);
      d.caretCol = col + rep.length;
    }
  } else {
    d.replaceInLine(line, col, col, rep);
    d.caretCol = col + rep.length;
  }
  return d.result();
}

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

EditResult? tableEdit(OrgAnalysis a, int caret, TableOp op) {
  final line = a.lineOfOffset(caret);
  final col = caret - a.lineStarts[line];
  final r = tableOperation(a.lines, line, col, op);
  if (r == null) return null;
  final d = Doc(r.lines, r.caretLine, r.caretCol);
  return d.result();
}

EditResult createTable(OrgAnalysis a, int caret) {
  final line = a.lineOfOffset(caret);
  final d = Doc.of(a, caret);
  final indent = leadingWhitespace(a.lines[line]);
  final t = newTable(indent, 3, 2);
  final empty = a.lines[line].trim().isEmpty;
  if (empty) {
    d.removeLines(line, line + 1);
    d.insertLines(line, t);
    d.moveCaret(line, indent.length + 2);
  } else {
    d.insertLines(line + 1, t);
    d.moveCaret(line + 1, indent.length + 2);
  }
  return d.result();
}
