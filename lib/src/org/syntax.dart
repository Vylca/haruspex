/// Core Org syntax: TODO keyword configuration, heading parsing and the
/// regular expressions used to classify lines.
library;

class TodoSequence {
  TodoSequence(this.todo, this.done);
  final List<String> todo;
  final List<String> done;
  List<String> get all => [...todo, ...done];
}

class TodoConfig {
  TodoConfig(List<TodoSequence> sequences)
      : sequences = sequences.isEmpty ? [TodoSequence(['TODO'], ['DONE'])] : sequences {
    for (final s in this.sequences) {
      all.addAll(s.all);
      doneSet.addAll(s.done);
      todoSet.addAll(s.todo);
    }
    allSet.addAll(all);
  }

  static TodoConfig get defaults => TodoConfig([TodoSequence(['TODO'], ['DONE'])]);

  final List<TodoSequence> sequences;
  final List<String> all = [];
  final Set<String> allSet = {};
  final Set<String> doneSet = {};
  final Set<String> todoSet = {};

  bool isKeyword(String word) => allSet.contains(word);
  bool isDone(String? kw) => kw != null && doneSet.contains(kw);
  bool isTodo(String? kw) => kw != null && todoSet.contains(kw);

  String get firstTodo {
    for (final s in sequences) {
      if (s.todo.isNotEmpty) return s.todo.first;
    }
    return all.isNotEmpty ? all.first : 'TODO';
  }

  String? firstDoneFor(String? kw) {
    for (final s in sequences) {
      if (kw == null || s.all.contains(kw)) {
        if (s.done.isNotEmpty) return s.done.first;
      }
    }
    return doneSet.isNotEmpty ? doneSet.first : null;
  }

  /// Next keyword when cycling forward. `null` means "no keyword".
  String? next(String? current) {
    if (current == null) {
      final a = sequences.first.all;
      return a.isEmpty ? null : a.first;
    }
    for (final s in sequences) {
      final a = s.all;
      final i = a.indexOf(current);
      if (i >= 0) return i + 1 < a.length ? a[i + 1] : null;
    }
    return null;
  }

  String? previous(String? current) {
    if (current == null) {
      final a = sequences.first.all;
      return a.isEmpty ? null : a.last;
    }
    for (final s in sequences) {
      final a = s.all;
      final i = a.indexOf(current);
      if (i >= 0) return i - 1 >= 0 ? a[i - 1] : null;
    }
    return null;
  }

  /// Parses the values of `#+TODO:`, `#+SEQ_TODO:` and `#+TYP_TODO:` lines.
  static TodoConfig parse(Iterable<String> values) {
    final seqs = <TodoSequence>[];
    for (final v in values) {
      final words = v.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.isEmpty) continue;
      final todo = <String>[];
      final done = <String>[];
      var seenBar = false;
      for (final raw in words) {
        if (raw == '|') {
          seenBar = true;
          continue;
        }
        final w = raw.replaceFirst(RegExp(r'\(.*\)$'), '');
        if (w.isEmpty) continue;
        (seenBar ? done : todo).add(w);
      }
      if (!seenBar && todo.isNotEmpty) {
        done.add(todo.removeLast());
      }
      if (todo.isEmpty && done.isEmpty) continue;
      seqs.add(TodoSequence(todo, done));
    }
    return TodoConfig(seqs);
  }
}

/// A parsed heading line. All ranges are character offsets within the line,
/// `-1` when the part is absent.
class HeadingInfo {
  HeadingInfo({
    required this.level,
    required this.keyword,
    required this.kwStart,
    required this.kwEnd,
    required this.priority,
    required this.prioStart,
    required this.prioEnd,
    required this.titleStart,
    required this.titleEnd,
    required this.tags,
    required this.tagsStart,
    required this.tagsEnd,
  });

  final int level;
  final String? keyword;
  final int kwStart;
  final int kwEnd;
  final String? priority;
  final int prioStart;
  final int prioEnd;
  final int titleStart;
  final int titleEnd;
  final List<String> tags;
  final int tagsStart;
  final int tagsEnd;

  static final RegExp _tagsRe = RegExp(r'[ \t]+(:[\p{L}\p{N}_@#%:]+:)[ \t]*$', unicode: true);
  static final RegExp _wordRe = RegExp(r'^(\S+)(?=\s|$)');

  static bool isHeading(String line) => line.startsWith('*') && headingRe.hasMatch(line);

  static int levelOf(String line) {
    var i = 0;
    while (i < line.length && line.codeUnitAt(i) == 0x2A) {
      i++;
    }
    return i;
  }

  static HeadingInfo? parse(String line, TodoConfig cfg) {
    if (!isHeading(line)) return null;
    final level = levelOf(line);
    var p = level;
    while (p < line.length && (line[p] == ' ' || line[p] == '\t')) {
      p++;
    }
    String? kw;
    var kwStart = -1, kwEnd = -1;
    final wm = _wordRe.firstMatch(line.substring(p));
    if (wm != null && cfg.isKeyword(wm.group(1)!)) {
      kw = wm.group(1);
      kwStart = p;
      kwEnd = p + kw!.length;
      p = kwEnd;
      while (p < line.length && (line[p] == ' ' || line[p] == '\t')) {
        p++;
      }
    }
    String? prio;
    var prioStart = -1, prioEnd = -1;
    if (p + 3 < line.length && line.startsWith('[#', p) && line[p + 3] == ']') {
      prio = line[p + 2];
      prioStart = p;
      prioEnd = p + 4;
      p = prioEnd;
      while (p < line.length && (line[p] == ' ' || line[p] == '\t')) {
        p++;
      }
    }
    var tagsStart = -1, tagsEnd = -1;
    var tags = <String>[];
    var titleEnd = line.length;
    final tm = _tagsRe.firstMatch(line);
    if (tm != null && tm.start >= p - 1) {
      tagsStart = tm.start + tm.group(0)!.indexOf(':');
      tagsEnd = tagsStart + tm.group(1)!.length;
      tags = tm.group(1)!.split(':').where((t) => t.isNotEmpty).toList();
      titleEnd = tm.start;
    }
    if (titleEnd < p) titleEnd = p;
    while (titleEnd > p && (line[titleEnd - 1] == ' ' || line[titleEnd - 1] == '\t')) {
      titleEnd--;
    }
    return HeadingInfo(
      level: level,
      keyword: kw,
      kwStart: kwStart,
      kwEnd: kwEnd,
      priority: prio,
      prioStart: prioStart,
      prioEnd: prioEnd,
      titleStart: p,
      titleEnd: titleEnd,
      tags: tags,
      tagsStart: tagsStart,
      tagsEnd: tagsEnd,
    );
  }

  String title(String line) => line.substring(titleStart, titleEnd);

  /// Column where the "prefix" (stars, keyword, priority) ends. Shift-arrow
  /// commands act on the heading only when the caret is inside this area.
  int get prefixEnd {
    if (prioEnd >= 0) return prioEnd;
    if (kwEnd >= 0) return kwEnd;
    return level;
  }
}

final RegExp headingRe = RegExp(r'^(\*+)[ \t]+(.*?)[ \t]*$');
final RegExp planningRe = RegExp(r'^[ \t]*(SCHEDULED|DEADLINE|CLOSED):');
final RegExp planningWordRe = RegExp(r'(SCHEDULED|DEADLINE|CLOSED):');
final RegExp drawerBeginRe = RegExp(r'^[ \t]*:([\w-]+):[ \t]*$');
final RegExp drawerEndRe = RegExp(r'^[ \t]*:END:[ \t]*$', caseSensitive: false);
final RegExp propertyRe = RegExp(r'^[ \t]*:([^\s:]+):(?:[ \t]+(.*?))?[ \t]*$');
final RegExp blockBeginRe = RegExp(r'^[ \t]*#\+begin_(\S+)(.*)$', caseSensitive: false);
final RegExp keywordRe = RegExp(r'^[ \t]*#\+([^\s:]+):(?:[ \t]*(.*))?$');
final RegExp commentRe = RegExp(r'^[ \t]*#(?:[ \t]|$)');
final RegExp tableRe = RegExp(r'^[ \t]*\|');
final RegExp tableRuleRe = RegExp(r'^[ \t]*\|-');
final RegExp hruleRe = RegExp(r'^[ \t]*-{5,}[ \t]*$');
final RegExp fixedWidthRe = RegExp(r'^[ \t]*:(?:[ \t]|$)');
final RegExp footnoteDefRe = RegExp(r'^\[fn:[^\]\s]+\]');
final RegExp blankRe = RegExp(r'^[ \t]*$');

/// Plain list item: indent, bullet, optional counter cookie, optional checkbox.
final RegExp listItemRe = RegExp(
  r'^([ \t]*)([-+]|\d+[.)])([ \t]+|$)(\[@\d+\][ \t]+)?(\[[ xX-]\](?:[ \t]+|$))?',
);
final RegExp starItemRe = RegExp(r'^([ \t]+)(\*)([ \t]+|$)(\[@\d+\][ \t]+)?(\[[ xX-]\](?:[ \t]+|$))?');

RegExp blockEndRe(String type) =>
    RegExp(r'^[ \t]*#\+end_' + RegExp.escape(type) + r'[ \t]*$', caseSensitive: false);

int indentWidth(String line) {
  var n = 0;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == ' ') {
      n++;
    } else if (c == '\t') {
      n += 8 - (n % 8);
    } else {
      break;
    }
  }
  return n;
}

String leadingWhitespace(String line) {
  var i = 0;
  while (i < line.length && (line[i] == ' ' || line[i] == '\t')) {
    i++;
  }
  return line.substring(0, i);
}
