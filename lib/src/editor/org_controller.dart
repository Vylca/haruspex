import 'package:flutter/material.dart';

import '../org/analysis.dart';
import '../org/edits.dart';
import 'highlighter.dart';

enum GlobalVisibility { overview, contents, showAll }

/// Text controller that owns the Org analysis, fold state and highlighting.
///
/// Folded text stays in the buffer; it is rendered with a near-zero font size
/// and the caret is kept out of it.
class OrgController extends TextEditingController {
  OrgController({super.text, required this.highlighter});

  final OrgHighlighter highlighter;

  OrgAnalysis? _analysis;

  /// Folded heading, drawer and block lines.
  Set<int> folds = {};

  /// Headings whose own body text is hidden but child headings are shown.
  Set<int> bodyFolds = {};

  GlobalVisibility globalVisibility = GlobalVisibility.showAll;

  int _foldVersion = 0;
  List<(int, int)>? _hidden;
  OrgAnalysis? _hiddenFor;
  int _hiddenVersion = -1;

  Map<int, int>? _pendingLineMap;

  /// Called with short status messages ("SUBTREE", "Entry repeats", ...).
  void Function(String message)? onMessage;

  OrgAnalysis get analysis => _analysisFor(text);

  OrgAnalysis _analysisFor(String t) {
    final a = _analysis;
    if (a != null && (identical(a.text, t) || a.text == t)) return a;
    final OrgAnalysis n;
    if (a == null) {
      n = OrgAnalysis(t);
    } else {
      final d = _diff;
      n = OrgAnalysis.update(a, t, d != null && identical(d.$1, a) && identical(d.$2, t) ? d.$3 : null);
    }
    _diff = null;
    _analysis = n;
    return n;
  }

  /// The line diff of the last edit, kept for the next analysis.
  (OrgAnalysis, String, LineDiff)? _diff;

  // -------------------------------------------------------------------------
  // Value changes: keep folds attached to their lines, keep the caret visible.
  // -------------------------------------------------------------------------

  @override
  set value(TextEditingValue newValue) {
    final old = super.value;
    final textChanged = newValue.text != old.text;
    if (textChanged) {
      _shiftFolds(old.text, newValue.text, _pendingLineMap);
      _pendingLineMap = null;
    }
    super.value = _adjustSelection(old, newValue, textChanged);
  }

  /// Applies a structural edit, carrying folds through block moves.
  void applyEdit(EditResult r) {
    _pendingLineMap = r.lineMap;
    final len = r.text.length;
    final b = r.selection.base.clamp(0, len);
    final e = r.selection.extent.clamp(0, len);
    value = TextEditingValue(
      text: r.text,
      selection: TextSelection(baseOffset: b, extentOffset: e),
    );
    _pendingLineMap = null;
    if (r.message != null) onMessage?.call(r.message!);
  }

  /// Moves fold markers along with the lines they belong to. Uses a
  /// line-level diff (common prefix and suffix lines); lines inside the
  /// changed region keep their position when the line count is unchanged.
  void _shiftFolds(String oldText, String newText, Map<int, int>? lineMap) {
    if (folds.isEmpty && bodyFolds.isEmpty) return;
    _foldVersion++;
    final map = lineMap;
    if (map != null) {
      Set<int> remap(Set<int> s) => {for (final f in s) map[f] ?? f};
      folds = remap(folds);
      bodyFolds = remap(bodyFolds);
      return;
    }
    final a = _analysis;
    final int pre, oldMidEnd, oldMid, newMid, delta;
    if (a != null && (identical(a.text, oldText) || a.text == oldText)) {
      // Same diff the next analysis needs; computed once.
      final d = LineDiff.between(a, newText);
      _diff = (a, newText, d);
      pre = d.start;
      oldMidEnd = d.oldEnd;
      oldMid = d.oldEnd - d.start;
      newMid = d.newLines.length;
      delta = d.newEnd - d.oldEnd;
    } else {
      final oldLines = oldText.split('\n');
      final newLines = newText.split('\n');
      final minN = oldLines.length < newLines.length ? oldLines.length : newLines.length;
      var p = 0;
      while (p < minN && oldLines[p] == newLines[p]) {
        p++;
      }
      var suf = 0;
      while (suf < minN - p && oldLines[oldLines.length - 1 - suf] == newLines[newLines.length - 1 - suf]) {
        suf++;
      }
      pre = p;
      oldMidEnd = oldLines.length - suf;
      oldMid = oldMidEnd - pre;
      newMid = newLines.length - suf - pre;
      delta = newLines.length - oldLines.length;
    }

    int? shift(int f) {
      if (f < pre) return f;
      if (f >= oldMidEnd) return f + delta;
      if (oldMid == newMid) return f;
      final k = f - pre;
      return k < newMid ? pre + k : null;
    }

    Set<int> apply(Set<int> set) {
      final out = <int>{};
      for (final f in set) {
        final n = shift(f);
        if (n != null) out.add(n);
      }
      return out;
    }

    folds = apply(folds);
    bodyFolds = apply(bodyFolds);
  }

  TextEditingValue _adjustSelection(TextEditingValue old, TextEditingValue nv, bool textChanged) {
    final sel = nv.selection;
    if (!sel.isValid || !sel.isCollapsed) return nv;
    if (folds.isEmpty && bodyFolds.isEmpty) return nv;
    final a = _analysisFor(nv.text);
    final o = sel.extentOffset;
    final range = _hiddenCharRangeAt(a, o);
    if (range == null) return nv;
    if (textChanged) {
      revealLine(a.lineOfOffset(o), notify: false, a: a);
      return nv;
    }
    final oldOff = old.selection.isValid ? old.selection.extentOffset : o;
    final (start, end) = range;
    // Hidden text shares a visual line with the next visible line, so most
    // moves (Right, Down, Home, clicks) belong at its start. Only a single
    // step back (Left) goes to the end of the folded line above.
    final stepBack = o < oldOff && oldOff - o == 1;
    int target;
    if (!stepBack && end < nv.text.length) {
      target = end;
    } else {
      target = start - 1;
    }
    if (target < 0) target = 0;
    return nv.copyWith(selection: TextSelection.collapsed(offset: target));
  }

  /// Character range [start, end) of the hidden region containing [offset].
  (int, int)? _hiddenCharRangeAt(OrgAnalysis a, int offset) {
    final hidden = _hiddenLinesFor(a);
    if (hidden.isEmpty) return null;
    final line = a.lineOfOffset(offset);
    for (final (s, e) in hidden) {
      if (line >= s && line < e) {
        final start = a.lineStarts[s];
        final end = e < a.lineCount ? a.lineStarts[e] : a.text.length;
        return (start, end);
      }
    }
    return null;
  }

  bool isOffsetHidden(int offset) => _hiddenCharRangeAt(analysis, offset) != null;

  /// Character range [start, end) of the folded region containing [offset].
  (int, int)? hiddenCharRange(int offset) => _hiddenCharRangeAt(analysis, offset);

  bool isLineHidden(int line) {
    for (final (s, e) in hiddenLines) {
      if (line >= s && line < e) return true;
      if (s > line) break;
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Hidden regions
  // -------------------------------------------------------------------------

  List<(int, int)> get hiddenLines => _hiddenLinesFor(analysis);

  List<(int, int)> _hiddenLinesFor(OrgAnalysis a) {
    if (_hidden != null && identical(_hiddenFor, a) && _hiddenVersion == _foldVersion) return _hidden!;
    _validateFolds(a);
    final spans = <(int, int)>[];
    for (final f in folds) {
      final kind = a.infos[f].kind;
      if (kind == LineKind.heading) {
        final end = a.subtreeEnd(f);
        if (end > f + 1) spans.add((f + 1, end));
      } else {
        final e = a.regionEnd[f];
        if (e != null) spans.add((f + 1, e + 1));
      }
    }
    for (final b in bodyFolds) {
      final end = a.bodyEnd(b);
      if (end > b + 1) spans.add((b + 1, end));
    }
    spans.sort((x, y) => x.$1.compareTo(y.$1));
    final merged = <(int, int)>[];
    for (final sp in spans) {
      if (merged.isNotEmpty && sp.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, sp.$2 > last.$2 ? sp.$2 : last.$2));
      } else {
        merged.add(sp);
      }
    }
    _hidden = merged;
    _hiddenFor = a;
    _hiddenVersion = _foldVersion;
    return merged;
  }

  void _validateFolds(OrgAnalysis a) {
    folds.removeWhere((f) {
      if (f < 0 || f >= a.lineCount) return true;
      final k = a.infos[f].kind;
      if (k == LineKind.heading) return false;
      if ((k == LineKind.drawerBegin || k == LineKind.blockBegin) && a.regionEnd.containsKey(f)) return false;
      return true;
    });
    bodyFolds.removeWhere((f) => !a.isHeading(f));
  }

  /// Character ranges of lines that end in a fold marker ("…").
  List<(int, int)> foldMarkerRanges() {
    final a = analysis;
    final hidden = hiddenLines;
    final result = <(int, int)>[];
    bool hiddenLine(int l) {
      for (final (s, e) in hidden) {
        if (l >= s && l < e) return true;
      }
      return false;
    }

    void consider(int f, int hiddenEnd) {
      if (hiddenEnd <= f + 1 || hiddenLine(f)) return;
      result.add((a.lineStart(f), a.lineEnd(f)));
    }

    for (final f in folds) {
      if (f >= a.lineCount) continue;
      if (a.infos[f].kind == LineKind.heading) {
        consider(f, a.subtreeEnd(f));
      } else {
        final e = a.regionEnd[f];
        if (e != null) consider(f, e + 1);
      }
    }
    for (final b in bodyFolds) {
      if (b >= a.lineCount || folds.contains(b)) continue;
      consider(b, a.bodyEnd(b));
    }
    return result;
  }

  // -------------------------------------------------------------------------
  // Fold commands
  // -------------------------------------------------------------------------

  void _changed() {
    _foldVersion++;
    notifyListeners();
  }

  /// Forces re-analysis and a repaint (e.g. after settings changed).
  void refresh() {
    _analysis = null;
    highlighter.clearCache();
    _changed();
  }

  /// Org TAB on a heading: FOLDED -> CHILDREN -> SUBTREE -> FOLDED.
  void cycleHeading(int h) {
    final a = analysis;
    if (!a.isHeading(h)) return;
    final end = a.subtreeEnd(h);
    if (end <= h + 1) {
      onMessage?.call('EMPTY ENTRY');
      return;
    }
    final children = a.childHeadings(h);
    final inside = a.headingsIn(h + 1, end);
    if (folds.contains(h)) {
      folds.remove(h);
      bodyFolds.remove(h);
      if (children.isEmpty) {
        onMessage?.call('SUBTREE');
      } else {
        for (final c in children) {
          folds.add(c);
          bodyFolds.remove(c);
        }
        onMessage?.call('CHILDREN');
      }
    } else if (bodyFolds.contains(h) || inside.any((x) => folds.contains(x) || bodyFolds.contains(x))) {
      bodyFolds.remove(h);
      for (final x in inside) {
        folds.remove(x);
        bodyFolds.remove(x);
      }
      onMessage?.call('SUBTREE');
    } else {
      folds.add(h);
      onMessage?.call('FOLDED');
    }
    _changed();
  }

  void toggleRegion(int line) {
    final a = analysis;
    final k = a.infos[line].kind;
    if (k != LineKind.drawerBegin && k != LineKind.blockBegin) return;
    if (!folds.remove(line)) folds.add(line);
    _changed();
  }

  void setGlobal(GlobalVisibility v, {bool notify = true}) {
    final a = analysis;
    final regions = folds.where((f) => f < a.lineCount && !a.isHeading(f)).toSet();
    globalVisibility = v;
    switch (v) {
      case GlobalVisibility.overview:
        folds = {...regions, ...a.headingLines};
        bodyFolds = {};
        onMessage?.call('OVERVIEW');
      case GlobalVisibility.contents:
        folds = regions;
        bodyFolds = {...a.headingLines};
        onMessage?.call('CONTENTS');
      case GlobalVisibility.showAll:
        folds = regions;
        bodyFolds = {};
        onMessage?.call('SHOW ALL');
    }
    if (notify) {
      _changed();
    } else {
      _foldVersion++;
    }
  }

  void cycleGlobal() {
    final next = switch (globalVisibility) {
      GlobalVisibility.showAll => GlobalVisibility.overview,
      GlobalVisibility.overview => GlobalVisibility.contents,
      GlobalVisibility.contents => GlobalVisibility.showAll,
    };
    setGlobal(next);
    _keepCaretVisible();
  }

  /// Shows headings down to [level], folding the rest.
  void showLevels(int level) {
    final a = analysis;
    final regions = folds.where((f) => f < a.lineCount && !a.isHeading(f)).toSet();
    folds = {...regions, for (final h in a.headingLines) if (a.levelOf(h) == level) h};
    bodyFolds = {for (final h in a.headingLines) if (a.levelOf(h) < level) h};
    _changed();
    _keepCaretVisible();
  }

  void foldAllDrawers({bool notify = true}) {
    final a = analysis;
    for (var l = 0; l < a.lineCount; l++) {
      if (a.infos[l].kind == LineKind.drawerBegin) folds.add(l);
    }
    if (notify) {
      _changed();
    } else {
      _foldVersion++;
    }
  }

  /// Initial visibility from #+STARTUP.
  void applyStartup({bool foldDrawers = true}) {
    final savedHandler = onMessage;
    onMessage = null;
    try {
      _applyStartup(foldDrawers);
    } finally {
      onMessage = savedHandler;
    }
  }

  void _applyStartup(bool foldDrawers) {
    final a = analysis;
    final s = a.startup;
    folds = {};
    bodyFolds = {};
    if (s.contains('overview') || s.contains('fold')) {
      setGlobal(GlobalVisibility.overview, notify: false);
    } else if (s.contains('content')) {
      setGlobal(GlobalVisibility.contents, notify: false);
    } else {
      final lv = s.map((x) => RegExp(r'^show(\d)levels?$').firstMatch(x)).whereType<RegExpMatch>().firstOrNull;
      if (lv != null) {
        final level = int.parse(lv.group(1)!);
        folds = {for (final h in a.headingLines) if (a.levelOf(h) == level) h};
        bodyFolds = {for (final h in a.headingLines) if (a.levelOf(h) < level) h};
        globalVisibility = GlobalVisibility.overview;
      } else {
        globalVisibility = GlobalVisibility.showAll;
      }
    }
    if (foldDrawers && !s.contains('nohidedrawers')) foldAllDrawers(notify: false);
    _foldVersion++;
    notifyListeners();
  }

  void unfoldAll() {
    folds = {};
    bodyFolds = {};
    globalVisibility = GlobalVisibility.showAll;
    _changed();
  }

  /// Removes folds hiding [offset].
  void revealOffset(int offset, {bool notify = true}) {
    final a = analysis;
    revealLine(a.lineOfOffset(offset.clamp(0, a.text.length)), notify: notify, a: a);
  }

  void revealLine(int line, {bool notify = true, OrgAnalysis? a}) {
    final an = a ?? analysis;
    var changed = false;
    for (var guard = 0; guard < 64; guard++) {
      _foldVersion++;
      final hidden = _hiddenLinesFor(an);
      final inside = hidden.any((r) => line >= r.$1 && line < r.$2);
      if (!inside) break;
      // Remove the fold whose hidden region contains the line, starting with
      // the innermost one.
      int? best;
      for (final f in [...folds, ...bodyFolds]) {
        final int end;
        if (an.isHeading(f)) {
          end = bodyFolds.contains(f) && !folds.contains(f) ? an.bodyEnd(f) : an.subtreeEnd(f);
        } else {
          end = (an.regionEnd[f] ?? f) + 1;
        }
        if (line > f && line < end && (best == null || f > best)) best = f;
      }
      if (best == null) break;
      folds.remove(best);
      bodyFolds.remove(best);
      changed = true;
    }
    if (changed) {
      _foldVersion++;
      if (notify) notifyListeners();
    }
  }

  void _keepCaretVisible() {
    final sel = selection;
    if (!sel.isValid) return;
    final a = analysis;
    final range = _hiddenCharRangeAt(a, sel.extentOffset);
    if (range != null) {
      final target = range.$1 - 1 < 0 ? 0 : range.$1 - 1;
      super.value = value.copyWith(selection: TextSelection.collapsed(offset: target));
    }
  }

  // -------------------------------------------------------------------------
  // Visible lines
  // -------------------------------------------------------------------------

  List<int>? _visible;
  OrgAnalysis? _visibleFor;
  int _visibleVersion = -1;

  /// Indices of the lines that are not inside a folded region.
  List<int> get visibleLines {
    final a = analysis;
    final hidden = _hiddenLinesFor(a);
    if (_visible != null && identical(_visibleFor, a) && _visibleVersion == _foldVersion) return _visible!;
    final out = <int>[];
    var h = 0;
    for (var i = 0; i < a.lineCount; i++) {
      while (h < hidden.length && hidden[h].$2 <= i) {
        h++;
      }
      if (h < hidden.length && i >= hidden[h].$1 && i < hidden[h].$2) {
        i = hidden[h].$2 - 1;
        continue;
      }
      out.add(i);
    }
    _visible = out;
    _visibleFor = a;
    _visibleVersion = _foldVersion;
    return out;
  }

  /// Whether line [f] ends in a fold marker.
  bool hasFoldMarker(int f) {
    final a = analysis;
    if (f < 0 || f >= a.lineCount) return false;
    if (folds.contains(f)) {
      if (a.isHeading(f)) return a.subtreeEnd(f) > f + 1;
      final e = a.regionEnd[f];
      return e != null;
    }
    if (bodyFolds.contains(f)) return a.bodyEnd(f) > f + 1;
    return false;
  }
}
