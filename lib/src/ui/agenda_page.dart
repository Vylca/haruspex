import 'package:flutter/material.dart';

import '../editor/org_theme.dart';
import '../org/agenda.dart';
import '../org/timestamp.dart';
import 'pixel_widgets.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// Agenda: week view, global TODO list and a heading search.
class AgendaPage extends StatefulWidget {
  const AgendaPage({
    super.key,
    required this.sources,
    required this.onCycleTodo,
    required this.theme,
  });

  final List<AgendaSource> Function() sources;
  final Future<void> Function(AgendaItem item) onCycleTodo;
  final OrgTheme theme;

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  late DateTime _weekStart = _mondayOf(DateTime.now());
  int _span = 7;
  String _search = '';
  final _searchCtrl = TextEditingController();

  static DateTime _mondayOf(DateTime d) => addDays(dateOnly(d), -(d.weekday - 1));

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _textButton(String label, String tip, VoidCallback onTap) => HoverBox(
        theme: widget.theme,
        onTap: onTap,
        tooltip: tip,
        builder: (hot) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(label, style: TextStyle(color: hot ? Colors.black : widget.theme.accent)),
        ),
      );

  Future<void> _cycle(AgendaItem item) async {
    await widget.onCycleTodo(item);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: widget.theme.background,
        appBar: AppBar(
          title: const Text('*Org Agenda*'),
          leading: Center(child: _textButton('<', 'Back', () => Navigator.of(context).maybePop())),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(24),
            child: SizedBox(
              height: 24,
              child: TabBar(tabs: [Tab(text: 'Week'), Tab(text: 'TODO list'), Tab(text: 'Search')]),
            ),
          ),
        ),
        body: TabBarView(children: [_weekView(), _todoView(), _searchView()]),
      ),
    );
  }

  Widget _weekView() {
    final today = dateOnly(DateTime.now());
    final days = buildAgenda(widget.sources(), _weekStart, _span, today: today);
    final end = addDays(_weekStart, _span - 1);
    final children = <Widget>[];
    for (final d in days) {
      final isToday = d.date == today;
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(
          '${_dayNames[d.date.weekday - 1]} ${d.date.day} ${_monthNames[d.date.month - 1]} ${d.date.year}'
          '${isToday ? '  ·  today' : ''}',
          style: TextStyle(color: isToday ? widget.theme.accent : widget.theme.levels[1]),
        ),
      ));
      for (final item in d.items) {
        children.add(_itemTile(item, showTime: true));
      }
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          _textButton('<', 'Previous', () => setState(() => _weekStart = addDays(_weekStart, -_span))),
          _textButton('today', 'Today', () => setState(() => _weekStart = _span == 1 ? today : _mondayOf(today))),
          _textButton('>', 'Next', () => setState(() => _weekStart = addDays(_weekStart, _span))),
          const SizedBox(width: 8),
          Text(_span == 1
              ? '${_weekStart.day} ${_monthNames[_weekStart.month - 1]}'
              : '${_weekStart.day} ${_monthNames[_weekStart.month - 1]} – ${end.day} ${_monthNames[end.month - 1]} ${end.year}'),
          const Spacer(),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('Day')),
              ButtonSegment(value: 7, label: Text('Week')),
            ],
            selected: {_span},
            onSelectionChanged: (s) => setState(() {
              _span = s.first;
              _weekStart = _span == 1 ? today : _mondayOf(today);
            }),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: ListView(children: children)),
    ]);
  }

  Widget _todoView() {
    final items = buildTodoList(widget.sources());
    if (items.isEmpty) return const Center(child: Text('No open TODO entries'));
    return ListView(children: [for (final i in items) _itemTile(i, showTime: false)]);
  }

  Widget _searchView() {
    final items = _search.isEmpty ? const <AgendaItem>[] : searchHeadings(widget.sources(), _search);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _searchCtrl,
          autofocus: false,
          decoration: const InputDecoration(hintText: 'Words, :tags: or keywords'),
          onChanged: (v) => setState(() => _search = v),
        ),
      ),
      Expanded(child: ListView(children: [for (final i in items) _itemTile(i, showTime: false)])),
    ]);
  }

  Widget _itemTile(AgendaItem item, {required bool showTime}) {
    final t = widget.theme;
    final labelColor = switch (item.kind) {
      AgendaKind.overdueDeadline || AgendaKind.deadline => t.todo,
      AgendaKind.deadlineWarning => t.priority,
      AgendaKind.overdueScheduled => t.priority,
      _ => t.faint,
    };
    return HoverBox(
      theme: t,
      onTap: () => Navigator.of(context).pop(item),
      builder: (hot) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
            width: 120,
            child: Text(
              item.sourceName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: hot ? Colors.black : t.faint),
            ),
          ),
          if (showTime)
            SizedBox(
              width: 96,
              child: Text(item.time ?? '', style: TextStyle(color: hot ? Colors.black : t.text)),
            ),
          if (showTime)
            SizedBox(
              width: 92,
              child: Text(item.label, style: TextStyle(color: hot ? Colors.black : labelColor)),
            ),
          if (item.keyword != null) ...[
            Text(
              item.keyword!,
              style: TextStyle(fontWeight: FontWeight.w700, color: hot ? Colors.black : (item.done ? t.done : t.todo)),
            ),
            const SizedBox(width: 8),
          ],
          if (item.priority != null) ...[
            Text('[#${item.priority}]', style: TextStyle(color: hot ? Colors.black : t.priority)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              item.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: hot ? Colors.black : (item.done ? t.faint : t.text),
                decoration: item.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (item.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(':${item.tags.join(':')}:', style: TextStyle(color: hot ? Colors.black : t.tag)),
            ),
          const SizedBox(width: 8),
          _textButton(item.done ? '[x]' : '[ ]', 'Cycle TODO state', () => _cycle(item)),
        ]),
      ),
    );
  }
}
