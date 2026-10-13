/// Line-level analysis of an Org document: line kinds, heading structure,
/// in-buffer settings. Recomputed whenever the text changes.
library;

import 'syntax.dart';

enum LineKind {
  blank,
  heading,
  planning,
  drawerBegin,
  drawerEnd,
  property,
  drawerContent,
  blockBegin,
  blockEnd,
  blockContent,
  keyword,
  comment,
  table,
  tableRule,
  listItem,
  hrule,
  fixedWidth,
  footnote,
  text,
}

class LineInfo {
  const LineInfo(this.kind, {this.heading, this.blockType});
  final LineKind kind;
  final HeadingInfo? heading;

  /// Lower-cased block type ("src", "quote", ...) for block lines.
  final String? blockType;

  static const blank = LineInfo(LineKind.blank);
  static const text = LineInfo(LineKind.text);
}

class OrgAnalysis {
  OrgAnalysis._(this.text, this.lines, this.lineStarts, this.infos, this.todo, this.keywords,
      this.startup, this.headingLines, this.regionEnd, this.priorities);

  factory OrgAnalysis(String text) {
    final lines = text.split('\n');
    final starts = List<int>.filled(lines.length, 0);
    var o = 0;
    for (var i = 0; i < lines.length; i++) {
      starts[i] = o;
      o += lines[i].length + 1;
    }

    // Pass 1: in-buffer settings.
    final keywords = <String, String>{};
    final todoValues = <String>[];
    final startup = <String>{};
    String? prioritiesValue;
    for (final l in lines) {
      if (!l.trimLeft().startsWith('#+')) continue;
      final m = keywordRe.firstMatch(l);
      if (m == null) continue;
      final key = m.group(1)!.toUpperCase();
      final value = (m.group(2) ?? '').trim();
      keywords.putIfAbsent(key, () => value);
      if (key == 'TODO' || key == 'SEQ_TODO' || key == 'TYP_TODO') todoValues.add(value);
      if (key == 'STARTUP') {
        startup.addAll(value.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty));
      }
      if (key == 'PRIORITIES') prioritiesValue = value;
    }
    final todo = todoValues.isEmpty ? TodoConfig.defaults : TodoConfig.parse(todoValues);
    var priorities = const PriorityConfig('A', 'C', 'B');
    if (prioritiesValue != null) {
      final parts = prioritiesValue.split(RegExp(r'\s+'));
      if (parts.length >= 3 && parts.every((p) => p.length == 1)) {
        priorities = PriorityConfig(parts[0], parts[1], parts[2]);
      }
    }

    // Pass 2: classification.
    final infos = List<LineInfo>.filled(lines.length, LineInfo.text);
    final headingLines = <int>[];
    final regionEnd = <int, int>{};
    var i = 0;
    while (i < lines.length) {
      final l = lines[i];
      if (l.isEmpty || blankRe.hasMatch(l)) {
        infos[i] = LineInfo.blank;
        i++;
        continue;
      }
      final h = HeadingInfo.parse(l, todo);
      if (h != null) {
        infos[i] = LineInfo(LineKind.heading, heading: h);
        headingLines.add(i);
        i++;
        continue;
      }
      final bm = blockBeginRe.firstMatch(l);
      if (bm != null) {
        final type = bm.group(1)!.toLowerCase();
        final endRe = blockEndRe(type);
        var j = i + 1;
        var found = -1;
        while (j < lines.length) {
          final lj = lines[j];
          if (lj.startsWith('*') && HeadingInfo.isHeading(lj)) break;
          if (endRe.hasMatch(lj)) {
            found = j;
            break;
          }
          j++;
        }
        if (found >= 0) {
          infos[i] = LineInfo(LineKind.blockBegin, blockType: type);
          for (var k = i + 1; k < found; k++) {
            infos[k] = LineInfo(LineKind.blockContent, blockType: type);
          }
          infos[found] = LineInfo(LineKind.blockEnd, blockType: type);
          regionEnd[i] = found;
          i = found + 1;
          continue;
        }
      }
      final dm = drawerBeginRe.firstMatch(l);
      if (dm != null && dm.group(1)!.toUpperCase() != 'END') {
        final isProps = dm.group(1)!.toUpperCase() == 'PROPERTIES';
        var j = i + 1;
        var found = -1;
        while (j < lines.length) {
          final lj = lines[j];
          if (lj.startsWith('*') && HeadingInfo.isHeading(lj)) break;
          if (drawerEndRe.hasMatch(lj)) {
            found = j;
            break;
          }
          j++;
        }
        if (found >= 0) {
          infos[i] = const LineInfo(LineKind.drawerBegin);
          for (var k = i + 1; k < found; k++) {
            infos[k] = LineInfo(isProps && propertyRe.hasMatch(lines[k])
                ? LineKind.property
                : LineKind.drawerContent);
          }
          infos[found] = const LineInfo(LineKind.drawerEnd);
          regionEnd[i] = found;
          i = found + 1;
          continue;
        }
      }
      infos[i] = LineInfo(_classify(l));
      i++;
    }
    return OrgAnalysis._(text, lines, starts, infos, todo, keywords, startup, headingLines,
        regionEnd, priorities);
  }

  /// Analysis of [text], reusing [prev] (the analysis of an earlier version)
  /// for the lines an edit did not touch. Falls back to a full parse when the
  /// edit could change lines elsewhere: headings, #+ lines (keywords and
  /// blocks) and drawer lines in the changed region.
  static OrgAnalysis update(OrgAnalysis prev, String text, [LineDiff? known]) {
    if (prev.lineCount < 2000 || text.isEmpty) return OrgAnalysis(text);
    final d = known ?? LineDiff.between(prev, text);
    final mid = d.newLines;
    bool risky(String l) {
      if (l.startsWith('*') && HeadingInfo.isHeading(l)) return true;
      final t = l.trimLeft();
      if (t.startsWith('#+')) return true;
      return t.startsWith(':') && (drawerBeginRe.hasMatch(l) || drawerEndRe.hasMatch(l));
    }

    for (var k = d.start; k < d.oldEnd; k++) {
      if (risky(prev.lines[k])) return OrgAnalysis(text);
    }
    for (final l in mid) {
      if (risky(l)) return OrgAnalysis(text);
    }

    // The changed lines are either all outside blocks and drawers or all
    // inside the same one.
    bool inside(LineKind k) =>
        k == LineKind.blockContent || k == LineKind.drawerContent || k == LineKind.property;
    final firstKind = prev.infos[d.start].kind;
    final isInside = inside(firstKind);
    for (var k = d.start; k < d.oldEnd; k++) {
      if (inside(prev.infos[k].kind) != isInside) return OrgAnalysis(text);
    }
    String? blockType;
    var props = false;
    if (isInside) {
      if (firstKind == LineKind.blockContent) {
        blockType = prev.infos[d.start].blockType;
      } else {
        var b = d.start;
        while (b > 0 && inside(prev.infos[b].kind)) {
          b--;
        }
        if (prev.infos[b].kind != LineKind.drawerBegin) return OrgAnalysis(text);
        props = prev.lines[b].trim().toUpperCase() == ':PROPERTIES:';
      }
    }

    final midInfos = <LineInfo>[
      for (final l in mid)
        if (isInside)
          blockType != null
              ? LineInfo(LineKind.blockContent, blockType: blockType)
              : LineInfo(props && propertyRe.hasMatch(l) ? LineKind.property : LineKind.drawerContent)
        else if (l.isEmpty || blankRe.hasMatch(l))
          LineInfo.blank
        else
          LineInfo(_classify(l)),
    ];
    final delta = mid.length - (d.oldEnd - d.start);
    final lines = [...prev.lines.sublist(0, d.start), ...mid, ...prev.lines.sublist(d.oldEnd)];
    final infos = [...prev.infos.sublist(0, d.start), ...midInfos, ...prev.infos.sublist(d.oldEnd)];
    final starts = List<int>.filled(lines.length, 0);
    var o = 0;
    for (var i = 0; i < lines.length; i++) {
      starts[i] = o;
      o += lines[i].length + 1;
    }
    final headings = [for (final h in prev.headingLines) h >= d.oldEnd ? h + delta : h];
    final regions = <int, int>{
      for (final e in prev.regionEnd.entries)
        if (e.key >= d.oldEnd) e.key + delta: e.value + delta else e.key: e.value >= d.start ? e.value + delta : e.value,
    };
    return OrgAnalysis._(text, lines, starts, infos, prev.todo, prev.keywords, prev.startup, headings, regions,
        prev.priorities);
  }

  static LineKind _classify(String l) {
    if (planningRe.hasMatch(l)) return LineKind.planning;
    final t = l.trimLeft();
    if (t.startsWith('#')) {
      if (t.startsWith('#+') && keywordRe.hasMatch(l)) return LineKind.keyword;
      if (commentRe.hasMatch(l)) return LineKind.comment;
    }
    if (t.startsWith('|')) return tableRuleRe.hasMatch(l) ? LineKind.tableRule : LineKind.table;
    if (hruleRe.hasMatch(l)) return LineKind.hrule;
    if (listItemRe.hasMatch(l) || starItemRe.hasMatch(l)) return LineKind.listItem;
    if (fixedWidthRe.hasMatch(l)) return LineKind.fixedWidth;
    if (footnoteDefRe.hasMatch(l)) return LineKind.footnote;
    return LineKind.text;
  }

  final String text;
  final List<String> lines;
  final List<int> lineStarts;
  final List<LineInfo> infos;
  final TodoConfig todo;
  final Map<String, String> keywords;
  final Set<String> startup;
  final List<int> headingLines;

  /// For drawer/block begin lines: the line index of the matching end line.
  final Map<int, int> regionEnd;
  final PriorityConfig priorities;

  int get lineCount => lines.length;

  int lineStart(int line) => lineStarts[line];
  int lineEnd(int line) => lineStarts[line] + lines[line].length;

  int lineOfOffset(int offset) {
    var lo = 0, hi = lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  bool isHeading(int line) => line >= 0 && line < infos.length && infos[line].kind == LineKind.heading;
  HeadingInfo? headingInfo(int line) => isHeading(line) ? infos[line].heading : null;
  int levelOf(int line) => infos[line].heading?.level ?? 0;

  /// Index into [headingLines] of the first heading at or after [line].
  int _headingIndexFrom(int line) {
    var lo = 0, hi = headingLines.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (headingLines[mid] < line) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Exclusive end line of the subtree starting at heading [h].
  int subtreeEnd(int h) {
    final level = levelOf(h);
    for (var k = _headingIndexFrom(h + 1); k < headingLines.length; k++) {
      if (levelOf(headingLines[k]) <= level) return headingLines[k];
    }
    return lines.length;
  }

  /// Exclusive end line of the body of heading [h] (up to the next heading).
  int bodyEnd(int h) {
    final k = _headingIndexFrom(h + 1);
    return k < headingLines.length ? headingLines[k] : lines.length;
  }

  /// The heading that owns [line] (the line itself if it is a heading).
  int? headingAtOrAbove(int line) {
    final k = _headingIndexFrom(line + 1) - 1;
    return k >= 0 ? headingLines[k] : null;
  }

  int? parentHeading(int h) {
    final level = levelOf(h);
    for (var k = _headingIndexFrom(h) - 1; k >= 0; k--) {
      if (levelOf(headingLines[k]) < level) return headingLines[k];
    }
    return null;
  }

  List<int> childHeadings(int h) {
    final end = subtreeEnd(h);
    final result = <int>[];
    var minLevel = 1 << 30;
    for (var k = _headingIndexFrom(h + 1); k < headingLines.length && headingLines[k] < end; k++) {
      final lv = levelOf(headingLines[k]);
      if (lv < minLevel) minLevel = lv;
    }
    for (var k = _headingIndexFrom(h + 1); k < headingLines.length && headingLines[k] < end; k++) {
      if (levelOf(headingLines[k]) == minLevel) result.add(headingLines[k]);
    }
    return result;
  }

  List<int> headingsIn(int startLine, int endLine) {
    final result = <int>[];
    for (var k = _headingIndexFrom(startLine); k < headingLines.length && headingLines[k] < endLine; k++) {
      result.add(headingLines[k]);
    }
    return result;
  }

  int? previousSibling(int h) {
    final level = levelOf(h);
    for (var k = _headingIndexFrom(h) - 1; k >= 0; k--) {
      final lv = levelOf(headingLines[k]);
      if (lv == level) return headingLines[k];
      if (lv < level) return null;
    }
    return null;
  }

  int? nextSibling(int h) {
    final level = levelOf(h);
    final end = subtreeEnd(h);
    if (end < lines.length && isHeading(end) && levelOf(end) == level) return end;
    return null;
  }

  /// Line index of the planning line (SCHEDULED/DEADLINE/CLOSED) of heading [h].
  int? planningLine(int h) {
    final l = h + 1;
    if (l < lines.length && infos[l].kind == LineKind.planning) return l;
    return null;
  }

  /// Property drawer of heading [h] as (begin, end) line indices.
  (int, int)? propertyDrawer(int h) {
    var l = h + 1;
    if (l < lines.length && infos[l].kind == LineKind.planning) l++;
    if (l < lines.length &&
        infos[l].kind == LineKind.drawerBegin &&
        lines[l].trim().toUpperCase() == ':PROPERTIES:') {
      final e = regionEnd[l];
      if (e != null) return (l, e);
    }
    return null;
  }

  Map<String, String> properties(int h) {
    final d = propertyDrawer(h);
    final result = <String, String>{};
    if (d == null) return result;
    for (var l = d.$1 + 1; l < d.$2; l++) {
      final m = propertyRe.firstMatch(lines[l]);
      if (m != null) result[m.group(1)!.toUpperCase()] = m.group(2) ?? '';
    }
    return result;
  }

  bool get logDone => startup.contains('logdone');
}

class PriorityConfig {
  const PriorityConfig(this.highest, this.lowest, this.defaultPriority);
  final String highest;
  final String lowest;
  final String defaultPriority;

  /// Priorities from highest to lowest.
  List<String> get all {
    final a = highest.codeUnitAt(0), b = lowest.codeUnitAt(0);
    final step = a <= b ? 1 : -1;
    return [for (var c = a; c != b + step; c += step) String.fromCharCode(c)];
  }
}

/// The lines an edit changed: lines [start, oldEnd) of the old text became
/// [newLines]. Found from the common start and end of the two texts.
class LineDiff {
  LineDiff(this.start, this.oldEnd, this.newLines);

  final int start;
  final int oldEnd;
  final List<String> newLines;

  int get newEnd => start + newLines.length;

  static LineDiff between(OrgAnalysis old, String text) {
    final a = old.text;
    final n = a.length < text.length ? a.length : text.length;
    var pre = 0;
    while (pre < n && a.codeUnitAt(pre) == text.codeUnitAt(pre)) {
      pre++;
    }
    var suf = 0;
    while (suf < n - pre && a.codeUnitAt(a.length - 1 - suf) == text.codeUnitAt(text.length - 1 - suf)) {
      suf++;
    }
    final start = old.lineOfOffset(pre);
    final last = old.lineOfOffset(a.length - suf);
    final oldLineEnd = old.lineEnd(last);
    final newLineEnd = oldLineEnd + text.length - a.length;
    final mid = text.substring(old.lineStarts[start], newLineEnd).split('\n');
    return LineDiff(start, last + 1, mid);
  }
}
