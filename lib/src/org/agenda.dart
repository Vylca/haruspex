/// Agenda: day/week view of scheduled items, deadlines and timestamps, plus
/// the global TODO list.
library;

import 'analysis.dart';
import 'timestamp.dart';

class AgendaSource {
  AgendaSource(this.id, this.name, this.text);
  final String id;
  final String name;
  final String text;
}

enum AgendaKind { deadline, overdueDeadline, deadlineWarning, scheduled, overdueScheduled, timestamp, range, todo }

class AgendaItem {
  AgendaItem({
    required this.sourceId,
    required this.sourceName,
    required this.line,
    required this.title,
    required this.keyword,
    required this.done,
    required this.priority,
    required this.tags,
    required this.kind,
    required this.label,
    this.time,
    this.date,
  });

  final String sourceId;
  final String sourceName;
  final int line;
  final String title;
  final String? keyword;
  final bool done;
  final String? priority;
  final List<String> tags;
  final AgendaKind kind;
  final String label;
  final String? time;
  final DateTime? date;
}

class AgendaDay {
  AgendaDay(this.date, this.items);
  final DateTime date;
  final List<AgendaItem> items;
}

final RegExp _linkRe = RegExp(r'\[\[([^\[\]]+)\](?:\[([^\[\]]+)\])?\]');
final RegExp _scheduledRe = RegExp(r'SCHEDULED:[ \t]*(<[^>]*>)');
final RegExp _deadlineRe = RegExp(r'DEADLINE:[ \t]*(<[^>]*>)');
final RegExp _rangeRe = RegExp(r'(<[^<>\n]+>)--(<[^<>\n]+>)');

String plainTitle(String title) =>
    title.replaceAllMapped(_linkRe, (m) => m.group(2) ?? m.group(1)!).trim();

class _Entry {
  _Entry(this.source, this.a, this.h);
  final AgendaSource source;
  final OrgAnalysis a;
  final int h;

  AgendaItem item(AgendaKind kind, String label, {String? time, DateTime? date}) {
    final info = a.headingInfo(h)!;
    final line = a.lines[h];
    return AgendaItem(
      sourceId: source.id,
      sourceName: source.name,
      line: h,
      title: plainTitle(info.title(line)),
      keyword: info.keyword,
      done: a.todo.isDone(info.keyword),
      priority: info.priority,
      tags: info.tags,
      kind: kind,
      label: label,
      time: time,
      date: date,
    );
  }
}

List<AgendaDay> buildAgenda(List<AgendaSource> sources, DateTime start, int days, {DateTime? today, int warningDays = 14}) {
  final t = dateOnly(today ?? DateTime.now());
  final from = dateOnly(start);
  final to = addDays(from, days - 1);
  final byDay = <int, List<AgendaItem>>{};
  void add(DateTime d, AgendaItem item) {
    final k = daysBetween(from, d);
    if (k < 0 || k >= days) return;
    byDay.putIfAbsent(k, () => []).add(item);
  }

  final todayInRange = !t.isBefore(from) && !t.isAfter(to);

  for (final src in sources) {
    final a = OrgAnalysis(src.text);
    for (final h in a.headingLines) {
      final e = _Entry(src, a, h);
      final info = a.headingInfo(h)!;
      final done = a.todo.isDone(info.keyword);
      final pl = a.planningLine(h);
      final consumed = <int>{};
      if (pl != null) {
        final pline = a.lines[pl];
        final sm = _scheduledRe.firstMatch(pline);
        if (sm != null) {
          final ts = OrgTimestamp.parse(sm.group(1)!);
          if (ts != null) {
            final time = ts.hasTime ? ts.timeString : null;
            final overdue = !done && ts.date.isBefore(t);
            for (final d in ts.occurrences(from, to)) {
              if (overdue && !d.isAfter(t)) continue;
              add(d, e.item(AgendaKind.scheduled, 'Scheduled', time: time, date: d));
            }
            if (overdue && todayInRange) {
              final n = daysBetween(ts.date, t);
              add(t, e.item(AgendaKind.overdueScheduled, 'Sched. ${n}x', time: time, date: t));
            }
          }
        }
        final dm = _deadlineRe.firstMatch(pline);
        if (dm != null) {
          final ts = OrgTimestamp.parse(dm.group(1)!);
          if (ts != null) {
            final time = ts.hasTime ? ts.timeString : null;
            final overdue = !done && ts.date.isBefore(t);
            for (final d in ts.occurrences(from, to)) {
              if (overdue && !d.isAfter(t)) continue;
              add(d, e.item(AgendaKind.deadline, 'Deadline', time: time, date: d));
            }
            if (!done && todayInRange) {
              final n = daysBetween(t, ts.date);
              if (n < 0) {
                add(t, e.item(AgendaKind.overdueDeadline, '${-n} d. ago', time: time, date: t));
              } else if (n > 0 && n <= ts.warningDays(warningDays)) {
                add(t, e.item(AgendaKind.deadlineWarning, 'In $n d.', time: time, date: t));
              }
            }
          }
        }
        consumed.add(pl);
      }
      // Plain active timestamps in the heading and body.
      final end = a.bodyEnd(h);
      for (var l = h; l < end; l++) {
        if (consumed.contains(l)) continue;
        final kind = a.infos[l].kind;
        if (kind == LineKind.blockContent ||
            kind == LineKind.property ||
            kind == LineKind.drawerContent ||
            kind == LineKind.comment) {
          continue;
        }
        final text = a.lines[l];
        if (!text.contains('<')) continue;
        final rangeSpans = <(int, int)>[];
        for (final rm in _rangeRe.allMatches(text)) {
          final s = OrgTimestamp.parse(rm.group(1)!);
          final f = OrgTimestamp.parse(rm.group(2)!);
          if (s == null || f == null || !s.active || !f.active) continue;
          rangeSpans.add((rm.start, rm.end));
          final total = daysBetween(s.date, f.date) + 1;
          for (var i = 0; i < total && i < 1000; i++) {
            final d = addDays(s.date, i);
            if (d.isBefore(from) || d.isAfter(to)) continue;
            final time = i == 0 && s.hasTime ? s.timeString : (i == total - 1 && f.hasTime ? f.timeString : null);
            add(d, e.item(AgendaKind.range, '(${i + 1}/$total)', time: time, date: d));
          }
        }
        for (final (m, ts) in OrgTimestamp.findAll(text)) {
          if (!ts.active) continue;
          if (rangeSpans.any((r) => m.start >= r.$1 && m.end <= r.$2)) continue;
          final time = ts.hasTime ? ts.timeString : null;
          for (final d in ts.occurrences(from, to)) {
            add(d, e.item(AgendaKind.timestamp, '', time: time, date: d));
          }
        }
      }
    }
  }

  final result = <AgendaDay>[];
  for (var k = 0; k < days; k++) {
    final items = byDay[k] ?? [];
    items.sort(_compare);
    result.add(AgendaDay(addDays(from, k), items));
  }
  return result;
}

int _kindRank(AgendaKind k) => switch (k) {
      AgendaKind.overdueDeadline => 0,
      AgendaKind.deadline => 1,
      AgendaKind.deadlineWarning => 2,
      AgendaKind.overdueScheduled => 3,
      AgendaKind.scheduled => 4,
      AgendaKind.range => 5,
      AgendaKind.timestamp => 6,
      AgendaKind.todo => 7,
    };

int _compare(AgendaItem x, AgendaItem y) {
  if (x.time != null && y.time != null) {
    final c = x.time!.compareTo(y.time!);
    if (c != 0) return c;
  } else if (x.time != null) {
    return -1;
  } else if (y.time != null) {
    return 1;
  }
  final k = _kindRank(x.kind).compareTo(_kindRank(y.kind));
  if (k != 0) return k;
  final px = x.priority ?? 'B', py = y.priority ?? 'B';
  return px.compareTo(py);
}

List<AgendaItem> buildTodoList(List<AgendaSource> sources) {
  final result = <AgendaItem>[];
  for (final src in sources) {
    final a = OrgAnalysis(src.text);
    for (final h in a.headingLines) {
      final info = a.headingInfo(h)!;
      if (!a.todo.isTodo(info.keyword)) continue;
      result.add(_Entry(src, a, h).item(AgendaKind.todo, info.keyword!));
    }
  }
  return result;
}

/// Matches an agenda tag/keyword search like "work+urgent-later" or "TODO=\"NEXT\"".
List<AgendaItem> searchHeadings(List<AgendaSource> sources, String query) {
  final q = query.trim().toLowerCase();
  final result = <AgendaItem>[];
  if (q.isEmpty) return result;
  final words = q.split(RegExp(r'\s+'));
  for (final src in sources) {
    final a = OrgAnalysis(src.text);
    for (final h in a.headingLines) {
      final info = a.headingInfo(h)!;
      final hay = '${a.lines[h]} ${info.tags.map((t) => ':$t:').join()}'.toLowerCase();
      final end = a.bodyEnd(h);
      final body = a.lines.sublist(h + 1, end).join('\n').toLowerCase();
      if (words.every((w) => hay.contains(w) || body.contains(w))) {
        result.add(_Entry(src, a, h).item(AgendaKind.todo, info.keyword ?? ''));
      }
    }
  }
  return result;
}
