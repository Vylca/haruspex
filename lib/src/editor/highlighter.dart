import 'package:flutter/material.dart';

import '../org/analysis.dart';
import '../org/edits.dart' show cookieRe, linkRe, plainUrlRe;
import '../org/lists.dart';
import '../org/timestamp.dart';
import 'org_theme.dart';

/// Builds styled spans for one line of an Org document at a time. Every
/// displayed string has the same length as the source text, so offsets map
/// one to one.
class OrgHighlighter {
  OrgHighlighter();

  OrgTheme theme = OrgTheme.light;
  String? fontFamily;
  String monoFamily = 'monospace';
  bool hideMarkup = true;
  bool scaleHeadings = true;

  /// org-superstar look: bullets instead of heading stars and list markers.
  bool superstar = true;

  /// Same as org-superstar's default headline bullets. Every replacement is
  /// a single UTF-16 unit so text offsets stay aligned with the buffer.
  static const headlineBullets = ['◉', '○', '✸', '✿'];
  static const itemBullets = {'-': '–', '+': '➤', '*': '•'};

  final Map<String, List<InlineSpan>> _cache = {};

  void clearCache() => _cache.clear();

  /// Markup hidden away from the caret (link brackets, emphasis markers).
  static const TextStyle hiddenStyle = TextStyle(
    fontSize: 0.00001,
    height: 1.0,
    color: Color(0x00000000),
    letterSpacing: 0,
    wordSpacing: 0,
    decoration: TextDecoration.none,
    fontWeight: FontWeight.normal,
    fontStyle: FontStyle.normal,
  );

  TextStyle get _mono => TextStyle(fontFamily: monoFamily);

  double headingScale(int level) {
    if (!scaleHeadings) return 1.0;
    return switch (level) { 1 => 1.32, 2 => 1.18, 3 => 1.08, _ => 1.0 };
  }

  /// Cache key of a line's spans.
  String lineKey(OrgAnalysis a, int i, bool active, [String? salt]) {
    final info = a.infos[i];
    return '${info.kind.index}|${active ? 1 : 0}|${info.blockType ?? ''}|${_headerRow(a, i) ? 1 : 0}|'
        '${salt ?? a.todo.all.join(',')}|${a.lines[i]}';
  }

  /// Styled spans for line [i] (without the line break). [active] lines show
  /// their markup in full.
  List<InlineSpan> lineSpans(OrgAnalysis a, int i, bool active, [String? key]) {
    if (_cache.length > 20000) _cache.clear();
    final k = key ?? lineKey(a, i, active);
    final cached = _cache[k];
    if (cached != null) return cached;
    final spans = _line(a, i, a.infos[i], a.lines[i], active);
    _cache[k] = spans;
    return spans;
  }

  /// Style of a heading line at [level], relative to the base style.
  TextStyle headingStyle(int level) =>
      TextStyle(fontSize: _baseSize * headingScale(level), fontWeight: FontWeight.w600);

  /// What a heading's stars and following space look like on screen.
  String headingPrefix(int level) {
    final bullet = superstar ? headlineBullets[(level - 1) % headlineBullets.length] : '*';
    return '${'*' * (level - 1)}$bullet ';
  }

  bool _headerRow(OrgAnalysis a, int i) {
    final k = a.infos[i].kind;
    if (k != LineKind.table) return false;
    // A header row is a data row followed (within the table) by a rule.
    var j = i + 1;
    while (j < a.lines.length && a.infos[j].kind == LineKind.table) {
      j++;
    }
    if (j >= a.lines.length || a.infos[j].kind != LineKind.tableRule) return false;
    var s = i;
    while (s > 0 && (a.infos[s - 1].kind == LineKind.table || a.infos[s - 1].kind == LineKind.tableRule)) {
      if (a.infos[s - 1].kind == LineKind.tableRule) return false;
      s--;
    }
    return true;
  }

  double _baseSize = 16;
  double get baseFontSize => _baseSize;
  set baseFontSize(double v) {
    if (v != _baseSize) {
      _baseSize = v;
      _cache.clear();
    }
  }

  List<InlineSpan> _line(OrgAnalysis a, int i, LineInfo info, String line, bool active) {
    final t = theme;
    final faint = TextStyle(color: t.faint);
    switch (info.kind) {
      case LineKind.blank:
        return line.isEmpty ? const [] : [TextSpan(text: line)];
      case LineKind.heading:
        return _heading(a, info, line, active);
      case LineKind.planning:
        return _planning(line);
      case LineKind.drawerBegin:
      case LineKind.drawerEnd:
        return [TextSpan(text: line, style: faint.copyWith(fontWeight: FontWeight.w600))];
      case LineKind.property:
        final m = RegExp(r'^([ \t]*:[^\s:]+:)(.*)$').firstMatch(line);
        if (m == null) return [TextSpan(text: line, style: faint)];
        return [
          TextSpan(text: m.group(1), style: TextStyle(color: t.tag, fontWeight: FontWeight.w600)),
          TextSpan(text: m.group(2), style: faint),
        ];
      case LineKind.drawerContent:
        return [TextSpan(text: line, style: faint)];
      case LineKind.blockBegin:
      case LineKind.blockEnd:
        return [TextSpan(text: line, style: _mono.copyWith(color: t.faint, fontSize: _baseSize * 0.88))];
      case LineKind.blockContent:
        final type = info.blockType ?? '';
        if (type == 'src' || type == 'example' || type == 'export') {
          return [TextSpan(text: line, style: _mono.copyWith(color: t.code))];
        }
        if (type == 'quote' || type == 'verse') {
          return _inline(line, const TextStyle(fontStyle: FontStyle.italic), active, 0);
        }
        if (type == 'comment') return [TextSpan(text: line, style: faint)];
        return _inline(line, const TextStyle(), active, 0);
      case LineKind.keyword:
        final m = RegExp(r'^([ \t]*#\+[^\s:]+:)([ \t]*)(.*)$').firstMatch(line);
        if (m == null) return [TextSpan(text: line, style: faint)];
        final key = m.group(1)!.trim().toUpperCase();
        TextStyle valueStyle = const TextStyle();
        if (key == '#+TITLE:') {
          valueStyle = TextStyle(fontSize: _baseSize * 1.5, fontWeight: FontWeight.w700, color: t.text);
        } else if (key == '#+SUBTITLE:') {
          valueStyle = TextStyle(fontSize: _baseSize * 1.15, color: t.faint);
        } else if (const {'#+TODO:', '#+SEQ_TODO:', '#+TYP_TODO:', '#+STARTUP:', '#+OPTIONS:', '#+PRIORITIES:', '#+TBLFM:'}
            .contains(key)) {
          valueStyle = TextStyle(color: t.faint);
        }
        return [
          TextSpan(text: m.group(1), style: faint),
          TextSpan(text: m.group(2)),
          TextSpan(text: m.group(3), style: valueStyle),
        ];
      case LineKind.comment:
        return [TextSpan(text: line, style: faint.copyWith(fontStyle: FontStyle.italic))];
      case LineKind.table:
        return _tableRow(line, _headerRow(a, i));
      case LineKind.tableRule:
        return [TextSpan(text: line, style: _mono.copyWith(color: t.faint))];
      case LineKind.listItem:
        return _listItem(line, active);
      case LineKind.hrule:
        return [TextSpan(text: line, style: faint)];
      case LineKind.fixedWidth:
        return [TextSpan(text: line, style: _mono.copyWith(color: t.faint))];
      case LineKind.footnote:
        final m = RegExp(r'^\[fn:[^\]\s]+\]').firstMatch(line)!;
        return [
          TextSpan(text: m.group(0), style: TextStyle(color: t.link)),
          ..._inline(line.substring(m.end), const TextStyle(), active, 0),
        ];
      case LineKind.text:
        return _inline(line, const TextStyle(), active, 0);
    }
  }

  List<InlineSpan> _heading(OrgAnalysis a, LineInfo info, String line, bool active) {
    final t = theme;
    final h = info.heading!;
    final scale = headingScale(h.level);
    final size = _baseSize * scale;
    final done = a.todo.isDone(h.keyword);
    final color = done ? t.faint : t.level(h.level);
    final base = TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w600);
    final spans = <InlineSpan>[];
    var p = 0;
    void plain(int to, [TextStyle? s]) {
      if (to > p) spans.add(TextSpan(text: line.substring(p, to), style: s ?? base));
      p = to;
    }

    // Leading stars: hidden with superstar (they still indent the bullet),
    // faint otherwise. The last star becomes the level's bullet.
    if (h.level > 1) {
      spans.add(TextSpan(
        text: line.substring(0, h.level - 1),
        style: base.copyWith(color: superstar ? const Color(0x00000000) : t.faint.withValues(alpha: 0.45)),
      ));
    }
    spans.add(TextSpan(
      text: superstar ? headlineBullets[(h.level - 1) % headlineBullets.length] : '*',
      style: base,
    ));
    p = h.level;
    if (h.kwStart >= 0) {
      plain(h.kwStart);
      plain(h.kwEnd, base.copyWith(color: done ? t.done : t.todo, fontWeight: FontWeight.w800));
    }
    if (h.prioStart >= 0) {
      plain(h.prioStart);
      plain(h.prioEnd, base.copyWith(color: t.priority, fontWeight: FontWeight.w700));
    }
    plain(h.titleStart);
    if (h.titleEnd > h.titleStart) {
      spans.addAll(_inline(line.substring(h.titleStart, h.titleEnd), base, active, 0));
      p = h.titleEnd;
    }
    if (h.tagsStart >= 0) {
      plain(h.tagsStart);
      plain(h.tagsEnd, base.copyWith(color: t.tag, fontWeight: FontWeight.w500, fontSize: size * 0.85));
    }
    plain(line.length);
    return spans;
  }

  List<InlineSpan> _planning(String line) {
    final t = theme;
    final spans = <InlineSpan>[];
    var p = 0;
    final tokens = <(int, int, TextStyle)>[];
    for (final m in RegExp(r'(SCHEDULED|DEADLINE|CLOSED):').allMatches(line)) {
      tokens.add((m.start, m.end, TextStyle(color: t.faint, fontWeight: FontWeight.w700)));
    }
    for (final (m, _) in OrgTimestamp.findAll(line)) {
      tokens.add((m.start, m.end, TextStyle(color: t.timestamp)));
    }
    tokens.sort((x, y) => x.$1.compareTo(y.$1));
    for (final (s, e, st) in tokens) {
      if (s < p) continue;
      if (s > p) spans.add(TextSpan(text: line.substring(p, s), style: TextStyle(color: t.faint)));
      spans.add(TextSpan(text: line.substring(s, e), style: st));
      p = e;
    }
    if (p < line.length) spans.add(TextSpan(text: line.substring(p), style: TextStyle(color: t.faint)));
    return spans;
  }

  List<InlineSpan> _tableRow(String line, bool header) {
    final t = theme;
    final cell = _mono.copyWith(color: t.text, fontWeight: header ? FontWeight.w700 : null);
    final bar = _mono.copyWith(color: t.faint);
    final spans = <InlineSpan>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isNotEmpty) {
        spans.add(TextSpan(text: buf.toString(), style: cell));
        buf.clear();
      }
    }

    for (var k = 0; k < line.length; k++) {
      final c = line[k];
      if (c == '|') {
        flush();
        spans.add(TextSpan(text: c, style: bar));
      } else {
        buf.write(c);
      }
    }
    flush();
    return spans;
  }

  List<InlineSpan> _listItem(String line, bool active) {
    final t = theme;
    final it = ListItemInfo.parse(line, 0);
    if (it == null) return _inline(line, const TextStyle(), active, 0);
    final spans = <InlineSpan>[];
    if (it.bulletStart > 0) spans.add(TextSpan(text: line.substring(0, it.bulletStart)));
    final bullet = line.substring(it.bulletStart, it.bulletEnd);
    spans.add(TextSpan(
      text: superstar ? (itemBullets[bullet] ?? bullet) : bullet,
      style: TextStyle(color: t.accent, fontWeight: FontWeight.w700),
    ));
    var p = it.bulletEnd;
    if (it.checkbox != null) {
      if (it.cbStart > p) spans.add(TextSpan(text: line.substring(p, it.cbStart)));
      final color = switch (it.checkbox) { 'X' => t.done, '-' => t.priority, _ => t.todo };
      spans.add(TextSpan(
        text: line.substring(it.cbStart, it.cbEnd),
        style: _mono.copyWith(color: color, fontWeight: FontWeight.w700),
      ));
      p = it.cbEnd;
    }
    final rest = line.substring(p);
    final done = it.checkbox == 'X';
    final restStyle = done ? TextStyle(color: t.faint) : const TextStyle();
    final dm = RegExp(r'^(\s*)(.*?)(\s+::)(\s|$)').firstMatch(rest);
    if (dm != null) {
      spans.add(TextSpan(text: dm.group(1)));
      spans.addAll(_inline(dm.group(2)!, restStyle.copyWith(fontWeight: FontWeight.w700), active, 0));
      spans.add(TextSpan(text: dm.group(3), style: TextStyle(color: t.faint)));
      final consumed = dm.group(1)!.length + dm.group(2)!.length + dm.group(3)!.length;
      spans.addAll(_inline(rest.substring(consumed), restStyle, active, 0));
    } else {
      spans.addAll(_inline(rest, restStyle, active, 0));
    }
    return spans;
  }

  // -------------------------------------------------------------------------
  // Inline markup
  // -------------------------------------------------------------------------

  static final RegExp _emphRe =
      RegExp(r'''(?<=^|[\s\-('"{])([*/_+])(?=\S)(.+?)(?<=\S)\1(?=$|[\s\-.,:!?;'")}\[])''');
  static final RegExp _verbRe =
      RegExp(r'''(?<=^|[\s\-('"{])([=~])(?=\S)(.+?)(?<=\S)\1(?=$|[\s\-.,:!?;'")}\[])''');
  static final RegExp _footRe = RegExp(r'\[fn:[^\]\s]*\]');
  static final RegExp _targetRe = RegExp(r'<<<?[^<>\n]+>>>?');
  static final RegExp _macroRe = RegExp(r'\{\{\{[^}]+\}\}\}');

  List<InlineSpan> _inline(String s, TextStyle style, bool active, int depth) {
    if (s.isEmpty) return const [];
    final t = theme;
    final tokens = <_Tok>[];
    void collect(RegExp re, int type) {
      for (final m in re.allMatches(s)) {
        if (m.end > m.start) tokens.add(_Tok(m, type));
      }
    }

    if (s.contains('[[')) collect(linkRe, 0);
    if (s.contains('<') || s.contains('[')) {
      for (final (m, _) in OrgTimestamp.findAll(s)) {
        tokens.add(_Tok(m, 1));
      }
    }
    if (s.contains('[fn:')) collect(_footRe, 2);
    if (s.contains('[')) collect(cookieRe, 3);
    if (s.contains('<<')) collect(_targetRe, 4);
    if (s.contains('{{{')) collect(_macroRe, 5);
    if (s.contains('=') || s.contains('~')) collect(_verbRe, 6);
    collect(_emphRe, 7);
    if (s.contains(':')) collect(plainUrlRe, 8);
    if (tokens.isEmpty) return [TextSpan(text: s, style: style)];
    tokens.sort((a, b) {
      final c = a.m.start.compareTo(b.m.start);
      return c != 0 ? c : a.type.compareTo(b.type);
    });

    final markup = active || !hideMarkup ? style.merge(TextStyle(color: t.faint)) : hiddenStyle;
    final spans = <InlineSpan>[];
    var p = 0;
    for (final tok in tokens) {
      final m = tok.m;
      if (m.start < p) continue;
      if (m.start > p) spans.add(TextSpan(text: s.substring(p, m.start), style: style));
      switch (tok.type) {
        case 0: // link
          final target = m.group(1)!;
          final desc = m.group(2);
          final linkStyle = style.merge(TextStyle(
            color: t.link,
            decoration: TextDecoration.underline,
            decorationColor: t.link.withValues(alpha: 0.5),
          ));
          if (desc != null) {
            final descStart = m.start + 2 + target.length + 2;
            spans.add(TextSpan(text: s.substring(m.start, descStart), style: markup));
            spans.add(TextSpan(text: desc, style: linkStyle));
            spans.add(TextSpan(text: ']]', style: markup));
          } else {
            spans.add(TextSpan(text: '[[', style: markup));
            spans.add(TextSpan(text: target, style: linkStyle));
            spans.add(TextSpan(text: ']]', style: markup));
          }
        case 1: // timestamp
          spans.add(TextSpan(text: m.group(0), style: style.merge(TextStyle(color: t.timestamp))));
        case 2: // footnote reference
          spans.add(TextSpan(text: m.group(0), style: style.merge(TextStyle(color: t.link))));
        case 3: // statistics cookie
          final c = m.group(1)!;
          var complete = false;
          if (c.endsWith('%')) {
            complete = c == '100%';
          } else {
            final parts = c.split('/');
            complete = parts.length == 2 && parts[0].isNotEmpty && parts[0] == parts[1];
          }
          spans.add(TextSpan(
            text: m.group(0),
            style: style.merge(TextStyle(color: complete ? t.done : t.todo, fontWeight: FontWeight.w700)),
          ));
        case 4: // target
          spans.add(TextSpan(
            text: m.group(0),
            style: style.merge(TextStyle(color: t.link, decoration: TextDecoration.underline)),
          ));
        case 5: // macro
          spans.add(TextSpan(text: m.group(0), style: style.merge(TextStyle(color: t.faint))));
        case 6: // verbatim / code
          final codeStyle = style.merge(_mono).merge(TextStyle(color: t.code, backgroundColor: t.codeBg));
          spans.add(TextSpan(text: m.group(1), style: markup));
          spans.add(TextSpan(text: m.group(2), style: codeStyle));
          spans.add(TextSpan(text: m.group(1), style: markup));
        case 7: // emphasis
          final marker = m.group(1)!;
          final inner = switch (marker) {
            '*' => const TextStyle(fontWeight: FontWeight.w700),
            '/' => const TextStyle(fontStyle: FontStyle.italic),
            '_' => const TextStyle(decoration: TextDecoration.underline),
            _ => const TextStyle(decoration: TextDecoration.lineThrough),
          };
          final merged = style.merge(inner);
          spans.add(TextSpan(text: marker, style: markup));
          if (depth < 2) {
            spans.addAll(_inline(m.group(2)!, merged, active, depth + 1));
          } else {
            spans.add(TextSpan(text: m.group(2), style: merged));
          }
          spans.add(TextSpan(text: marker, style: markup));
        case 8: // plain URL
          spans.add(TextSpan(
            text: m.group(0),
            style: style.merge(TextStyle(color: t.link, decoration: TextDecoration.underline)),
          ));
      }
      p = m.end;
    }
    if (p < s.length) spans.add(TextSpan(text: s.substring(p), style: style));
    return spans;
  }
}

class _Tok {
  _Tok(this.m, this.type);
  final RegExpMatch m;
  final int type;
}
