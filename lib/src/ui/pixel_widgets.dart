import 'package:flutter/gestures.dart';
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
    this.hotColor,
  });

  final OrgTheme theme;
  final VoidCallback? onTap;
  final Widget Function(bool hot) builder;
  final String? tooltip;
  final GestureTapDownCallback? onSecondaryTapDown;

  /// Drawn as the current item (dim orange background) when not hovered.
  final bool selected;

  /// Background under the mouse, orange by default.
  final Color? hotColor;

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
          color: hot ? (widget.hotColor ?? t.accent) : (widget.selected ? t.markerBg : Colors.transparent),
          child: widget.builder(hot),
        ),
      ),
    );
    final tip = widget.tooltip;
    if (tip != null) child = Tooltip(message: tip, child: child);
    return child;
  }
}

/// The Haruspex logo, the alchemical symbol for earth, made by
/// tool/build_icon.py.
const List<String> logoRows = [
  '##########################',
  '##########################',
  '.##....................##.',
  '..##..................##..',
  '..##..................##..',
  '...##................##...',
  '....##..............##....',
  '....##..............##....',
  '.....##............##.....',
  '...####################...',
  '...####################...',
  '.......##........##.......',
  '........##......##........',
  '........##......##........',
  '.........##....##.........',
  '..........##..##..........',
  '..........##..##..........',
  '...........####...........',
  '............##............',
  '............##............',
];

/// The logo with one pixel strokes, for the title bar.
const List<String> smallLogoRows = [
  '#############',
  '#...........#',
  '.#.........#.',
  '..#.......#..',
  '..#.......#..',
  '.###########.',
  '....#...#....',
  '....#...#....',
  '.....#.#.....',
  '......#......',
  '......#......',
];

/// Pixel art from rows of '#' (filled) and '.' (empty), drawn as squares.
class PixelArt extends StatelessWidget {
  const PixelArt(this.rows, {super.key, required this.color, this.pixel = 8});

  final List<String> rows;
  final Color color;

  /// Side of one square, in logical pixels.
  final double pixel;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(rows.first.length * pixel, rows.length * pixel),
      painter: _PixelPainter(rows, color, pixel),
    );
  }
}

/// Big blocky letters, used for the dashboard banner.
class PixelBanner extends StatelessWidget {
  const PixelBanner(this.text, {super.key, required this.color, this.pixel = 8});

  final String text;
  final Color color;
  final double pixel;

  static const _glyphs = {
    'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    'D': ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
    'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
    'G': ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.###.'],
    'H': ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
    'O': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
    'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
    'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
    'U': ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    'X': ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
  };

  /// Width of [text] in squares.
  static int widthOf(String text) => text.isEmpty ? 0 : text.length * 6 - 1;

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
  Widget build(BuildContext context) => PixelArt(_rows, color: color, pixel: pixel);
}

class _PixelPainter extends CustomPainter {
  _PixelPainter(this.rows, this.color, this.pixel);

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
  bool shouldRepaint(covariant _PixelPainter old) =>
      old.color != color || old.pixel != pixel || old.rows.join() != rows.join();
}

/// The line between two panels. Drag it to resize them, double click to go
/// back to the default size.
class PanelSplitter extends StatefulWidget {
  const PanelSplitter({
    super.key,
    required this.theme,
    required this.onDrag,
    this.onDragEnd,
    this.onReset,
  });

  final OrgTheme theme;

  /// Called with the horizontal movement since the last update.
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;
  final VoidCallback? onReset;

  @override
  State<PanelSplitter> createState() => _PanelSplitterState();
}

class _PanelSplitterState extends State<PanelSplitter> {
  bool _hot = false;
  bool _dragging = false;

  void _end() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    widget.onDragEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final lit = _hot || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hot = true),
      onExit: (_) => setState(() => _hot = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Count the movement from the press, not from where the drag is
        // recognized, so the line stays under the mouse.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => _end(),
        onHorizontalDragCancel: _end,
        onDoubleTap: widget.onReset,
        child: SizedBox(
          width: 5,
          child: Center(child: Container(width: lit ? 2 : 1, color: lit ? t.accent : t.border)),
        ),
      ),
    );
  }
}
