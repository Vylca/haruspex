import 'package:flutter/material.dart';

import '../editor/org_theme.dart';

/// A flat clickable area that turns orange (with black content) under the
/// mouse. [builder] gets whether it is hovered.
class HoverBox extends StatefulWidget {
  const HoverBox({
    super.key,
    required this.theme,
    required this.onTap,
    required this.builder,
    this.tooltip,
    this.onSecondaryTapDown,
    this.selected = false,
  });

  final OrgTheme theme;
  final VoidCallback? onTap;
  final Widget Function(bool hot) builder;
  final String? tooltip;
  final GestureTapDownCallback? onSecondaryTapDown;

  /// Drawn as the current item (dim orange background) when not hovered.
  final bool selected;

  @override
  State<HoverBox> createState() => _HoverBoxState();
}

class _HoverBoxState extends State<HoverBox> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final hot = _hot && widget.onTap != null;
    Widget child = MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hot = true),
      onExit: (_) => setState(() => _hot = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: ColoredBox(
          color: hot ? t.accent : (widget.selected ? t.markerBg : Colors.transparent),
          child: widget.builder(hot),
        ),
      ),
    );
    final tip = widget.tooltip;
    if (tip != null) child = Tooltip(message: tip, child: child);
    return child;
  }
}

/// Big blocky letters drawn as squares, used for the dashboard banner.
class PixelBanner extends StatelessWidget {
  const PixelBanner(this.text, {super.key, required this.color, this.pixel = 8});

  final String text;
  final Color color;

  /// Side of one square, in logical pixels.
  final double pixel;

  static const _glyphs = {
    'O': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
    'G': ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.###.'],
    'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
    'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    'D': ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
  };

  List<String> get _rows {
    final rows = List.filled(7, '');
    for (final ch in text.split('')) {
      final g = _glyphs[ch] ?? List.filled(7, '.....');
      for (var r = 0; r < 7; r++) {
        rows[r] += rows[r].isEmpty ? g[r] : '.${g[r]}';
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return CustomPaint(
      size: Size(rows.first.length * pixel, rows.length * pixel),
      painter: _BannerPainter(rows, color, pixel),
    );
  }
}

class _BannerPainter extends CustomPainter {
  _BannerPainter(this.rows, this.color, this.pixel);

  final List<String> rows;
  final Color color;
  final double pixel;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    final path = Path();
    for (var y = 0; y < rows.length; y++) {
      final row = rows[y];
      var x = 0;
      while (x < row.length) {
        if (row[x] != '#') {
          x++;
          continue;
        }
        final start = x;
        while (x < row.length && row[x] == '#') {
          x++;
        }
        path.addRect(Rect.fromLTWH(start * pixel, y * pixel, (x - start) * pixel, pixel));
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BannerPainter old) =>
      old.color != color || old.pixel != pixel || old.rows.join() != rows.join();
}
