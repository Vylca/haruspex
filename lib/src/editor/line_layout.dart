import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A laid-out logical line: one paragraph, offset by [indent].
class LineLayout {
  LineLayout(this.painter, this.indent);

  final TextPainter painter;
  final double indent;
  List<ui.LineMetrics>? _metrics;

  double get height => painter.height;

  List<ui.LineMetrics> get metrics => _metrics ??= painter.computeLineMetrics();

  /// Top and bottom of the visual line containing local y [y].
  (double, double) visualLineAt(double y) {
    final ms = metrics;
    if (ms.isEmpty) return (0, height);
    for (final m in ms) {
      final top = m.baseline - m.ascent;
      final bottom = m.baseline + m.descent;
      if (y < bottom) return (top, bottom);
    }
    final last = ms.last;
    return (last.baseline - last.ascent, last.baseline + last.descent);
  }

  void dispose() => painter.dispose();
}

/// Keeps line layouts between frames; layouts that were not used in the last
/// pass are disposed.
class LineLayoutCache {
  Map<String, LineLayout> _entries = {};
  Map<String, LineLayout> _next = {};

  LineLayout get(String key, LineLayout Function() create) {
    final hit = _next[key] ?? _entries.remove(key);
    if (hit != null) {
      _next[key] = hit;
      return hit;
    }
    final made = create();
    _next[key] = made;
    return made;
  }

  /// Keeps a layout from the previous pass for this pass.
  void keep(String key, LineLayout layout) {
    _entries.remove(key);
    _next[key] = layout;
  }

  /// Ends a layout pass: everything not requested since the last call is
  /// disposed after the current frame.
  void endPass() {
    final stale = _entries.values.toList();
    _entries = _next;
    _next = {};
    if (stale.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final l in stale) {
          l.dispose();
        }
      });
    }
  }

  void clear() {
    for (final l in _entries.values) {
      l.dispose();
    }
    for (final l in _next.values) {
      l.dispose();
    }
    _entries = {};
    _next = {};
  }
}
