/// Org timestamps: parsing, formatting, shifting and repeaters.
library;

const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

DateTime shiftDate(DateTime d, int n, String unit) {
  switch (unit) {
    case 'h':
      return d.add(Duration(hours: n));
    case 'd':
      return DateTime(d.year, d.month, d.day + n, d.hour, d.minute);
    case 'w':
      return DateTime(d.year, d.month, d.day + 7 * n, d.hour, d.minute);
    case 'm':
      return DateTime(d.year, d.month + n, d.day, d.hour, d.minute);
    case 'y':
      return DateTime(d.year + n, d.month, d.day, d.hour, d.minute);
  }
  return d;
}

int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

String _two(int n) => n.toString().padLeft(2, '0');

class Repeater {
  Repeater(this.type, this.n, this.unit);
  final String type; // '+', '++' or '.+'
  final int n;
  final String unit;

  static final RegExp _re = RegExp(r'^(\.\+|\+\+|\+)(\d+)([hdwmy])');

  static Repeater? parse(String? s) {
    if (s == null) return null;
    final m = _re.firstMatch(s);
    if (m == null) return null;
    return Repeater(m.group(1)!, int.parse(m.group(2)!), m.group(3)!);
  }
}

enum TsField { year, month, day, hour, minute, endHour, endMinute }

class OrgTimestamp {
  OrgTimestamp({
    required this.active,
    required this.date,
    this.hour,
    this.minute,
    this.endHour,
    this.endMinute,
    this.repeater,
    this.warning,
  });

  final bool active;
  final DateTime date; // date part only
  final int? hour;
  final int? minute;
  final int? endHour;
  final int? endMinute;

  /// Raw repeater cookie, e.g. "+1w", ".+2d", "++1m/3d".
  final String? repeater;

  /// Raw warning cookie, e.g. "-3d".
  final String? warning;

  static final RegExp pattern = RegExp(
    r'([<\[])(\d{4})-(\d{2})-(\d{2})'
    r'(?:[ \t]+([^\s\d>\]+-]+))?'
    r'(?:[ \t]+(\d{1,2}):(\d{2})(?:-(\d{1,2}):(\d{2}))?)?'
    r'(?:[ \t]+((?:\.\+|\+\+|\+)\d+[hdwmy](?:/\d+[hdwmy])?))?'
    r'(?:[ \t]+(--?\d+[hdwmy]))?'
    r'[ \t]*([>\]])',
  );

  /// Parses a match of [pattern]; returns null for mismatched brackets or
  /// invalid dates.
  static OrgTimestamp? fromMatch(RegExpMatch m) {
    final open = m.group(1)!, close = m.group(12)!;
    if ((open == '<') != (close == '>')) return null;
    final y = int.parse(m.group(2)!), mo = int.parse(m.group(3)!), d = int.parse(m.group(4)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    int? p(int g) => m.group(g) == null ? null : int.parse(m.group(g)!);
    return OrgTimestamp(
      active: open == '<',
      date: DateTime(y, mo, d),
      hour: p(6),
      minute: p(7),
      endHour: p(8),
      endMinute: p(9),
      repeater: m.group(10),
      warning: m.group(11),
    );
  }

  static OrgTimestamp? parse(String s) {
    final m = pattern.firstMatch(s);
    return m == null ? null : fromMatch(m);
  }

  /// All valid timestamps in [line] with their match.
  static List<(RegExpMatch, OrgTimestamp)> findAll(String line) {
    final result = <(RegExpMatch, OrgTimestamp)>[];
    if (!line.contains('<') && !line.contains('[')) return result;
    for (final m in pattern.allMatches(line)) {
      final ts = fromMatch(m);
      if (ts != null) result.add((m, ts));
    }
    return result;
  }

  static OrgTimestamp now({bool active = true, bool withTime = false}) {
    final n = DateTime.now();
    return OrgTimestamp(
      active: active,
      date: dateOnly(n),
      hour: withTime ? n.hour : null,
      minute: withTime ? n.minute : null,
    );
  }

  bool get hasTime => hour != null && minute != null;

  String get timeString {
    if (!hasTime) return '';
    var s = '${_two(hour!)}:${_two(minute!)}';
    if (endHour != null && endMinute != null) s += '-${_two(endHour!)}:${_two(endMinute!)}';
    return s;
  }

  String format() {
    final b = StringBuffer(active ? '<' : '[');
    b.write('${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}');
    b.write(' ${weekdayNames[date.weekday - 1]}');
    if (hasTime) b.write(' $timeString');
    if (repeater != null) b.write(' $repeater');
    if (warning != null) b.write(' $warning');
    b.write(active ? '>' : ']');
    return b.toString();
  }

  @override
  String toString() => format();

  OrgTimestamp copyWith({
    bool? active,
    DateTime? date,
    int? Function()? hour,
    int? Function()? minute,
    int? Function()? endHour,
    int? Function()? endMinute,
    String? Function()? repeater,
    String? Function()? warning,
  }) {
    return OrgTimestamp(
      active: active ?? this.active,
      date: date ?? this.date,
      hour: hour != null ? hour() : this.hour,
      minute: minute != null ? minute() : this.minute,
      endHour: endHour != null ? endHour() : this.endHour,
      endMinute: endMinute != null ? endMinute() : this.endMinute,
      repeater: repeater != null ? repeater() : this.repeater,
      warning: warning != null ? warning() : this.warning,
    );
  }

  OrgTimestamp addDays(int n) => copyWith(date: DateTime(date.year, date.month, date.day + n));

  /// Shifts one field by [delta] (minutes move in steps of 5, like Org).
  OrgTimestamp shiftField(TsField f, int delta) {
    switch (f) {
      case TsField.year:
        return copyWith(date: DateTime(date.year + delta, date.month, date.day));
      case TsField.month:
        return copyWith(date: DateTime(date.year, date.month + delta, date.day));
      case TsField.day:
        return addDays(delta);
      case TsField.hour:
      case TsField.minute:
        if (!hasTime) return addDays(delta);
        final mins = f == TsField.hour ? delta * 60 : delta * 5;
        return _shiftMinutes(mins, shiftEnd: true);
      case TsField.endHour:
      case TsField.endMinute:
        if (endHour == null || endMinute == null) return _shiftMinutes(delta * 60, shiftEnd: true);
        final mins = f == TsField.endHour ? delta * 60 : delta * 5;
        final total = ((endHour! * 60 + endMinute! + mins) % 1440 + 1440) % 1440;
        return copyWith(endHour: () => total ~/ 60, endMinute: () => total % 60);
    }
    // ignore: dead_code
    return this;
  }

  OrgTimestamp _shiftMinutes(int mins, {required bool shiftEnd}) {
    final start = DateTime(date.year, date.month, date.day, hour!, minute!).add(Duration(minutes: mins));
    int? eh = endHour, em = endMinute;
    if (shiftEnd && eh != null && em != null) {
      final total = ((eh * 60 + em + mins) % 1440 + 1440) % 1440;
      eh = total ~/ 60;
      em = total % 60;
    }
    return OrgTimestamp(
      active: active,
      date: dateOnly(start),
      hour: start.hour,
      minute: start.minute,
      endHour: eh,
      endMinute: em,
      repeater: repeater,
      warning: warning,
    );
  }

  /// Which field the character at [col] (relative to the timestamp start)
  /// belongs to.
  TsField fieldAt(String raw, int col) {
    if (col >= 1 && col < 5) return TsField.year;
    if (col >= 6 && col < 8) return TsField.month;
    if (col >= 9 && col < 11) return TsField.day;
    final timeMatch = RegExp(r'(\d{1,2}):(\d{2})(?:-(\d{1,2}):(\d{2}))?').firstMatch(raw.substring(11 < raw.length ? 11 : raw.length));
    if (timeMatch != null) {
      final base = 11 + timeMatch.start;
      final hEnd = base + timeMatch.group(1)!.length;
      if (col >= base && col < hEnd) return TsField.hour;
      if (col > hEnd && col <= hEnd + 2) return TsField.minute;
      if (timeMatch.group(3) != null) {
        final eStart = hEnd + 4;
        final eEnd = eStart + timeMatch.group(3)!.length;
        if (col >= eStart && col < eEnd) return TsField.endHour;
        if (col > eEnd && col <= eEnd + 2) return TsField.endMinute;
      }
    }
    return TsField.day;
  }

  DateTime get dateTime => DateTime(date.year, date.month, date.day, hour ?? 0, minute ?? 0);

  /// Applies the repeater when the entry is marked done; returns null when
  /// there is no repeater.
  OrgTimestamp? repeated(DateTime now) {
    final r = Repeater.parse(repeater);
    if (r == null) return null;
    var dt = dateTime;
    switch (r.type) {
      case '+':
        dt = shiftDate(dt, r.n, r.unit);
      case '++':
        var guard = 0;
        do {
          dt = shiftDate(dt, r.n, r.unit);
          guard++;
        } while (!dt.isAfter(now) && guard < 100000);
        if (r.unit != 'h' && !hasTime) {
          // For date-only stamps "future" means strictly after today.
          while (!dateOnly(dt).isAfter(dateOnly(now)) && guard < 100000) {
            dt = shiftDate(dt, r.n, r.unit);
            guard++;
          }
        }
      case '.+':
        final base = r.unit == 'h' ? now : DateTime(now.year, now.month, now.day, hour ?? 0, minute ?? 0);
        dt = shiftDate(base, r.n, r.unit);
    }
    return OrgTimestamp(
      active: active,
      date: dateOnly(dt),
      hour: hasTime ? dt.hour : null,
      minute: hasTime ? dt.minute : null,
      endHour: endHour,
      endMinute: endMinute,
      repeater: repeater,
      warning: warning,
    );
  }

  /// Dates (date part) on which this timestamp occurs in [from, to] inclusive,
  /// expanding repeaters.
  List<DateTime> occurrences(DateTime from, DateTime to) {
    final f = dateOnly(from), t = dateOnly(to);
    final r = Repeater.parse(repeater);
    if (r == null || r.unit == 'h' || r.n <= 0) {
      return (date.isBefore(f) || date.isAfter(t)) ? const [] : [date];
    }
    final result = <DateTime>[];
    var d = date;
    var guard = 0;
    while (!d.isAfter(t) && guard < 5000) {
      if (!d.isBefore(f)) result.add(d);
      d = dateOnly(shiftDate(d, r.n, r.unit));
      guard++;
    }
    return result;
  }

  /// Warning period in days for deadlines (default [defaultDays]).
  int warningDays(int defaultDays) {
    final w = warning;
    if (w == null) return defaultDays;
    final m = RegExp(r'--?(\d+)([hdwmy])').firstMatch(w);
    if (m == null) return defaultDays;
    final n = int.parse(m.group(1)!);
    switch (m.group(2)) {
      case 'h':
        return 0;
      case 'w':
        return n * 7;
      case 'm':
        return n * 30;
      case 'y':
        return n * 365;
    }
    return n;
  }
}
