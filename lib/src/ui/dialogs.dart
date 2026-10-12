import 'package:flutter/material.dart';

import '../org/timestamp.dart';

class TimestampChoice {
  TimestampChoice(this.timestamp);
  final OrgTimestamp? timestamp; // null = remove
}

Future<TimestampChoice?> showTimestampDialog(
  BuildContext context, {
  required String title,
  OrgTimestamp? initial,
  bool active = true,
  bool allowRemove = false,
}) {
  return showDialog<TimestampChoice>(
    context: context,
    builder: (_) => _TimestampDialog(title: title, initial: initial, active: active, allowRemove: allowRemove),
  );
}

class _TimestampDialog extends StatefulWidget {
  const _TimestampDialog({required this.title, required this.initial, required this.active, required this.allowRemove});
  final String title;
  final OrgTimestamp? initial;
  final bool active;
  final bool allowRemove;

  @override
  State<_TimestampDialog> createState() => _TimestampDialogState();
}

class _TimestampDialogState extends State<_TimestampDialog> {
  late DateTime _date = widget.initial?.date ?? dateOnly(DateTime.now());
  late final TextEditingController _time = TextEditingController(text: widget.initial?.timeString ?? '');
  late final TextEditingController _repeat = TextEditingController(text: widget.initial?.repeater ?? '');
  late final TextEditingController _warn = TextEditingController(text: widget.initial?.warning ?? '');
  String? _error;

  @override
  void dispose() {
    _time.dispose();
    _repeat.dispose();
    _warn.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _time.text.trim();
    int? h, m, eh, em;
    if (t.isNotEmpty) {
      final tm = RegExp(r'^(\d{1,2}):(\d{2})(?:-(\d{1,2}):(\d{2}))?$').firstMatch(t);
      if (tm == null) {
        setState(() => _error = 'Time must look like 09:30 or 09:30-11:00');
        return;
      }
      h = int.parse(tm.group(1)!);
      m = int.parse(tm.group(2)!);
      if (tm.group(3) != null) {
        eh = int.parse(tm.group(3)!);
        em = int.parse(tm.group(4)!);
      }
      if (h > 23 || m > 59 || (eh != null && (eh > 23 || em! > 59))) {
        setState(() => _error = 'Invalid time');
        return;
      }
    }
    final rep = _repeat.text.trim();
    if (rep.isNotEmpty && !RegExp(r'^(\.\+|\+\+|\+)\d+[hdwmy](/\d+[hdwmy])?$').hasMatch(rep)) {
      setState(() => _error = 'Repeater must look like +1w, ++1m or .+2d');
      return;
    }
    final warn = _warn.text.trim();
    if (warn.isNotEmpty && !RegExp(r'^--?\d+[hdwmy]$').hasMatch(warn)) {
      setState(() => _error = 'Warning must look like -3d');
      return;
    }
    Navigator.of(context).pop(TimestampChoice(OrgTimestamp(
      active: widget.initial?.active ?? widget.active,
      date: _date,
      hour: h,
      minute: m,
      endHour: eh,
      endMinute: em,
      repeater: rep.isEmpty ? null : rep,
      warning: warn.isEmpty ? null : warn,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final preview = OrgTimestamp(active: widget.initial?.active ?? widget.active, date: _date).format();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CalendarDatePicker(
                initialDate: _date,
                firstDate: DateTime(1900),
                lastDate: DateTime(2200),
                onDateChanged: (d) => setState(() => _date = dateOnly(d)),
              ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _time,
                    decoration: const InputDecoration(labelText: 'Time (optional)', hintText: '09:30 or 09:30-11:00'),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _repeat,
                    decoration: const InputDecoration(labelText: 'Repeat', hintText: '+1w'),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _warn,
                    decoration: const InputDecoration(labelText: 'Warn', hintText: '-3d'),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Text(preview, style: const TextStyle(fontFamily: 'monospace')),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.allowRemove)
          TextButton(
            onPressed: () => Navigator.of(context).pop(TimestampChoice(null)),
            child: const Text('Remove'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}

/// Returns the new tag list, or null when cancelled.
Future<List<String>?> showTagsDialog(BuildContext context, List<String> current, List<String> known) {
  final ctrl = TextEditingController(text: current.join(' '));
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) {
      List<String> parse() => ctrl.text.split(RegExp(r'[\s:]+')).where((t) => t.isNotEmpty).toList();
      return StatefulBuilder(builder: (ctx, setState) {
        final selected = parse().toSet();
        return AlertDialog(
          title: const Text('Tags'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'work urgent', helperText: 'Separate tags with spaces'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => Navigator.of(ctx).pop(parse()),
              ),
              if (known.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in known)
                    FilterChip(
                      label: Text(t),
                      selected: selected.contains(t),
                      onSelected: (on) {
                        final list = parse();
                        if (on) {
                          list.add(t);
                        } else {
                          list.remove(t);
                        }
                        ctrl.text = list.join(' ');
                        setState(() {});
                      },
                    ),
                ]),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(parse()), child: const Text('OK')),
          ],
        );
      });
    },
  );
}

class LinkChoice {
  LinkChoice(this.target, this.description);
  final String target;
  final String description;
}

Future<LinkChoice?> showLinkDialog(BuildContext context, {String target = '', String description = ''}) {
  final t = TextEditingController(text: target);
  final d = TextEditingController(text: description);
  return showDialog<LinkChoice>(
    context: context,
    builder: (ctx) {
      void submit() {
        if (t.text.trim().isEmpty) return;
        Navigator.of(ctx).pop(LinkChoice(t.text.trim(), d.text));
      }

      return AlertDialog(
        title: const Text('Insert link'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: t,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Target',
                hintText: 'https://…, file:notes.org, *Heading, #custom-id',
              ),
              onSubmitted: (_) => submit(),
            ),
            TextField(
              controller: d,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              onSubmitted: (_) => submit(),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: const Text('OK')),
        ],
      );
    },
  );
}

/// Returns the chosen priority letter, '' for none, or null when cancelled.
Future<String?> showPriorityDialog(BuildContext context, List<String> priorities) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Priority'),
      children: [
        for (final p in priorities)
          SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(p), child: Text('[#$p]')),
        SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(''), child: const Text('None')),
      ],
    ),
  );
}

enum SaveChoice { save, discard, cancel }

Future<SaveChoice> askSave(BuildContext context, String name) async {
  final r = await showDialog<SaveChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Unsaved changes'),
      content: Text('Save changes to "$name"?'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(SaveChoice.discard), child: const Text("Don't save")),
        TextButton(onPressed: () => Navigator.of(ctx).pop(SaveChoice.cancel), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(SaveChoice.save), child: const Text('Save')),
      ],
    ),
  );
  return r ?? SaveChoice.cancel;
}

Future<void> showInfo(BuildContext context, String title, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
    ),
  );
}

/// Asks for a line of text; returns null when cancelled.
Future<String?> showTextPrompt(BuildContext context, {required String title, String initial = '', String? label}) {
  final ctrl = TextEditingController(text: initial);
  ctrl.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

Future<bool> showConfirm(BuildContext context, {required String title, required String message, String ok = 'OK'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}
