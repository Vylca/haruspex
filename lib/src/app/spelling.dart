import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:haruspex_hunspell/haruspex_hunspell.dart';

import 'document.dart';
import 'settings.dart';

/// A Hunspell dictionary on disk.
class Dictionary {
  const Dictionary(this.code, this.name, this.aff, this.dic, {this.bundled = false});

  /// Locale code such as "fr_FR", the file name without its extension.
  final String code;
  final String name;
  final String aff;
  final String dic;
  final bool bundled;
}

/// Names of the dictionaries that ship with the app, in menu order.
const bundledDictionaries = {
  'en_US': 'English (US)',
  'en_GB': 'English (UK)',
  'fr_FR': 'Français',
  'de_DE': 'Deutsch',
  'es_ES': 'Español',
  'it_IT': 'Italiano',
  'pt_PT': 'Português (Portugal)',
  'pt_BR': 'Português (Brasil)',
  'nl_NL': 'Nederlands',
  'ru_RU': 'Русский',
};

/// Dictionary used for a bare language code ("fr", "pt") when several
/// regions are available.
const _preferredRegion = {
  'en': 'en_US',
  'fr': 'fr_FR',
  'de': 'de_DE',
  'es': 'es_ES',
  'it': 'it_IT',
  'pt': 'pt_PT',
  'nl': 'nl_NL',
  'ru': 'ru_RU',
};

/// A loaded dictionary with a cache of checked words.
class SpellChecker {
  SpellChecker(this.code, this._h);

  final String code;
  final Hunspell _h;
  final Map<String, bool> _known = {};

  bool check(String word) {
    final hit = _known[word];
    if (hit != null) return hit;
    if (_known.length > 50000) _known.clear();
    return _known[word] = _h.spell(word);
  }

  /// Letters that differ only by an accent.
  static const _accentGroups = [
    'aàâäáãå', 'eéèêë', 'iîïíì', 'oôöóòõ', 'uùûüú', 'cç', 'yÿý', 'nñ', //
    'AÀÂÄÁÃÅ', 'EÉÈÊË', 'IÎÏÍÌ', 'OÔÖÓÒÕ', 'UÙÛÜÚ', 'CÇ', 'YŸÝ', 'NÑ',
  ];

  /// Corrections for [word], best first. A wrong accent is the most common
  /// slip (trés for très), and Hunspell sometimes misses it when the
  /// dictionary has a replacement rule that also fits, so those come first.
  List<String> suggest(String word) {
    final out = <String>[];
    for (var i = 0; i < word.length; i++) {
      final ch = word[i];
      for (final g in _accentGroups) {
        if (!g.contains(ch)) continue;
        for (final alt in g.split('')) {
          if (alt == ch) continue;
          final candidate = word.replaceRange(i, i + 1, alt);
          if (!out.contains(candidate) && check(candidate)) out.add(candidate);
        }
      }
    }
    for (final s in _h.suggest(word)) {
      if (!out.contains(s)) out.add(s);
    }
    return out;
  }

  void _add(String word) {
    _h.add(word);
    _known.remove(word);
  }

  void _remove(String word) {
    _h.remove(word);
    _known.remove(word);
  }
}

/// The spell checker: finds the dictionaries (bundled with the app, or
/// installed for Hunspell on the system), loads them on first use in the
/// background, and keeps the personal word list.
class SpellService extends ChangeNotifier {
  SpellService._();

  static final SpellService instance = SpellService._();

  final Map<String, Dictionary> _dicts = {};
  final Map<String, SpellChecker> _loaded = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};

  /// Words added with "Add to dictionary", saved to a file.
  final Set<String> personal = {};

  /// Words ignored until the app quits.
  final Set<String> ignored = {};

  File? _personalFile;

  /// Changes whenever a check could give a different answer (a dictionary
  /// loaded, a word added): part of the editor's cache keys.
  int generation = 0;

  bool _ready = false;
  bool get ready => _ready;

  /// Whether Hunspell could be loaded at all.
  bool get available => Hunspell.available;

  List<Dictionary> get dictionaries {
    final list = _dicts.values.toList();
    final order = bundledDictionaries.keys.toList();
    int rank(Dictionary d) {
      final i = order.indexOf(d.code);
      return i < 0 ? order.length : i;
    }

    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.code.compareTo(b.code);
    });
    return list;
  }

  Dictionary? dictionary(String code) => _dicts[code];

  /// Finds the dictionaries and reads the personal word list. [bundledDir]
  /// and [systemDirs] replace the usual places (tests).
  Future<void> init({String? bundledDir, List<String>? systemDirs, String? personalPath}) async {
    _dicts.clear();
    _loaded.clear();
    _failed.clear();
    final dir = bundledDir ?? await _bundledDir();
    if (dir != null) {
      for (final e in bundledDictionaries.entries) {
        final aff = '$dir/${e.key}.aff', dic = '$dir/${e.key}.dic';
        if (File(aff).existsSync() && File(dic).existsSync()) {
          _dicts[e.key] = Dictionary(e.key, e.value, aff, dic, bundled: true);
        }
      }
    }
    for (final d in systemDirs ?? _systemDirs()) {
      _scanSystem(d);
    }
    final personalFile = personalPath != null ? File(personalPath) : _defaultPersonalFile();
    _personalFile = personalFile;
    if (personalFile != null) {
      try {
        if (await personalFile.exists()) {
          personal
            ..clear()
            ..addAll((await personalFile.readAsLines()).map((l) => l.trim()).where((l) => l.isNotEmpty));
        }
      } catch (_) {
        // Unreadable word list: start empty.
      }
    }
    _ready = true;
    generation++;
    notifyListeners();
  }

  /// Bundled dictionaries are Flutter assets. On Linux they are plain files
  /// next to the app. Elsewhere they are copied out of the bundle once.
  static Future<String?> _bundledDir() async {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final direct = '$exeDir/data/flutter_assets/assets/dictionaries';
      if (File('$direct/en_US.aff').existsSync()) return direct;
      final cache = _cacheDir();
      if (cache == null) return null;
      final out = Directory('$cache/dictionaries');
      await out.create(recursive: true);
      for (final code in bundledDictionaries.keys) {
        for (final ext in ['aff', 'dic']) {
          final f = File('${out.path}/$code.$ext');
          try {
            final data = await rootBundle.load('assets/dictionaries/$code.$ext');
            if (f.existsSync() && f.lengthSync() == data.lengthInBytes) continue;
            await f.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
          } catch (_) {
            // Not in this build.
          }
        }
      }
      return out.path;
    } catch (_) {
      return null;
    }
  }

  static String? _cacheDir() {
    final env = Platform.environment;
    final base = env['XDG_CACHE_HOME'] ?? (env['HOME'] != null ? '${env['HOME']}/.cache' : null);
    return base == null ? Directory.systemTemp.path : '$base/haruspex';
  }

  static List<String> _systemDirs() {
    final env = Platform.environment;
    final home = env['HOME'];
    final data = env['XDG_DATA_HOME'] ?? (home != null ? '$home/.local/share' : null);
    return [
      '/usr/share/hunspell',
      '/usr/share/myspell',
      '/usr/share/myspell/dicts',
      if (data != null) '$data/hunspell',
    ];
  }

  static final RegExp _codeRe = RegExp(r'^[a-z]{2,3}(?:[_-][A-Za-z0-9]+)*$');

  void _scanSystem(String path) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return;
      for (final f in dir.listSync()) {
        if (f is! File || !f.path.endsWith('.aff')) continue;
        final base = f.path.substring(0, f.path.length - 4);
        final code = base.split('/').last;
        if (!_codeRe.hasMatch(code) || _dicts.containsKey(code)) continue;
        if (!File('$base.dic').existsSync()) continue;
        _dicts[code] = Dictionary(code, bundledDictionaries[code] ?? code, f.path, '$base.dic');
      }
    } catch (_) {
      // Unreadable folder.
    }
  }

  static File? _defaultPersonalFile() {
    final env = Platform.environment;
    final base = env['XDG_CONFIG_HOME'] ?? (env['HOME'] != null ? '${env['HOME']}/.config' : null);
    return base == null ? null : File('$base/haruspex/dictionary.txt');
  }

  /// The dictionary for a document: its `#+LANGUAGE:` value when it has one
  /// (null if no dictionary matches it), otherwise [fallback].
  String? resolve(String? orgLanguage, String fallback) {
    final lang = orgLanguage?.trim();
    if (lang != null && lang.isNotEmpty) return match(lang);
    return match(fallback) ?? (_dicts.isEmpty ? null : dictionaries.first.code);
  }

  /// The available dictionary closest to a language tag ("fr", "fr-CA",
  /// "pt_BR"), or null.
  String? match(String tag) {
    final t = tag.trim().replaceAll('-', '_');
    if (t.isEmpty) return null;
    for (final code in _dicts.keys) {
      if (code.toLowerCase() == t.toLowerCase()) return code;
    }
    final lang = t.split('_').first.toLowerCase();
    final preferred = _preferredRegion[lang];
    if (preferred != null && _dicts.containsKey(preferred)) return preferred;
    for (final code in dictionaries.map((d) => d.code)) {
      if (code.toLowerCase().split('_').first == lang) return code;
    }
    return null;
  }

  /// The system language as a dictionary code, if one is available.
  String? systemLanguage() {
    try {
      final name = Platform.localeName.split('.').first;
      return match(name);
    } catch (_) {
      return null;
    }
  }

  /// The checker for [code] once it is loaded. The first call starts loading
  /// it in the background and returns null, listeners hear when it is ready.
  SpellChecker? checker(String code) {
    final hit = _loaded[code];
    if (hit != null) return hit;
    if (_loading.contains(code) || _failed.contains(code)) return null;
    final d = _dicts[code];
    if (d == null) return null;
    _loading.add(code);
    _load(d);
    return null;
  }

  /// Whether [code] could not be loaded.
  bool failed(String code) => _failed.contains(code);

  Future<void> _load(Dictionary d) async {
    int? address;
    try {
      address = await _openInBackground(Hunspell.libraryPath, d.aff, d.dic);
    } catch (_) {
      address = null;
    }
    _loading.remove(d.code);
    final h = address == null ? null : Hunspell.fromAddress(address);
    if (h == null || !h.supported) {
      h?.dispose();
      _failed.add(d.code);
    } else {
      final c = SpellChecker(d.code, h);
      for (final w in personal) {
        c._add(w);
      }
      _loaded[d.code] = c;
    }
    generation++;
    notifyListeners();
  }

  /// Opens a dictionary in another isolate (it can take a few hundred
  /// milliseconds) and returns its native address. Not async, so the closure
  /// only captures its three strings.
  static Future<int?> _openInBackground(String? lib, String aff, String dic) => Isolate.run(() {
        Hunspell.libraryPath = lib;
        return Hunspell.open(aff, dic)?.address;
      });

  /// Loads [code] right away, for tests.
  @visibleForTesting
  SpellChecker? loadNow(String code) {
    final d = _dicts[code];
    if (d == null) return null;
    final h = Hunspell.open(d.aff, d.dic);
    if (h == null) return null;
    final c = SpellChecker(d.code, h);
    for (final w in personal) {
      c._add(w);
    }
    _loaded[code] = c;
    generation++;
    return c;
  }

  bool isIgnored(String word) => ignored.contains(word) || personal.contains(word);

  /// Adds [word] to the personal word list, for every language.
  Future<void> addWord(String word) async {
    if (!personal.add(word)) return;
    for (final c in _loaded.values) {
      c._add(word);
    }
    generation++;
    notifyListeners();
    await _savePersonal();
  }

  /// Removes [word] from the personal word list.
  Future<void> removeWord(String word) async {
    if (!personal.remove(word)) return;
    for (final c in _loaded.values) {
      c._remove(word);
    }
    generation++;
    notifyListeners();
    await _savePersonal();
  }

  /// Stops flagging [word] until the app quits.
  void ignore(String word) {
    if (!ignored.add(word)) return;
    generation++;
    notifyListeners();
  }

  Future<void> _savePersonal() async {
    final f = _personalFile;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      final words = personal.toList()..sort();
      await f.writeAsString(words.isEmpty ? '' : '${words.join('\n')}\n');
    } catch (_) {
      // Not fatal: the words stay for this session.
    }
  }
}

/// The dictionary [doc] is checked with, or null when it is not checked:
/// the language picked for it in the mode line, else its `#+LANGUAGE:`
/// keyword, else the language in Settings (or the system's).
String? spellCodeFor(OrgDocument doc, AppSettings settings) {
  if (!settings.spellCheck) return null;
  final chosen = doc.spellLanguage;
  if (chosen != null) return chosen.isEmpty ? null : chosen;
  final svc = SpellService.instance;
  final fallback = settings.spellLanguage.isNotEmpty ? settings.spellLanguage : (svc.systemLanguage() ?? 'en_US');
  return svc.resolve(doc.controller.analysis.keywords['LANGUAGE'], fallback);
}
