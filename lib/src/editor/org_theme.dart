import 'package:flutter/material.dart';

class OrgTheme {
  const OrgTheme({
    required this.background,
    required this.text,
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
    required this.markerBg,
    required this.markerFg,
    required this.selection,
    required this.searchHit,
  });

  final Color background;
  final Color text;
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
  final Color accent;
  final Color markerBg;
  final Color markerFg;
  final Color selection;
  final Color searchHit;

  Color level(int l) => levels[(l - 1) % levels.length];

  static const light = OrgTheme(
    background: Color(0xFFFBFAF7),
    text: Color(0xFF1F2328),
    faint: Color(0xFF8C959F),
    levels: [
      Color(0xFF0B5CAD),
      Color(0xFF8250DF),
      Color(0xFF1A7F37),
      Color(0xFFBC4C00),
      Color(0xFF0969DA),
      Color(0xFFBF3989),
      Color(0xFF6639BA),
      Color(0xFF116329),
    ],
    todo: Color(0xFFCF222E),
    done: Color(0xFF1A7F37),
    priority: Color(0xFFBC4C00),
    tag: Color(0xFF6E7781),
    link: Color(0xFF0969DA),
    timestamp: Color(0xFF8250DF),
    code: Color(0xFF953800),
    codeBg: Color(0x14000000),
    accent: Color(0xFF0B5CAD),
    markerBg: Color(0x1A0B5CAD),
    markerFg: Color(0xFF0B5CAD),
    selection: Color(0x400969DA),
    searchHit: Color(0x66F2CC60),
  );

  static const dark = OrgTheme(
    background: Color(0xFF16181D),
    text: Color(0xFFE6EDF3),
    faint: Color(0xFF6E7681),
    levels: [
      Color(0xFF58A6FF),
      Color(0xFFD2A8FF),
      Color(0xFF7EE787),
      Color(0xFFFFA657),
      Color(0xFF79C0FF),
      Color(0xFFFF7B72),
      Color(0xFFBC8CFF),
      Color(0xFF56D364),
    ],
    todo: Color(0xFFFF7B72),
    done: Color(0xFF7EE787),
    priority: Color(0xFFFFA657),
    tag: Color(0xFF8B949E),
    link: Color(0xFF58A6FF),
    timestamp: Color(0xFFD2A8FF),
    code: Color(0xFFFFA657),
    codeBg: Color(0x1FFFFFFF),
    accent: Color(0xFF58A6FF),
    markerBg: Color(0x2658A6FF),
    markerFg: Color(0xFF79C0FF),
    selection: Color(0x5558A6FF),
    searchHit: Color(0x55BB8009),
  );
}
