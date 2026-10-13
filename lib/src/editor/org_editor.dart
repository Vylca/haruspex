import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/document.dart';
import '../app/settings.dart';
import '../org/analysis.dart';
import '../org/edits.dart';
import '../org/lists.dart';
import '../org/table.dart';
import '../org/timestamp.dart';
import '../ui/dialogs.dart';
import 'line_layout.dart';
import 'org_controller.dart';
import 'org_theme.dart';

abstract class EditorHost {
  void showMessage(String message);
  void setPrefixActive(bool active);
  Future<void> openLink(String target, OrgDocument from);
  void openAgenda();
}

/// The Org text editor. Every logical line is laid out as its own paragraph,
/// which gives per-line indentation (org-indent style), real folding (hidden
/// lines are simply not laid out) and scrolling that only paints what is on
/// screen. Text input goes through the platform text input connection.
class OrgEditor extends StatefulWidget {
  const OrgEditor({super.key, required this.doc, required this.host, required this.settings});

  final OrgDocument doc;
  final EditorHost host;
  final AppSettings settings;

  @override
  State<OrgEditor> createState() => OrgEditorState();
}

/// A laid out line from the last layout pass, with what its look depends on.
class _LineEntry {
  _LineEntry(this.key, this.text, this.kind, this.block, this.header, this.active, this.indent, this.layout);

  final String key;
  final String text;
  final LineKind kind;
  final String? block;
  final bool header;
  final bool active;
  final double indent;
  final LineLayout layout;
}

class _CaretGeometry {
  _CaretGeometry(this.index, this.rect, this.lineTop, this.lineBottom);

  /// Index into the visible lines.
  final int index;

  /// Caret rectangle in content coordinates.
  final Rect rect;

  /// Visual line containing the caret, in content coordinates.
  final double lineTop;
  final double lineBottom;
}

/// Paints the lines on screen. The whole document is one tall canvas;
/// only the lines inside the viewport are drawn, found by binary search.
class _DocPainter extends CustomPainter {
  _DocPainter(this.s) : super(repaint: s._caretOn);

  final OrgEditorState s;

  @override
  void paint(Canvas canvas, Size size) => s._paintVisible(canvas, size);

  @override
  bool shouldRepaint(covariant _DocPainter old) => true;
}

class OrgEditorState extends State<OrgEditor> with TextInputClient {
  static const double _vpad = 8;
  static const double _caretWidth = 2;

  /// Space between the line numbers and the text.
  static const double _gutterGap = 12;

  /// Line height as a multiple of the font size, rounded to whole pixels with
  /// the same spacing above and below the text.
  static double _snappedLineHeight(double fontSize, double lineHeight) {
    if (fontSize <= 0) return lineHeight;
    final extra = ((fontSize * lineHeight - fontSize) / 2).round();
    return (fontSize + 2 * math.max<int>(0, extra)) / fontSize;
  }

  bool _prefix = false;

  OrgDocument get doc => widget.doc;
  OrgController get c => doc.controller;
  OrgAnalysis get a => c.analysis;

  int get caret {
    final s = c.selection;
    if (!s.isValid) return 0;
    return s.extentOffset.clamp(0, c.text.length);
  }

  int get caretLine => a.lineOfOffset(caret);
  int get caretCol => caret - a.lineStarts[caretLine];
  LineInfo get lineInfo => a.infos[caretLine];
  bool get inTable => lineInfo.kind == LineKind.table || lineInfo.kind == LineKind.tableRule;
  bool get onHeading => lineInfo.kind == LineKind.heading;

  void _message(String m) => widget.host.showMessage(m);

  void _setPrefix(bool on) {
    _prefix = on;
    widget.host.setPrefixActive(on);
  }

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  // Layout of the visible lines, refreshed by [_relayout].
  final LineLayoutCache _cache = LineLayoutCache();
  List<_LineEntry> _lineEntries = const [];
  String _lineEnv = '';
  List<int> _visible = const [];
  List<LineLayout> _layouts = const [];
  List<double> _tops = const [];
  double _totalHeight = 0;
  double _hpad = 20;
  double _rpad = 20;
  final Map<String, TextPainter> _gutterCache = {};
  double _textWidth = 600;
  int _caretIndex = -1;
  TextStyle _baseStyle = const TextStyle();
  OrgTheme _theme = OrgTheme.hev;
  TextScaler _textScaler = TextScaler.noScaling;
  double _caretRatio = 1.0;
  String _styleSig = '';
  final Map<int, double> _prefixWidths = {};
  OrgAnalysis? _sigAnalysis;
  List<int>? _sigVisible;
  int _sigFrom = -2, _sigTo = -2;
  double _sigWidth = -1;
  String _sigStyle = '';

  // Platform text input.
  TextInputConnection? _connection;
  TextEditingValue? _lastRemote;
  bool _imeScheduled = false;

  // Caret.
  final ValueNotifier<bool> _caretOn = ValueNotifier<bool>(true);
  Timer? _blink;
  double? _goalX;

  // Undo history.
  final List<TextEditingValue> _undo = [];
  final List<TextEditingValue> _redo = [];
  late TextEditingValue _lastValue;
  DateTime _lastEdit = DateTime(0);
  bool _restoring = false;
  bool _structural = false;
  int _lastKind = 0;

  // Pointer.
  final GlobalKey _viewportKey = GlobalKey();
  int _clicks = 0;
  DateTime _lastClick = DateTime(0);
  Offset _lastClickPos = Offset.zero;
  bool _dragging = false;
  int _dragMode = 1;
  int _dragBase = 0;
  TextRange _dragUnit = TextRange.empty;
  Offset? _touchDown;

  @override
  void initState() {
    super.initState();
    _lastValue = c.value;
    _remoteValue(c.value);
    c.addListener(_onControllerChanged);
    doc.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    c.removeListener(_onControllerChanged);
    doc.focusNode.removeListener(_onFocusChanged);
    _closeConnection();
    _blink?.cancel();
    _caretOn.dispose();
    _cache.clear();
    _clearGutterCache();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (doc.focusNode.hasFocus) {
      if (!c.selection.isValid) c.selection = const TextSelection.collapsed(offset: 0);
      _openConnection();
      _restartBlink();
    } else {
      _closeConnection();
      _blink?.cancel();
      _caretOn.value = false;
    }
    setState(() {});
  }

  void _onControllerChanged() {
    final v = c.value;
    if (v.text != _lastValue.text && !_restoring) {
      final now = DateTime.now();
      // A new undo step starts after a pause, on structural edits, and when
      // switching between typing and deleting.
      final kind = v.text.length >= _lastValue.text.length ? 1 : -1;
      final boundary = _structural ||
          _undo.isEmpty ||
          kind != _lastKind ||
          now.difference(_lastEdit) > const Duration(milliseconds: 900);
      _lastKind = kind;
      if (boundary) {
        _undo.add(_lastValue.copyWith(composing: TextRange.empty));
        if (_undo.length > 500) _undo.removeAt(0);
      }
      _redo.clear();
      _lastEdit = _structural ? DateTime(0) : now;
    }
    _lastValue = v;
    // Always recomputed, so the input method's lines match the document.
    final rv = _remoteValue(v);
    final conn = _connection;
    if (conn != null && conn.attached && rv != _lastRemote) {
      _lastRemote = rv;
      conn.setEditingState(rv);
    }
    _restartBlink();
    if (mounted) setState(() {});
  }

  /// The caret stays lit while the editor has focus (no blinking, like Doom
  /// Emacs).
  void _restartBlink() {
    _blink?.cancel();
    if (!doc.focusNode.hasFocus) return;
    _caretOn.value = true;
  }

  // -------------------------------------------------------------------------
  // Platform text input
  // -------------------------------------------------------------------------

  /// The input method only sees the lines around the caret, from
  /// [_remoteStart] to [_remoteEnd] in the document, so typing in a big
  /// document does not send the whole text on every key.
  int _remoteStart = 0;
  int _remoteEnd = 0;

  TextEditingValue _remoteValue(TextEditingValue v) {
    final text = v.text;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: text.length);
    final comp = v.composing;
    final hasComp = comp.isValid && !comp.isCollapsed;
    var lo = sel.start, hi = sel.end;
    if (hasComp) {
      lo = math.min<int>(lo, comp.start);
      hi = math.max<int>(hi, comp.end);
    }
    lo = lo.clamp(0, text.length);
    hi = hi.clamp(lo, text.length);
    final start = lo == 0 ? 0 : text.lastIndexOf('\n', lo - 1) + 1;
    var end = text.indexOf('\n', hi);
    if (end < 0) end = text.length;
    _remoteStart = start;
    _remoteEnd = end;
    return TextEditingValue(
      text: text.substring(start, end),
      selection: TextSelection(
        baseOffset: sel.baseOffset.clamp(start, end) - start,
        extentOffset: sel.extentOffset.clamp(start, end) - start,
        affinity: sel.affinity,
        isDirectional: sel.isDirectional,
      ),
      composing: hasComp ? TextRange(start: comp.start - start, end: comp.end - start) : TextRange.empty,
    );
  }

  void _openConnection() {
    final conn = _connection;
    if (conn != null && conn.attached) {
      conn.show();
      return;
    }
    final config = TextInputConfiguration(
      viewId: View.of(context).viewId,
      inputType: TextInputType.multiline,
      inputAction: TextInputAction.newline,
      autocorrect: false,
      enableSuggestions: false,
      keyboardAppearance: Theme.of(context).brightness,
    );
    final value = _remoteValue(c.value);
    _connection = TextInput.attach(this, config)
      ..setEditingState(value)
      ..show();
    _lastRemote = value;
    _scheduleImeGeometry();
  }

  void _closeConnection() {
    final conn = _connection;
    if (conn != null && conn.attached) conn.close();
    _connection = null;
  }

  void _scheduleImeGeometry() {
    if (_imeScheduled) return;
    _imeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _imeScheduled = false;
      final conn = _connection;
      if (!mounted || conn == null || !conn.attached) return;
      final box = _viewportKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      conn.setEditableSizeAndTransform(box.size, box.getTransformTo(null));
      final g = _geometry(caret);
      if (g != null) {
        final scroll = doc.scroll.hasClients ? doc.scroll.offset : 0.0;
        final r = g.rect.shift(Offset(_hpad, _vpad - scroll));
        conn.setCaretRect(r);
        conn.setComposingRect(r);
      }
    });
  }

  @override
  TextEditingValue? get currentTextEditingValue => _remoteValue(c.value);

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    _lastRemote = value;
    // Put the input method's lines back into the document.
    final full = c.value;
    final start = _remoteStart.clamp(0, full.text.length);
    final end = _remoteEnd.clamp(start, full.text.length);
    final sel = value.selection;
    final comp = value.composing;
    final next = TextEditingValue(
      text: full.text.replaceRange(start, end, value.text),
      selection: sel.isValid
          ? TextSelection(
              baseOffset: sel.baseOffset + start,
              extentOffset: sel.extentOffset + start,
              affinity: sel.affinity,
              isDirectional: sel.isDirectional,
            )
          : full.selection,
      composing: comp.isValid ? TextRange(start: comp.start + start, end: comp.end + start) : TextRange.empty,
    );
    if (next == full) return;
    _remoteEnd = start + value.text.length;
    _goalX = null;
    c.value = next;
    revealCaret();
  }

  @override
  void performAction(TextInputAction action) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
  }

  // -------------------------------------------------------------------------
  // Layout
  // -------------------------------------------------------------------------

  double _indentFor(OrgAnalysis an, int i) {
    if (!widget.settings.indentBody || an.isHeading(i)) return 0;
    final h = an.headingAtOrAbove(i);
    if (h == null) return 0;
    return _prefixWidth(an.levelOf(h));
  }

  double _prefixWidth(int level) {
    final cached = _prefixWidths[level];
    if (cached != null) return cached;
    final hl = c.highlighter;
    final p = TextPainter(
      text: TextSpan(text: hl.headingPrefix(level), style: _baseStyle.merge(hl.headingStyle(level))),
      textDirection: TextDirection.ltr,
      textScaler: _textScaler,
    )..layout();
    final w = p.width;
    p.dispose();
    _prefixWidths[level] = w;
    return w;
  }

  /// Lays out the visible lines if anything they depend on changed.
  void _relayout() {
    final an = a;
    final visible = c.visibleLines;
    final sel = c.selection;
    var from = -1, to = -1;
    if (sel.isValid) {
      final len = an.text.length;
      from = an.lineOfOffset(sel.start.clamp(0, len));
      to = an.lineOfOffset(sel.end.clamp(0, len));
    }
    if (identical(_sigAnalysis, an) &&
        identical(_sigVisible, visible) &&
        _sigFrom == from &&
        _sigTo == to &&
        _sigWidth == _textWidth &&
        _sigStyle == _styleSig) {
      return;
    }
    final hl = c.highlighter;
    final salt = an.todo.all.join(',');
    // Lines are matched against the previous pass by their common prefix and
    // suffix, so an edit or a caret move only lays out the lines it touched.
    final env = '$salt|$_textWidth|$_styleSig';
    final old = env == _lineEnv ? _lineEntries : const <_LineEntry>[];
    final n = visible.length, m = old.length;
    var p = 0;
    while (p < n && p < m && old[p].text == an.lines[visible[p]]) {
      p++;
    }
    var q = 0;
    while (q < n - p && q < m - p && old[m - 1 - q].text == an.lines[visible[n - 1 - q]]) {
      q++;
    }
    final entries = <_LineEntry>[];
    final layouts = <LineLayout>[];
    final tops = <double>[];
    var y = 0.0;
    var caretIndex = -1;
    final caretL = sel.isValid ? an.lineOfOffset(sel.extentOffset.clamp(0, an.text.length)) : -1;
    for (var k = 0; k < n; k++) {
      final i = visible[k];
      if (i == caretL) caretIndex = k;
      final info = an.infos[i];
      final active = i >= from && i <= to;
      final indent = _indentFor(an, i);
      final header = info.kind == LineKind.table && hl.isHeaderRow(an, i);
      final prev = k < p ? old[k] : (k >= n - q ? old[k - n + m] : null);
      _LineEntry entry;
      if (prev != null &&
          prev.kind == info.kind &&
          prev.block == info.blockType &&
          prev.header == header &&
          prev.active == active &&
          prev.indent == indent) {
        _cache.keep(prev.key, prev.layout);
        entry = prev;
      } else {
        final width = math.max<double>(10.0, _textWidth - indent - 4);
        final lineKey = hl.lineKey(an, i, active, salt);
        final key = '$lineKey|$indent|$width|$_styleSig';
        final lay = _cache.get(key, () {
          final spans = hl.lineSpans(an, i, active, lineKey);
          final painter = TextPainter(
            text: TextSpan(style: _baseStyle, children: spans),
            textDirection: TextDirection.ltr,
            textScaler: _textScaler,
          )..layout(maxWidth: width);
          return LineLayout(painter, indent);
        });
        entry = _LineEntry(key, an.lines[i], info.kind, info.blockType, header, active, indent, lay);
      }
      entries.add(entry);
      tops.add(y);
      layouts.add(entry.layout);
      y += entry.layout.height;
    }
    _lineEntries = entries;
    _lineEnv = env;
    _cache.endPass();
    _visible = visible;
    _layouts = layouts;
    _tops = tops;
    _totalHeight = y;
    _caretIndex = caretIndex;
    _sigAnalysis = an;
    _sigVisible = visible;
    _sigFrom = from;
    _sigTo = to;
    _sigWidth = _textWidth;
    _sigStyle = _styleSig;
  }

  int _visibleIndex(int line) {
    var lo = 0, hi = _visible.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final v = _visible[mid];
      if (v == line) return mid;
      if (v < line) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  Rect _caretProto(LineLayout lay) => Rect.fromLTWH(0, 0, _caretWidth, lay.painter.preferredLineHeight);

  /// Top and bottom of the visual line that holds the caret at [local]
  /// (a line of [len] characters).
  (double, double) _caretLine(LineLayout lay, int local, int len) {
    final ms = lay.metrics;
    if (len == 0 || ms.isEmpty) return (0, lay.height);
    if (local >= len) {
      final m = ms.last;
      return (m.baseline - m.ascent, m.baseline + m.descent);
    }
    final pos = TextPosition(offset: local);
    final proto = _caretProto(lay);
    final p = lay.painter.getOffsetForCaret(pos, proto);
    final h = lay.painter.getFullHeightForCaret(pos, proto);
    return lay.visualLineAt(p.dy + h / 2);
  }

  /// The caret at [local] in line coordinates: centered on the character
  /// boundary and on its visual line, as tall as the text.
  Rect _caretIn(LineLayout lay, int local, int len) {
    final x = lay.painter.getOffsetForCaret(TextPosition(offset: local), _caretProto(lay)).dx;
    final (top, bottom) = _caretLine(lay, local, len);
    final h = (bottom - top) * _caretRatio;
    return Rect.fromLTWH(x - _caretWidth / 2, (top + bottom - h) / 2, _caretWidth, h);
  }

  /// Height of the text relative to its line (which includes the line
  /// spacing), used to size the caret.
  double _measureCaretRatio() {
    final p = TextPainter(
      text: TextSpan(text: 'x', style: _baseStyle),
      textDirection: TextDirection.ltr,
      textScaler: _textScaler,
    )..layout();
    final boxes = p.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1));
    final lineHeight = p.height;
    p.dispose();
    if (boxes.isEmpty || lineHeight <= 0) return 1.0;
    final b = boxes.first;
    return ((b.bottom - b.top) / lineHeight).clamp(0.3, 1.0);
  }

  _CaretGeometry? _geometry(int offset) {
    _relayout();
    final an = a;
    final o = offset.clamp(0, an.text.length);
    final line = an.lineOfOffset(o);
    final k = _visibleIndex(line);
    if (k < 0 || k >= _layouts.length) return null;
    final lay = _layouts[k];
    final len = an.lines[line].length;
    final local = (o - an.lineStarts[line]).clamp(0, len);
    final (top, bottom) = _caretLine(lay, local, len);
    final r = _caretIn(lay, local, len);
    return _CaretGeometry(k, r.shift(Offset(lay.indent, _tops[k])), _tops[k] + top, _tops[k] + bottom);
  }

  /// Text offset at a point in content coordinates.
  int _offsetAt(Offset p) {
    _relayout();
    if (_visible.isEmpty) return 0;
    final y = p.dy < 0 ? 0.0 : p.dy;
    var lo = 0, hi = _tops.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_tops[mid] <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final lay = _layouts[lo];
    final localY = (y - _tops[lo]).clamp(0.0, math.max<double>(0.0, lay.height - 0.5));
    final pos = lay.painter.getPositionForOffset(Offset(p.dx - lay.indent, localY));
    final line = _visible[lo];
    return a.lineStarts[line] + pos.offset.clamp(0, a.lines[line].length);
  }

  Offset _toContent(Offset local) {
    final scroll = doc.scroll.hasClients ? doc.scroll.offset : 0.0;
    return Offset(local.dx - _hpad, local.dy + scroll - _vpad);
  }

  // -------------------------------------------------------------------------
  // Painting
  // -------------------------------------------------------------------------

  double _viewportHeight = 600;

  /// Paints the lines that intersect the viewport.
  void _paintVisible(Canvas canvas, Size size) {
    if (_layouts.isEmpty) return;
    final scroll = doc.scroll.hasClients ? doc.scroll.offset : 0.0;
    final top = scroll - _vpad - 4;
    final bottom = scroll - _vpad + _viewportHeight + 4;
    // First line whose bottom is below the top of the viewport.
    var lo = 0, hi = _tops.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_tops[mid] + _layouts[mid].height <= top) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var k = lo; k < _layouts.length && _tops[k] < bottom; k++) {
      canvas.save();
      canvas.translate(0, _tops[k]);
      _paintLine(canvas, k, Size(size.width, _layouts[k].height));
      canvas.restore();
    }
  }

  void _paintLine(Canvas canvas, int k, Size size) {
    if (k >= _layouts.length || k >= _visible.length) return;
    final an = a;
    final line = _visible[k];
    if (line >= an.lineCount) return;
    final lay = _layouts[k];
    final start = an.lineStarts[line];
    final len = an.lines[line].length;
    final dx = lay.indent;
    final sel = c.selection;
    final isCaretLine = k == _caretIndex;

    // Current line highlight across the whole width (hl-line).
    if (isCaretLine && doc.focusNode.hasFocus) {
      canvas.drawRect(Rect.fromLTRB(-_hpad, 0, size.width + _rpad, lay.height), Paint()..color = _theme.hlLine);
    }

    if (widget.settings.lineNumbers) _paintLineNumber(canvas, lay, line, isCaretLine);

    if (sel.isValid && !sel.isCollapsed) {
      final s0 = sel.start - start, s1 = sel.end - start;
      if (s1 >= 0 && s0 <= len) {
        final paint = Paint()..color = _theme.selection;
        final from = s0.clamp(0, len), to = s1.clamp(0, len);
        if (to > from) {
          final boxes = lay.painter.getBoxesForSelection(
            TextSelection(baseOffset: from, extentOffset: to),
            boxHeightStyle: ui.BoxHeightStyle.max,
          );
          for (final b in boxes) {
            canvas.drawRect(b.toRect().shift(Offset(dx, 0)), paint);
          }
        }
        if (s1 > len) {
          final end = _caretIn(lay, len, len);
          final (top, bottom) = _caretLine(lay, len, len);
          canvas.drawRect(Rect.fromLTRB(dx + end.center.dx, top, dx + end.center.dx + 8, bottom), paint);
        }
      }
    }

    lay.painter.paint(canvas, Offset(dx, 0));

    final comp = c.value.composing;
    if (comp.isValid && !comp.isCollapsed) {
      final c0 = comp.start - start, c1 = comp.end - start;
      if (c1 > 0 && c0 < len) {
        final paint = Paint()
          ..color = _theme.text
          ..strokeWidth = 1;
        final boxes = lay.painter.getBoxesForSelection(
          TextSelection(baseOffset: c0.clamp(0, len), extentOffset: c1.clamp(0, len)),
        );
        for (final b in boxes) {
          canvas.drawLine(Offset(dx + b.left, b.bottom - 1), Offset(dx + b.right, b.bottom - 1), paint);
        }
      }
    }

    if (c.hasFoldMarker(line)) {
      // Folded: an org-ellipsis after the text.
      final end = _caretIn(lay, len, len);
      final tp = _gutterPainter('fold', ' \u25BE', _theme.accent);
      final (top, bottom) = _caretLine(lay, len, len);
      final y = ((top + bottom - tp.height) / 2).roundToDouble();
      tp.paint(canvas, Offset((dx + end.center.dx).roundToDouble(), y));
    }

    if (doc.focusNode.hasFocus && _caretOn.value && sel.isValid) {
      final o = sel.extentOffset - start;
      if (o >= 0 && o <= len) {
        canvas.drawRect(_caretIn(lay, o, len).shift(Offset(dx, 0)), Paint()..color = _theme.accent);
      }
    }
  }

  /// Line number right-aligned in the gutter, on the baseline of the line's
  /// first row.
  void _paintLineNumber(Canvas canvas, LineLayout lay, int line, bool current) {
    final tp = _gutterPainter('n${line + 1}|$current', '${line + 1}', current ? _theme.accent : _theme.faint);
    final ms = lay.metrics;
    var y = 0.0;
    if (ms.isNotEmpty) {
      y = ms.first.baseline - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    }
    tp.paint(canvas, Offset(-_gutterGap - tp.width, y.roundToDouble()));
  }

  /// Small painters for the gutter and fold markers, kept between frames.
  TextPainter _gutterPainter(String key, String text, Color color) {
    final cached = _gutterCache[key];
    if (cached != null) return cached;
    if (_gutterCache.length > 4000) _clearGutterCache();
    final tp = TextPainter(
      text: TextSpan(text: text, style: _baseStyle.copyWith(color: color)),
      textDirection: TextDirection.ltr,
      textScaler: _textScaler,
    )..layout();
    _gutterCache[key] = tp;
    return tp;
  }

  void _clearGutterCache() {
    for (final p in _gutterCache.values) {
      p.dispose();
    }
    _gutterCache.clear();
  }

  /// Width of the line number column.
  double _gutterWidth(int lineCount) {
    final digits = math.max<int>(3, '$lineCount'.length);
    final w = _gutterPainter('digit', '0', _theme.faint).width;
    return (digits * w + 12).ceilToDouble();
  }

  // -------------------------------------------------------------------------
  // Applying edits and moving the caret
  // -------------------------------------------------------------------------

  void apply(EditResult? r) {
    if (r == null) return;
    _structural = true;
    c.applyEdit(r);
    _structural = false;
    _goalX = null;
    revealCaret();
  }

  /// Scrolls so the caret is on screen (after the next layout).
  void revealCaret() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !doc.scroll.hasClients) return;
      final sel = c.selection;
      if (!sel.isValid) return;
      final g = _geometry(sel.extentOffset);
      if (g == null) return;
      final pos = doc.scroll.position;
      final top = g.lineTop + _vpad - 12, bottom = g.lineBottom + _vpad + 12;
      var target = pos.pixels;
      if (top < target) {
        target = top;
      } else if (bottom > target + pos.viewportDimension) {
        target = bottom - pos.viewportDimension;
      }
      target = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if ((target - pos.pixels).abs() > 0.5) pos.jumpTo(target);
      _scheduleImeGeometry();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void jumpToLine(int line, {int col = 0}) {
    final an = a;
    if (line < 0 || line >= an.lineCount) return;
    c.revealLine(line);
    final off = an.lineStarts[line] + math.min<int>(col, an.lines[line].length);
    c.selection = TextSelection.collapsed(offset: off);
    doc.focusNode.requestFocus();
    revealCaret();
  }

  void jumpToOffset(int start, int end, {bool focus = true}) {
    c.revealOffset(start);
    c.selection = TextSelection(baseOffset: start, extentOffset: end);
    if (focus) doc.focusNode.requestFocus();
    revealCaret();
  }

  void _insertText(String s) => _replaceSelection(s);

  void _replaceSelection(String s) {
    final sel = c.selection;
    final t = c.text;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    _goalX = null;
    c.value = TextEditingValue(
      text: t.replaceRange(start, end, s),
      selection: TextSelection.collapsed(offset: start + s.length),
    );
    revealCaret();
  }

  void _select(TextSelection s) {
    c.value = c.value.copyWith(selection: s, composing: TextRange.empty);
    revealCaret();
  }

  void _moveTo(int target, bool extend, {bool keepGoal = false, bool? forward}) {
    if (!keepGoal) _goalX = null;
    final len = c.text.length;
    var t = target.clamp(0, len);
    if (forward != null) t = _skipHidden(t, forward);
    final sel = c.selection.isValid ? c.selection : TextSelection.collapsed(offset: t);
    _select(extend ? TextSelection(baseOffset: sel.baseOffset, extentOffset: t) : TextSelection.collapsed(offset: t));
  }

  int _skipHidden(int o, bool forward) {
    final r = c.hiddenCharRange(o);
    if (r == null) return o;
    if (forward && r.$2 < c.text.length) return r.$2;
    return math.max<int>(0, r.$1 - 1);
  }

  static final RegExp _wordChar = RegExp(r'[\p{L}\p{N}_]', unicode: true);
  static bool _isHigh(int u) => u >= 0xD800 && u <= 0xDBFF;
  static bool _isLow(int u) => u >= 0xDC00 && u <= 0xDFFF;

  bool _isWord(String t, int i) => i >= 0 && i < t.length && _wordChar.hasMatch(t[i]);

  int _prevChar(int o) {
    if (o <= 0) return 0;
    final t = c.text;
    if (o >= 2 && _isLow(t.codeUnitAt(o - 1)) && _isHigh(t.codeUnitAt(o - 2))) return o - 2;
    return o - 1;
  }

  int _nextChar(int o) {
    final t = c.text;
    if (o >= t.length) return t.length;
    if (o + 1 < t.length && _isHigh(t.codeUnitAt(o)) && _isLow(t.codeUnitAt(o + 1))) return o + 2;
    return o + 1;
  }

  int _wordLeft(int o) {
    final t = c.text;
    var i = o;
    while (i > 0 && !_isWord(t, i - 1)) {
      i--;
    }
    while (i > 0 && _isWord(t, i - 1)) {
      i--;
    }
    return i;
  }

  int _wordRight(int o) {
    final t = c.text;
    var i = o;
    while (i < t.length && !_isWord(t, i)) {
      i++;
    }
    while (i < t.length && _isWord(t, i)) {
      i++;
    }
    return i;
  }

  TextRange _wordRange(int o) {
    final t = c.text;
    if (t.isEmpty) return const TextRange.collapsed(0);
    var s = o, e = o;
    if (_isWord(t, s) || _isWord(t, s - 1)) {
      while (s > 0 && _isWord(t, s - 1)) {
        s--;
      }
      while (e < t.length && _isWord(t, e)) {
        e++;
      }
    } else if (e < t.length) {
      e++;
    }
    return TextRange(start: s, end: e);
  }

  TextRange _lineRange(int o) {
    final an = a;
    final l = an.lineOfOffset(o);
    final end = l + 1 < an.lineCount ? an.lineStarts[l + 1] : an.text.length;
    return TextRange(start: an.lineStarts[l], end: end);
  }

  void _vertical(int dir, bool extend, {double? distance}) {
    final sel = c.selection;
    if (!sel.isValid) return;
    final g = _geometry(sel.extentOffset);
    if (g == null) return;
    _goalX ??= g.rect.center.dx;
    final y = distance != null
        ? g.rect.center.dy + dir * distance
        : (dir < 0 ? g.lineTop - 1 : g.lineBottom + 1);
    int target;
    if (y < 0) {
      target = 0;
    } else if (y >= _totalHeight) {
      target = c.text.length;
    } else {
      target = _offsetAt(Offset(_goalX!, y));
    }
    _moveTo(target, extend, keepGoal: true);
  }

  void _homeEnd(bool end, bool ctrl, bool extend) {
    if (ctrl) {
      _moveTo(end ? c.text.length : 0, extend);
      return;
    }
    _relayout();
    final an = a;
    final o = caret;
    final line = an.lineOfOffset(o);
    final ls = an.lineStarts[line];
    var s = ls, e = an.lineEnd(line);
    final k = _visibleIndex(line);
    if (k >= 0 && k < _layouts.length) {
      final r = _layouts[k].painter.getLineBoundary(TextPosition(offset: o - ls));
      if (r.isValid) {
        s = ls + r.start;
        e = math.min<int>(ls + r.end, an.lineEnd(line));
      }
    }
    _moveTo(end ? e : s, extend);
  }

  void _deleteBackward(bool word) {
    final sel = c.selection;
    if (!sel.isValid) return;
    if (!sel.isCollapsed) {
      _replaceSelection('');
      return;
    }
    final o = sel.extentOffset;
    if (o <= 0) return;
    final from = word ? _wordLeft(o) : _prevChar(o);
    if (c.isOffsetHidden(from) || c.isOffsetHidden(o - 1)) {
      c.revealOffset(o - 1);
      _message('Unfolded to avoid editing hidden text');
      return;
    }
    _goalX = null;
    c.value = TextEditingValue(text: c.text.replaceRange(from, o, ''), selection: TextSelection.collapsed(offset: from));
    revealCaret();
  }

  void _deleteForward(bool word) {
    final sel = c.selection;
    if (!sel.isValid) return;
    if (!sel.isCollapsed) {
      _replaceSelection('');
      return;
    }
    final o = sel.extentOffset;
    final t = c.text;
    if (o >= t.length) return;
    final to = word ? _wordRight(o) : _nextChar(o);
    if (c.isOffsetHidden(math.min<int>(o + 1, t.length)) || c.isOffsetHidden(math.max<int>(o, to - 1))) {
      c.revealOffset(math.min<int>(o + 1, t.length));
      _message('Unfolded to avoid editing hidden text');
      return;
    }
    _goalX = null;
    c.value = TextEditingValue(text: t.replaceRange(o, to, ''), selection: TextSelection.collapsed(offset: o));
    revealCaret();
  }

  void _newline() {
    // Keep the indentation of the current line.
    final line = a.lines[caretLine];
    final ws = line.substring(0, line.length - line.trimLeft().length);
    final col = caretCol;
    _replaceSelection('\n${col >= ws.length ? ws : ''}');
  }

  Future<void> copySelection() async {
    final s = c.selection;
    if (!s.isValid || s.isCollapsed) return;
    await Clipboard.setData(ClipboardData(text: c.text.substring(s.start, s.end)));
  }

  Future<void> cutSelection() async {
    final s = c.selection;
    if (!s.isValid || s.isCollapsed) return;
    await copySelection();
    _replaceSelection('');
  }

  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) return;
    _replaceSelection(text.replaceAll('\r\n', '\n'));
  }

  void selectAll() => _select(TextSelection(baseOffset: 0, extentOffset: c.text.length));

  void undo() {
    if (_undo.isEmpty) return;
    _restoring = true;
    _redo.add(c.value.copyWith(composing: TextRange.empty));
    c.value = _undo.removeLast();
    _restoring = false;
    _lastEdit = DateTime(0);
    _lastKind = 0;
    revealCaret();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _restoring = true;
    _undo.add(c.value.copyWith(composing: TextRange.empty));
    c.value = _redo.removeLast();
    _restoring = false;
    _lastEdit = DateTime(0);
    _lastKind = 0;
    revealCaret();
  }

  // -------------------------------------------------------------------------
  // Keys
  // -------------------------------------------------------------------------

  static final Set<LogicalKeyboardKey> _modifiers = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.numLock,
    LogicalKeyboardKey.altGraph,
    LogicalKeyboardKey.superKey,
    LogicalKeyboardKey.hyper,
    LogicalKeyboardKey.fn,
  };

  static bool _isArrow(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowLeft ||
      k == LogicalKeyboardKey.arrowRight ||
      k == LogicalKeyboardKey.arrowUp ||
      k == LogicalKeyboardKey.arrowDown;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (_modifiers.contains(k)) return KeyEventResult.ignored;
    final hk = HardwareKeyboard.instance;
    final ctrl = hk.isControlPressed, alt = hk.isAltPressed, shift = hk.isShiftPressed, meta = hk.isMetaPressed;
    final composing = c.value.composing.isValid && !c.value.composing.isCollapsed;
    if (composing && !ctrl && !alt) {
      // Let the input method finish its composition.
      return KeyEventResult.skipRemainingHandlers;
    }
    if (_prefix) {
      if (e is KeyRepeatEvent) return KeyEventResult.handled;
      _setPrefix(false);
      _prefixCommand(e, ctrl);
      return KeyEventResult.handled;
    }
    if (ctrl && !alt && !shift && k == LogicalKeyboardKey.keyC && c.selection.isCollapsed) {
      _setPrefix(true);
      return KeyEventResult.handled;
    }
    var done = false;
    if (k == LogicalKeyboardKey.tab && !ctrl && !alt) {
      done = shift ? _shiftTab() : _tab();
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      done = _enter(ctrl: ctrl, alt: alt, shift: shift);
    } else if (alt && !ctrl && _isArrow(k)) {
      done = _metaArrow(k, shift);
    } else if (shift && !alt && !ctrl && _isArrow(k)) {
      done = _shiftArrow(k);
    } else if (!ctrl && !alt && !shift && k == LogicalKeyboardKey.backspace) {
      done = _guardBackspace();
    } else if (!ctrl && !alt && !shift && k == LogicalKeyboardKey.delete) {
      done = _guardDelete();
    }
    if (!done) done = _editingKey(k, ctrl, alt, shift);
    if (done) {
      _restartBlink();
      return KeyEventResult.handled;
    }
    // Keys that type something go to the text input; function keys and
    // the like can still reach the window's shortcuts.
    if (!ctrl && !alt && !meta && e.character != null) return KeyEventResult.skipRemainingHandlers;
    return KeyEventResult.ignored;
  }

  /// Plain text editing and navigation.
  bool _editingKey(LogicalKeyboardKey k, bool ctrl, bool alt, bool shift) {
    if (alt) return false;
    final sel = c.selection.isValid ? c.selection : TextSelection.collapsed(offset: c.text.length);
    final o = sel.extentOffset;
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (!shift && !ctrl && !sel.isCollapsed) {
        _moveTo(sel.start, false);
      } else {
        _moveTo(ctrl ? _wordLeft(o) : _prevChar(o), shift, forward: false);
      }
      return true;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (!shift && !ctrl && !sel.isCollapsed) {
        _moveTo(sel.end, false);
      } else {
        _moveTo(ctrl ? _wordRight(o) : _nextChar(o), shift, forward: true);
      }
      return true;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      if (ctrl) return false;
      _vertical(k == LogicalKeyboardKey.arrowUp ? -1 : 1, shift);
      return true;
    }
    if (k == LogicalKeyboardKey.home || k == LogicalKeyboardKey.end) {
      _homeEnd(k == LogicalKeyboardKey.end, ctrl, shift);
      return true;
    }
    if (k == LogicalKeyboardKey.pageUp || k == LogicalKeyboardKey.pageDown) {
      final view = doc.scroll.hasClients ? doc.scroll.position.viewportDimension : 400.0;
      _vertical(k == LogicalKeyboardKey.pageUp ? -1 : 1, shift, distance: view * 0.9);
      return true;
    }
    if (k == LogicalKeyboardKey.backspace) {
      _deleteBackward(ctrl);
      return true;
    }
    if (k == LogicalKeyboardKey.delete) {
      _deleteForward(ctrl);
      return true;
    }
    if ((k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) && !ctrl) {
      _newline();
      return true;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (!sel.isCollapsed) _moveTo(o, false);
      return true;
    }
    if (!ctrl) return false;
    if (k == LogicalKeyboardKey.keyA && !shift) {
      selectAll();
      return true;
    }
    if (k == LogicalKeyboardKey.keyC && !shift) {
      copySelection();
      return true;
    }
    if (k == LogicalKeyboardKey.keyX && !shift) {
      cutSelection();
      return true;
    }
    if (k == LogicalKeyboardKey.keyV && !shift) {
      paste();
      return true;
    }
    if (k == LogicalKeyboardKey.keyZ) {
      if (shift) {
        redo();
      } else {
        undo();
      }
      return true;
    }
    if (k == LogicalKeyboardKey.keyY && !shift) {
      redo();
      return true;
    }
    if (k == LogicalKeyboardKey.insert && !shift) {
      copySelection();
      return true;
    }
    return false;
  }

  bool _guardBackspace() {
    final s = c.selection;
    if (!s.isValid || !s.isCollapsed) return false;
    final o = s.extentOffset;
    if (o <= 0) return false;
    if (c.isOffsetHidden(o - 1)) {
      c.revealOffset(o - 1);
      _message('Unfolded to avoid editing hidden text');
      return true;
    }
    return false;
  }

  bool _guardDelete() {
    final s = c.selection;
    if (!s.isValid || !s.isCollapsed) return false;
    final o = s.extentOffset;
    if (o + 1 > c.text.length) return false;
    if (c.isOffsetHidden(math.min<int>(o + 1, c.text.length))) {
      c.revealOffset(o + 1);
      _message('Unfolded to avoid editing hidden text');
      return true;
    }
    return false;
  }

  bool _tab() {
    if (inTable) {
      apply(tableEdit(a, caret, TableOp.nextField));
      return true;
    }
    final info = lineInfo;
    if (info.kind == LineKind.heading) {
      cycleAtCaret();
      return true;
    }
    if (info.kind == LineKind.drawerBegin || info.kind == LineKind.blockBegin) {
      c.toggleRegion(caretLine);
      return true;
    }
    final item = itemAt(a.lines, caretLine);
    if (item != null && a.lines[caretLine].substring(item.contentStart).trim().isEmpty) {
      final r = shiftItem(a, caret, 1, subtree: true);
      if (r != null && r.message != null) {
        apply(shiftItem(a, caret, -1, subtree: true));
      } else {
        apply(r);
      }
      return true;
    }
    _insertText('  ');
    return true;
  }

  bool _shiftTab() {
    if (inTable) {
      apply(tableEdit(a, caret, TableOp.previousField));
      return true;
    }
    c.cycleGlobal();
    revealCaret();
    return true;
  }

  bool _enter({required bool ctrl, required bool alt, required bool shift}) {
    final item = onHeading ? null : owningItem(a.lines, caretLine);
    if (alt && shift && !ctrl) {
      apply(item != null ? insertItem(a, caret, checkbox: true) : insertHeading(a, caret, todo: true));
      return true;
    }
    if (alt && !ctrl) {
      if (inTable) {
        apply(tableEdit(a, caret, TableOp.insertRowBelow));
      } else if (item != null) {
        apply(insertItem(a, caret));
      } else {
        apply(insertHeading(a, caret, folded: c.folds.contains(caretLine)));
      }
      return true;
    }
    if (ctrl && !alt) {
      apply(insertHeading(a, caret, todo: shift, respectContent: true));
      return true;
    }
    if (!ctrl && !alt && !shift && inTable && c.selection.isCollapsed && caretCol < a.lines[caretLine].length) {
      apply(tableEdit(a, caret, TableOp.nextRow));
      return true;
    }
    return false;
  }

  bool _metaArrow(LogicalKeyboardKey k, bool shift) {
    final left = k == LogicalKeyboardKey.arrowLeft;
    final right = k == LogicalKeyboardKey.arrowRight;
    final up = k == LogicalKeyboardKey.arrowUp;
    if (inTable) {
      final TableOp op;
      if (shift) {
        op = left
            ? TableOp.deleteColumn
            : right
                ? TableOp.insertColumn
                : up
                    ? TableOp.deleteRow
                    : TableOp.insertRowAbove;
      } else {
        op = left
            ? TableOp.moveColumnLeft
            : right
                ? TableOp.moveColumnRight
                : up
                    ? TableOp.moveRowUp
                    : TableOp.moveRowDown;
      }
      apply(tableEdit(a, caret, op));
      return true;
    }
    if (!onHeading) {
      final item = owningItem(a.lines, caretLine);
      if (item != null) {
        if (left || right) {
          apply(shiftItem(a, caret, right ? 1 : -1, subtree: shift));
        } else {
          apply(moveItem(a, caret, up: up));
        }
        return true;
      }
    }
    if (onHeading) {
      if (left || right) {
        apply(changeHeadingLevel(a, caret, right ? 1 : -1, subtree: shift));
      } else {
        apply(moveSubtree(a, caret, up: up));
      }
      return true;
    }
    if (up || k == LogicalKeyboardKey.arrowDown) {
      _dragLine(up);
      return true;
    }
    return false;
  }

  void _dragLine(bool up) {
    final l = caretLine;
    final other = up ? l - 1 : l + 1;
    if (other < 0 || other >= a.lineCount) return;
    final lines = [...a.lines];
    final tmp = lines[l];
    lines[l] = lines[other];
    lines[other] = tmp;
    final d = Doc(lines, other, caretCol);
    apply(d.result());
  }

  bool _shiftArrow(LogicalKeyboardKey k) {
    if (!c.selection.isCollapsed) return false;
    final left = k == LogicalKeyboardKey.arrowLeft;
    final right = k == LogicalKeyboardKey.arrowRight;
    final up = k == LogicalKeyboardKey.arrowUp;
    final line = a.lines[caretLine];
    final col = caretCol;
    if (timestampAt(line, col) != null) {
      if (left || right) {
        apply(shiftTimestampAt(a, caret, days: right ? 1 : -1));
      } else {
        apply(shiftTimestampAt(a, caret, fieldDelta: up ? 1 : -1));
      }
      return true;
    }
    final h = a.headingInfo(caretLine);
    if (h != null && col >= 1 && col <= h.prefixEnd) {
      if (left || right) {
        apply(cycleTodo(a, caret, backward: left));
      } else {
        apply(shiftPriority(a, caret, up));
      }
      return true;
    }
    final item = itemAt(a.lines, caretLine);
    if (item != null && (left || right) && col > item.bulletStart && col <= item.bulletEnd) {
      apply(cycleBullet(a, caret, backward: left));
      return true;
    }
    return false;
  }


  void _prefixCommand(KeyEvent e, bool ctrl) {
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape || (ctrl && k == LogicalKeyboardKey.keyG)) {
      _message('Quit');
      return;
    }
    var ch = e.character ?? '';
    if (ch.isEmpty || ch.codeUnitAt(0) < 32) ch = k.keyLabel.toLowerCase();
    if (ch.length == 1 && RegExp(r'[A-Z]').hasMatch(ch) && !ctrl) ch = ch.toLowerCase();
    runPrefixCommand(ch);
  }

  /// Runs the command bound to `C-c <ch>`.
  void runPrefixCommand(String ch) {
    switch (ch) {
      case 'c':
        ctrlCctrlC();
      case 't':
        apply(cycleTodo(a, caret));
      case 's':
        schedule('SCHEDULED');
      case 'd':
        schedule('DEADLINE');
      case '.':
        insertTimestampDialog(active: true);
      case '!':
        insertTimestampDialog(active: false);
      case ',':
        priorityDialog();
      case 'q':
        tagsDialog();
      case 'l':
        linkDialog();
      case 'o':
        openLinkAtPoint();
      case '*':
        apply(toggleHeading(a, caret));
      case '-':
        if (inTable) {
          apply(tableEdit(a, caret, TableOp.insertHline));
        } else {
          apply(cycleBullet(a, caret));
        }
      case '|':
        apply(createTable(a, caret));
      case '#':
        apply(updateStatistics(a, caret));
      case 'n':
        nextHeading(forward: true);
      case 'p':
        nextHeading(forward: false);
      case 'f':
        siblingHeading(forward: true);
      case 'b':
        siblingHeading(forward: false);
      case 'u':
        parentHeading();
      case 'a':
        widget.host.openAgenda();
      case 'x':
        apply(toggleCheckboxPresence(a, caret));
      default:
        _message('C-c $ch is undefined');
    }
  }

  // -------------------------------------------------------------------------
  // Commands (also used by menus and the toolbar)
  // -------------------------------------------------------------------------

  /// Runs a named command; used by the menu bar and the toolbar.
  void runCommand(String id) {
    if (c.selection.isValid == false) {
      c.selection = const TextSelection.collapsed(offset: 0);
    }
    switch (id) {
      case 'cycle':
        if (inTable) {
          apply(tableEdit(a, caret, TableOp.align));
        } else {
          cycleAtCaret();
        }
      case 'globalCycle':
        c.cycleGlobal();
      case 'overview':
        c.setGlobal(GlobalVisibility.overview);
      case 'contents':
        c.setGlobal(GlobalVisibility.contents);
      case 'showAll':
        c.unfoldAll();
      case 'todo':
        apply(cycleTodo(a, caret));
      case 'todoBack':
        apply(cycleTodo(a, caret, backward: true));
      case 'priorityUp':
        apply(shiftPriority(a, caret, true));
      case 'priorityDown':
        apply(shiftPriority(a, caret, false));
      case 'priority':
        priorityDialog();
      case 'tags':
        tagsDialog();
      case 'schedule':
        schedule('SCHEDULED');
      case 'deadline':
        schedule('DEADLINE');
      case 'timestamp':
        insertTimestampDialog(active: true);
      case 'inactiveTimestamp':
        insertTimestampDialog(active: false);
      case 'link':
        linkDialog();
      case 'openLink':
        openLinkAtPoint();
      case 'checkbox':
        final r = toggleCheckbox(a, caret);
        if (r == null) {
          apply(toggleCheckboxPresence(a, caret));
        } else {
          apply(r);
        }
      case 'checkboxPresence':
        apply(toggleCheckboxPresence(a, caret));
      case 'insertHeading':
        _enter(ctrl: false, alt: true, shift: false);
      case 'insertTodoHeading':
        apply(insertHeading(a, caret, todo: true));
      case 'insertHeadingAfter':
        apply(insertHeading(a, caret, respectContent: true));
      case 'insertItem':
        final r = insertItem(a, caret);
        if (r == null) {
          final line = a.lines[caretLine];
          final prefix = line.trim().isEmpty ? '- ' : '\n- ';
          final end = a.lineEnd(caretLine);
          c.selection = TextSelection.collapsed(offset: end);
          _insertText(prefix);
        } else {
          apply(r);
        }
      case 'promote':
        _metaArrow(LogicalKeyboardKey.arrowLeft, false);
      case 'demote':
        _metaArrow(LogicalKeyboardKey.arrowRight, false);
      case 'promoteTree':
        _metaArrow(LogicalKeyboardKey.arrowLeft, true);
      case 'demoteTree':
        _metaArrow(LogicalKeyboardKey.arrowRight, true);
      case 'moveUp':
        _metaArrow(LogicalKeyboardKey.arrowUp, false);
      case 'moveDown':
        _metaArrow(LogicalKeyboardKey.arrowDown, false);
      case 'toggleHeading':
        apply(toggleHeading(a, caret));
      case 'table':
        apply(inTable ? tableEdit(a, caret, TableOp.align) : createTable(a, caret));
      case 'tableHline':
        apply(tableEdit(a, caret, TableOp.insertHline));
      case 'statistics':
        apply(updateStatistics(a, caret));
      case 'ctrlCctrlC':
        ctrlCctrlC();
      case 'nextHeading':
        nextHeading(forward: true);
      case 'prevHeading':
        nextHeading(forward: false);
      case 'parentHeading':
        parentHeading();
      case 'agenda':
        widget.host.openAgenda();
    }
    doc.focusNode.requestFocus();
  }

  void cycleAtCaret() {
    final line = caretLine;
    final info = a.infos[line];
    if (info.kind == LineKind.heading) {
      c.cycleHeading(line);
    } else if (info.kind == LineKind.drawerBegin || info.kind == LineKind.blockBegin) {
      c.toggleRegion(line);
    } else {
      final h = a.headingAtOrAbove(line);
      if (h != null) c.cycleHeading(h);
    }
    revealCaret();
  }

  void ctrlCctrlC() {
    if (inTable) {
      apply(tableEdit(a, caret, TableOp.align));
      return;
    }
    final line = a.lines[caretLine];
    final item = owningItem(a.lines, caretLine);
    if (item != null && item.checkbox != null) {
      apply(toggleCheckbox(a, caret));
      return;
    }
    if (cookieRe.hasMatch(line)) {
      apply(updateStatistics(a, caret));
      return;
    }
    if (timestampAt(line, caretCol) != null) {
      apply(shiftTimestampAt(a, caret, fieldDelta: 0));
      return;
    }
    if (onHeading) {
      tagsDialog();
      return;
    }
    if (lineInfo.kind == LineKind.keyword) {
      c.refresh();
      _message('Local setup has been refreshed');
      return;
    }
    _message('C-c C-c can do nothing useful here');
  }

  Future<void> schedule(String key) async {
    final h = a.headingAtOrAbove(caretLine);
    if (h == null) {
      _message('Not in an entry');
      return;
    }
    OrgTimestamp? initial;
    final pl = a.planningLine(h);
    if (pl != null) {
      final m = RegExp('$key:[ \\t]*(<[^>]*>)').firstMatch(a.lines[pl]);
      if (m != null) initial = OrgTimestamp.parse(m.group(1)!);
    }
    final pos = caret;
    final r = await showTimestampDialog(
      context,
      title: key == 'SCHEDULED' ? 'Schedule' : 'Deadline',
      initial: initial,
      allowRemove: initial != null,
    );
    if (r == null || !mounted) return;
    apply(setPlanning(c.analysis, pos.clamp(0, c.text.length), key, r.timestamp));
    doc.focusNode.requestFocus();
  }

  Future<void> insertTimestampDialog({required bool active}) async {
    final line = a.lines[caretLine];
    final existing = timestampAt(line, caretCol);
    final pos = caret;
    final r = await showTimestampDialog(
      context,
      title: active ? 'Timestamp' : 'Inactive timestamp',
      initial: existing?.$2,
      active: active,
    );
    if (r == null || r.timestamp == null || !mounted) return;
    apply(insertTimestamp(c.analysis, pos.clamp(0, c.text.length), r.timestamp!));
    doc.focusNode.requestFocus();
  }

  Future<void> priorityDialog() async {
    final h = a.headingAtOrAbove(caretLine);
    if (h == null) {
      _message('Not in an entry');
      return;
    }
    final pos = caret;
    final p = await showPriorityDialog(context, a.priorities.all);
    if (p == null || !mounted) return;
    apply(setPriority(c.analysis, pos.clamp(0, c.text.length), p.isEmpty ? null : p));
    doc.focusNode.requestFocus();
  }

  Future<void> tagsDialog() async {
    final h = a.headingAtOrAbove(caretLine);
    if (h == null) {
      _message('Not in an entry');
      return;
    }
    final known = <String>{};
    for (final x in a.headingLines) {
      known.addAll(a.headingInfo(x)!.tags);
    }
    final tagsKw = a.keywords['TAGS'] ?? a.keywords['FILETAGS'];
    if (tagsKw != null) {
      known.addAll(tagsKw.split(RegExp(r'[\s:{}]+')).where((t) => t.isNotEmpty && !t.contains('(')));
    }
    final pos = caret;
    final tags = await showTagsDialog(context, a.headingInfo(h)!.tags, known.toList()..sort());
    if (tags == null || !mounted) return;
    apply(setTags(c.analysis, pos.clamp(0, c.text.length), tags));
    doc.focusNode.requestFocus();
  }

  Future<void> linkDialog() async {
    final line = a.lines[caretLine];
    final existing = linkAt(line, caretCol);
    final sel = c.selection;
    String desc = existing?.description ?? '';
    if (existing == null && sel.isValid && !sel.isCollapsed) {
      desc = c.text.substring(sel.start, sel.end);
      if (desc.contains('\n')) desc = '';
    }
    final pos = caret;
    final selStart = sel.isValid ? sel.start : null, selEnd = sel.isValid ? sel.end : null;
    final r = await showLinkDialog(context, target: existing?.target ?? '', description: desc);
    if (r == null || !mounted) return;
    apply(insertLink(c.analysis, pos.clamp(0, c.text.length), r.target, r.description,
        selStart: selStart, selEnd: selEnd));
    doc.focusNode.requestFocus();
  }

  void openLinkAtPoint({bool silent = false}) {
    final line = a.lines[caretLine];
    final link = linkAt(line, caretCol);
    if (link == null) {
      if (!silent) _message('No link at point');
      return;
    }
    widget.host.openLink(link.target, doc);
  }

  void nextHeading({required bool forward}) {
    final l = caretLine;
    final hs = a.headingLines;
    if (forward) {
      for (final h in hs) {
        if (h > l && !c.isLineHidden(h)) return jumpToLine(h);
      }
    } else {
      for (final h in hs.reversed) {
        if (h < l && !c.isLineHidden(h)) return jumpToLine(h);
      }
    }
    _message('No more headings');
  }

  void siblingHeading({required bool forward}) {
    final h = a.headingAtOrAbove(caretLine);
    if (h == null) return;
    final t = forward ? a.nextSibling(h) : a.previousSibling(h);
    if (t == null) {
      _message('No more siblings');
      return;
    }
    jumpToLine(t);
  }

  void parentHeading() {
    final h = a.headingAtOrAbove(caretLine);
    if (h == null) return;
    final p = h == caretLine ? a.parentHeading(h) : h;
    if (p == null) {
      _message('Already at top level');
      return;
    }
    jumpToLine(p);
  }

  /// Search helpers for the find bar.
  bool find(String query,
      {required bool forward, bool caseSensitive = false, bool fromSelectionStart = false, bool focus = true}) {
    if (query.isEmpty) return false;
    final text = caseSensitive ? c.text : c.text.toLowerCase();
    final q = caseSensitive ? query : query.toLowerCase();
    final sel = c.selection;
    int idx;
    if (forward) {
      final from = sel.isValid ? (fromSelectionStart ? sel.start : sel.end) : 0;
      idx = text.indexOf(q, from.clamp(0, text.length));
      if (idx < 0) idx = text.indexOf(q);
    } else {
      final from = sel.isValid ? sel.start - 1 : text.length;
      idx = from < 0 ? -1 : text.lastIndexOf(q, from);
      if (idx < 0) idx = text.lastIndexOf(q);
    }
    if (idx < 0) return false;
    jumpToOffset(idx, idx + q.length, focus: focus);
    return true;
  }

  int countMatches(String query, {bool caseSensitive = false}) {
    if (query.isEmpty) return 0;
    final text = caseSensitive ? c.text : c.text.toLowerCase();
    final q = caseSensitive ? query : query.toLowerCase();
    var n = 0, i = 0;
    while (true) {
      i = text.indexOf(q, i);
      if (i < 0) break;
      n++;
      i += q.length;
    }
    return n;
  }

  bool replaceCurrent(String query, String replacement, {bool caseSensitive = false}) {
    final sel = c.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final current = c.text.substring(sel.start, sel.end);
      final matches = caseSensitive ? current == query : current.toLowerCase() == query.toLowerCase();
      if (matches) {
        final t = c.text.replaceRange(sel.start, sel.end, replacement);
        c.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: sel.start + replacement.length));
      }
    }
    return find(query, forward: true, caseSensitive: caseSensitive, focus: false);
  }

  int replaceAll(String query, String replacement, {bool caseSensitive = false}) {
    if (query.isEmpty) return 0;
    final text = c.text;
    final re = RegExp(RegExp.escape(query), caseSensitive: caseSensitive);
    var n = 0;
    final out = text.replaceAllMapped(re, (m) {
      n++;
      return replacement;
    });
    if (n > 0) {
      c.value = TextEditingValue(text: out, selection: TextSelection.collapsed(offset: math.min<int>(caret, out.length)));
    }
    return n;
  }

  // -------------------------------------------------------------------------
  // Pointer
  // -------------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus) {
      _touchDown = e.localPosition;
      return;
    }
    if ((e.buttons & kSecondaryMouseButton) != 0) {
      _contextMenu(e.position, e.localPosition);
      return;
    }
    if ((e.buttons & kPrimaryMouseButton) == 0) return;
    doc.focusNode.requestFocus();
    final o = _offsetAt(_toContent(e.localPosition));
    final now = DateTime.now();
    if (now.difference(_lastClick) < const Duration(milliseconds: 400) &&
        (e.localPosition - _lastClickPos).distance < 6) {
      _clicks = _clicks % 3 + 1;
    } else {
      _clicks = 1;
    }
    _lastClick = now;
    _lastClickPos = e.localPosition;
    _goalX = null;
    if (HardwareKeyboard.instance.isShiftPressed && c.selection.isValid) {
      _dragMode = 1;
      _dragBase = c.selection.baseOffset;
      _select(TextSelection(baseOffset: _dragBase, extentOffset: o));
    } else if (_clicks == 2) {
      final r = _wordRange(o);
      _dragMode = 2;
      _dragUnit = r;
      _select(TextSelection(baseOffset: r.start, extentOffset: r.end));
    } else if (_clicks == 3) {
      final r = _lineRange(o);
      _dragMode = 3;
      _dragUnit = r;
      _select(TextSelection(baseOffset: r.start, extentOffset: r.end));
    } else {
      _dragMode = 1;
      _dragBase = o;
      _select(TextSelection.collapsed(offset: o));
    }
    _dragging = true;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_dragging) return;
    if ((e.buttons & kPrimaryMouseButton) == 0) {
      _dragging = false;
      return;
    }
    final box = _viewportKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize && doc.scroll.hasClients) {
      final pos = doc.scroll.position;
      if (e.localPosition.dy < 24) {
        pos.jumpTo(math.max<double>(pos.minScrollExtent, pos.pixels - 18));
      } else if (e.localPosition.dy > box.size.height - 24) {
        pos.jumpTo(math.min<double>(pos.maxScrollExtent, pos.pixels + 18));
      }
    }
    final o = _offsetAt(_toContent(e.localPosition));
    TextSelection next;
    if (_dragMode == 1) {
      next = TextSelection(baseOffset: _dragBase, extentOffset: o);
    } else {
      final r = _dragMode == 2 ? _wordRange(o) : _lineRange(o);
      next = o < _dragUnit.start
          ? TextSelection(baseOffset: _dragUnit.end, extentOffset: r.start)
          : TextSelection(baseOffset: _dragUnit.start, extentOffset: math.max<int>(r.end, _dragUnit.end));
    }
    if (next != c.selection) c.value = c.value.copyWith(selection: next, composing: TextRange.empty);
  }

  void _onPointerUp(PointerUpEvent e) {
    final touch = _touchDown;
    if (touch != null) {
      _touchDown = null;
      if ((e.localPosition - touch).distance < 12) {
        doc.focusNode.requestFocus();
        _select(TextSelection.collapsed(offset: _offsetAt(_toContent(e.localPosition))));
        _connection?.show();
      }
      return;
    }
    _dragging = false;
    if (_clicks == 1 && HardwareKeyboard.instance.isControlPressed) openLinkAtPoint(silent: true);
  }

  Future<void> _contextMenu(Offset global, Offset local) async {
    doc.focusNode.requestFocus();
    final o = _offsetAt(_toContent(local));
    final sel = c.selection;
    if (!sel.isValid || sel.isCollapsed || o < sel.start || o > sel.end) {
      _select(TextSelection.collapsed(offset: o));
    }
    final hasSel = c.selection.isValid && !c.selection.isCollapsed;
    final link = linkAt(a.lines[caretLine], caretCol);
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(global & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        if (link != null) const PopupMenuItem(value: 'open', child: Text('Open link')),
        PopupMenuItem(value: 'cut', enabled: hasSel, child: const Text('Cut')),
        PopupMenuItem(value: 'copy', enabled: hasSel, child: const Text('Copy')),
        const PopupMenuItem(value: 'paste', child: Text('Paste')),
        const PopupMenuItem(value: 'all', child: Text('Select all')),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'open':
        openLinkAtPoint();
      case 'cut':
        await cutSelection();
      case 'copy':
        await copySelection();
      case 'paste':
        await paste();
      case 'all':
        selectAll();
    }
    doc.focusNode.requestFocus();
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    _theme = s.orgTheme;
    _textScaler = MediaQuery.textScalerOf(context);
    _baseStyle = TextStyle(
      fontSize: s.fontSize,
      height: _snappedLineHeight(s.fontSize, s.lineHeight),
      // Line spacing goes equally above and below the text, so the text and
      // the caret sit in the middle of each line.
      leadingDistribution: TextLeadingDistribution.even,
      color: _theme.text,
      fontFamily: s.fontFamily,
    );
    final hl = c.highlighter;
    final sig = '${s.fontFamily}|${s.codeFontFamily}|${s.fontSize}|${s.lineHeight}|${identityHashCode(_theme)}|'
        '${hl.superstar}|${hl.hideMarkup}|${hl.scaleHeadings}|${s.indentBody}|${_textScaler.scale(16)}';
    if (sig != _styleSig) {
      _styleSig = sig;
      _prefixWidths.clear();
      _clearGutterCache();
      _caretRatio = _measureCaretRatio();
    }
    if (doc.focusNode.hasFocus) _scheduleImeGeometry();
    return Focus(
      focusNode: doc.focusNode,
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, constraints) {
        // Whole pixels everywhere, so a pixel font stays on the pixel grid.
        final w = constraints.maxWidth;
        final left = s.lineNumbers ? _gutterWidth(c.analysis.lineCount) + _gutterGap : 20.0;
        if (s.centerText) {
          _hpad = math.max<double>(left, (w - s.maxWidth) / 2).roundToDouble();
          _textWidth = math.max<double>(60.0, w - 2 * _hpad).floorToDouble();
        } else {
          _hpad = left;
          _textWidth = math.max<double>(60.0, math.min<double>(s.maxWidth, w - left - 20)).floorToDouble();
        }
        _rpad = math.max<double>(0.0, w - _hpad - _textWidth);
        _viewportHeight = constraints.maxHeight;
        _relayout();
        return ColoredBox(
          color: _theme.background,
          child: Listener(
            key: _viewportKey,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            child: MouseRegion(
              cursor: SystemMouseCursors.text,
              child: SingleChildScrollView(
                controller: doc.scroll,
                padding: EdgeInsets.fromLTRB(_hpad, _vpad, _rpad, math.max<double>(_vpad, constraints.maxHeight / 3).roundToDouble()),
                child: CustomPaint(size: Size(_textWidth, _totalHeight), painter: _DocPainter(this)),
              ),
            ),
          ),
        );
      }),
    );
  }
}
