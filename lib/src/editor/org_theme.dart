import 'package:flutter/material.dart';

/// The pixel font bundled with the app (Spleen 8x16). It is crisp at 16 px
/// and whole multiples of it.
const String pixelFont = 'Spleen';

/// Size at which [pixelFont] lines up with the screen pixels.
const double pixelSize = 16;

class OrgTheme {
  const OrgTheme({
    required this.background,
    required this.panel,
    required this.panelHi,
    required this.border,
    required this.hlLine,
    required this.text,
    required this.bright,
    required this.faint,
    required this.levels,
    required this.todo,
    required this.done,
    required this.priority,
    required this.tag,
    required this.link,
    required this.timestamp,
    required this.code,
    required this.codeBg,
    required this.accent,
    required this.accentDim,
    required this.markerBg,
    required this.markerFg,
    required this.selection,
    required this.searchHit,
  });

  /// Editor background.
  final Color background;

  /// Menu bar, tabs, mode line and side panels (darker than the editor).
  final Color panel;

  /// Hovered items in panels and menus.
  final Color panelHi;

  /// One pixel lines between areas.
  final Color border;

  /// Background of the line holding the caret.
  final Color hlLine;
  final Color text;

  /// Bold text.
  final Color bright;
  final Color faint;
  final List<Color> levels;
  final Color todo;
  final Color done;
  final Color priority;
  final Color tag;
  final Color link;
  final Color timestamp;
  final Color code;
  final Color codeBg;

  /// The orange.
  final Color accent;
  final Color accentDim;
  final Color markerBg;
  final Color markerFg;
  final Color selection;
  final Color searchHit;

  Color level(int l) => levels[(l - 1) % levels.length];

  /// Black and orange, after the HUDs and menus of early 2000s shooters.
  static const hev = OrgTheme(
    background: Color(0xFF0F0E0C),
    panel: Color(0xFF080706),
    panelHi: Color(0xFF221A0F),
    border: Color(0xFF2C251C),
    hlLine: Color(0xFF1A1610),
    text: Color(0xFFDDD2BC),
    bright: Color(0xFFFFF1D6),
    faint: Color(0xFF7A6E5C),
    levels: [
      Color(0xFFFF9F1C),
      Color(0xFFFFC857),
      Color(0xFFE8683A),
      Color(0xFFD9B26F),
      Color(0xFFF4A259),
      Color(0xFFB8B068),
      Color(0xFFC8834E),
      Color(0xFF9C9478),
    ],
    todo: Color(0xFFFF4B2B),
    done: Color(0xFF8FA35B),
    priority: Color(0xFFFFC857),
    tag: Color(0xFF8C8A6A),
    link: Color(0xFFFFC857),
    timestamp: Color(0xFFC9A66B),
    code: Color(0xFFE9B872),
    codeBg: Color(0xFF1C1813),
    accent: Color(0xFFFF9F1C),
    accentDim: Color(0xFF7A4A0E),
    markerBg: Color(0xFF2A1D0B),
    markerFg: Color(0xFFFF9F1C),
    selection: Color(0xFF5A3912),
    searchHit: Color(0x99B36B00),
  );
}
