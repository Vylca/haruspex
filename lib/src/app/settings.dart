import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../editor/org_theme.dart';

class AppSettings extends ChangeNotifier {
  /// Bumped when the default look changes, so older settings files pick up
  /// the new defaults for the look once.
  static const int _styleVersion = 2;

  /// Editor font family: the bundled pixel font, any installed font, or a
  /// fontconfig alias such as "monospace", "sans-serif" or "serif".
  String fontFamily = pixelFont;

  /// Font for code, tables and verbatim text.
  String codeFontFamily = pixelFont;
  double fontSize = pixelSize;
  double lineHeight = 1.25;
  bool hideMarkup = true;
  bool scaleHeadings = false;
  bool superstar = true;

  /// Line numbers in a gutter on the left.
  bool lineNumbers = true;

  /// Center the text column instead of starting it at the left edge.
  bool centerText = false;

  /// Indent body text to line up with its heading (like org-indent-mode).
  bool indentBody = true;
  bool foldDrawers = true;
  bool showOutline = false;
  bool showFiles = true;

  static const double defaultFilesWidth = 260;
  static const double defaultOutlineWidth = 270;

  /// Widths of the file tree and the outline, set by dragging their edges.
  double filesWidth = defaultFilesWidth;
  double outlineWidth = defaultOutlineWidth;
  double maxWidth = 860;
  List<String> recentFiles = [];
  List<String> agendaFiles = [];
  bool tutorialShown = false;

  /// Folder opened as a vault, reopened at start.
  String? lastVault;
  List<String> recentVaults = [];

  OrgTheme get orgTheme => OrgTheme.hev;

  static File? _file([String app = 'haruspex']) {
    try {
      final env = Platform.environment;
      final base = env['XDG_CONFIG_HOME'] ?? (env['HOME'] != null ? '${env['HOME']}/.config' : null);
      if (base == null) return null;
      return File('$base/$app/settings.json');
    } catch (_) {
      return null;
    }
  }

  /// A saved font, with the pixel font of earlier versions mapped to the
  /// current one.
  static String? _font(String? family) => oldPixelFonts.contains(family) ? pixelFont : family;

  Future<void> load() async {
    var f = _file();
    if (f == null) return;
    try {
      if (!await f.exists()) {
        // Settings saved before the app was renamed.
        final old = _file('orgpad');
        if (old == null || !await old.exists()) return;
        f = old;
      }
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if ((j['styleVersion'] as num? ?? 0) >= _styleVersion) {
        fontFamily = _font(j['fontFamily'] as String?) ?? fontFamily;
        codeFontFamily = _font(j['codeFontFamily'] as String?) ?? codeFontFamily;
        fontSize = (j['fontSize'] as num?)?.toDouble() ?? fontSize;
        lineHeight = (j['lineHeight'] as num?)?.toDouble() ?? lineHeight;
        scaleHeadings = j['scaleHeadings'] as bool? ?? scaleHeadings;
      }
      hideMarkup = j['hideMarkup'] as bool? ?? hideMarkup;
      lineNumbers = j['lineNumbers'] as bool? ?? lineNumbers;
      centerText = j['centerText'] as bool? ?? centerText;
      superstar = j['superstar'] as bool? ?? superstar;
      indentBody = j['indentBody'] as bool? ?? indentBody;
      foldDrawers = j['foldDrawers'] as bool? ?? foldDrawers;
      showOutline = j['showOutline'] as bool? ?? showOutline;
      showFiles = j['showFiles'] as bool? ?? showFiles;
      filesWidth = (j['filesWidth'] as num?)?.toDouble() ?? filesWidth;
      outlineWidth = (j['outlineWidth'] as num?)?.toDouble() ?? outlineWidth;
      maxWidth = (j['maxWidth'] as num?)?.toDouble() ?? maxWidth;
      recentFiles = (j['recentFiles'] as List?)?.cast<String>() ?? recentFiles;
      agendaFiles = (j['agendaFiles'] as List?)?.cast<String>() ?? agendaFiles;
      tutorialShown = j['tutorialShown'] as bool? ?? tutorialShown;
      lastVault = j['lastVault'] as String?;
      recentVaults = (j['recentVaults'] as List?)?.cast<String>() ?? recentVaults;
    } catch (_) {
      // Ignore a broken settings file.
    }
  }

  Future<void> save() async {
    final f = _file();
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'styleVersion': _styleVersion,
        'fontFamily': fontFamily,
        'codeFontFamily': codeFontFamily,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'hideMarkup': hideMarkup,
        'scaleHeadings': scaleHeadings,
        'superstar': superstar,
        'lineNumbers': lineNumbers,
        'centerText': centerText,
        'indentBody': indentBody,
        'foldDrawers': foldDrawers,
        'showOutline': showOutline,
        'showFiles': showFiles,
        'filesWidth': filesWidth,
        'outlineWidth': outlineWidth,
        'maxWidth': maxWidth,
        'recentFiles': recentFiles,
        'agendaFiles': agendaFiles,
        'tutorialShown': tutorialShown,
        'lastVault': lastVault,
        'recentVaults': recentVaults,
      }));
    } catch (_) {
      // Not fatal.
    }
  }

  void update(void Function(AppSettings s) change) {
    change(this);
    notifyListeners();
    save();
  }

  void addRecent(String path) {
    recentFiles.remove(path);
    recentFiles.insert(0, path);
    if (recentFiles.length > 12) recentFiles = recentFiles.sublist(0, 12);
    notifyListeners();
    save();
  }

  void addRecentVault(String path) {
    recentVaults.remove(path);
    recentVaults.insert(0, path);
    if (recentVaults.length > 8) recentVaults = recentVaults.sublist(0, 8);
    lastVault = path;
    notifyListeners();
    save();
  }
}

/// The bundled pixel font plus the installed font families, from fontconfig.
Future<List<String>> systemFontFamilies() async {
  final families = <String>{pixelFont, 'monospace', 'sans-serif', 'serif'};
  try {
    final r = await Process.run('fc-list', [':', 'family']);
    if (r.exitCode == 0) {
      for (final line in (r.stdout as String).split('\n')) {
        final name = line.split(',').first.trim();
        if (name.isNotEmpty && !name.startsWith('.')) families.add(name);
      }
    }
  } catch (_) {
    // fc-list missing: only the generic names are offered.
  }
  final list = families.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}
