import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../editor/org_theme.dart';

class AppSettings extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;

  /// Editor font family (any installed font, or a fontconfig alias such as
  /// "monospace", "sans-serif" or "serif").
  String fontFamily = 'monospace';

  /// Font for code, tables and verbatim text.
  String codeFontFamily = 'monospace';
  double fontSize = 16;
  double lineHeight = 1.5;
  bool hideMarkup = true;
  bool scaleHeadings = true;
  bool superstar = true;

  /// Indent body text to line up with its heading (like org-indent-mode).
  bool indentBody = true;
  bool foldDrawers = true;
  bool showOutline = false;
  bool showFiles = true;
  double maxWidth = 860;
  List<String> recentFiles = [];
  List<String> agendaFiles = [];
  bool tutorialShown = false;

  /// Folder opened as a vault, reopened at start.
  String? lastVault;
  List<String> recentVaults = [];

  OrgTheme orgTheme(Brightness b) => b == Brightness.dark ? OrgTheme.dark : OrgTheme.light;

  static File? _file() {
    try {
      final env = Platform.environment;
      final base = env['XDG_CONFIG_HOME'] ?? (env['HOME'] != null ? '${env['HOME']}/.config' : null);
      if (base == null) return null;
      return File('$base/orgpad/settings.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    final f = _file();
    if (f == null) return;
    try {
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      themeMode = ThemeMode.values.firstWhere((m) => m.name == j['themeMode'], orElse: () => ThemeMode.system);
      fontFamily = j['fontFamily'] as String? ?? fontFamily;
      codeFontFamily = j['codeFontFamily'] as String? ?? codeFontFamily;
      fontSize = (j['fontSize'] as num?)?.toDouble() ?? fontSize;
      lineHeight = (j['lineHeight'] as num?)?.toDouble() ?? lineHeight;
      hideMarkup = j['hideMarkup'] as bool? ?? hideMarkup;
      scaleHeadings = j['scaleHeadings'] as bool? ?? scaleHeadings;
      superstar = j['superstar'] as bool? ?? superstar;
      indentBody = j['indentBody'] as bool? ?? indentBody;
      foldDrawers = j['foldDrawers'] as bool? ?? foldDrawers;
      showOutline = j['showOutline'] as bool? ?? showOutline;
      showFiles = j['showFiles'] as bool? ?? showFiles;
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
        'themeMode': themeMode.name,
        'fontFamily': fontFamily,
        'codeFontFamily': codeFontFamily,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'hideMarkup': hideMarkup,
        'scaleHeadings': scaleHeadings,
        'superstar': superstar,
        'indentBody': indentBody,
        'foldDrawers': foldDrawers,
        'showOutline': showOutline,
        'showFiles': showFiles,
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

/// Installed font families, from fontconfig.
Future<List<String>> systemFontFamilies() async {
  final families = <String>{'monospace', 'sans-serif', 'serif'};
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
