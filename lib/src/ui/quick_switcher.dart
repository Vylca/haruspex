import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/vault.dart';
import '../editor/org_theme.dart';
import 'pixel_widgets.dart';

/// Result of the quick switcher: an existing note, or a name to create.
class SwitcherChoice {
  SwitcherChoice.open(this.path) : create = null;
  SwitcherChoice.create(this.create) : path = null;
  final String? path;
  final String? create;
}

Future<SwitcherChoice?> showQuickSwitcher(BuildContext context, Vault vault) =>
    showDialog<SwitcherChoice>(context: context, builder: (_) => _QuickSwitcher(vault: vault));

class _QuickSwitcher extends StatefulWidget {
  const _QuickSwitcher({required this.vault});
  final Vault vault;

  @override
  State<_QuickSwitcher> createState() => _QuickSwitcherState();
}

class _QuickSwitcherState extends State<_QuickSwitcher> {
  final TextEditingController _q = TextEditingController();
  int _selected = 0;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// Subsequence match score; lower is better, null means no match.
  static int? _score(String query, String candidate) {
    if (query.isEmpty) return candidate.length;
    final q = query.toLowerCase(), c = candidate.toLowerCase();
    final name = c.contains('/') ? c.substring(c.lastIndexOf('/') + 1) : c;
    if (name.startsWith(q)) return name.length;
    if (c.contains(q)) return 100 + c.indexOf(q);
    var i = 0, gaps = 0, last = -1;
    for (var j = 0; j < c.length && i < q.length; j++) {
      if (c[j] == q[i]) {
        if (last >= 0) gaps += j - last - 1;
        last = j;
        i++;
      }
    }
    return i == q.length ? 1000 + gaps : null;
  }

  List<String> get _matches {
    final q = _q.text.trim();
    final scored = <(int, String)>[];
    for (final n in widget.vault.notes) {
      final rel = stripNoteExtension(widget.vault.relative(n));
      final s = _score(q, rel);
      if (s != null) scored.add((s, n));
    }
    scored.sort((x, y) => x.$1 != y.$1 ? x.$1.compareTo(y.$1) : x.$2.compareTo(y.$2));
    return [for (final s in scored.take(200)) s.$2];
  }

  void _submit() {
    final m = _matches;
    if (m.isNotEmpty) {
      Navigator.of(context).pop(SwitcherChoice.open(m[_selected.clamp(0, m.length - 1)]));
    } else if (_q.text.trim().isNotEmpty) {
      Navigator.of(context).pop(SwitcherChoice.create(_q.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final t = OrgTheme.hev;
    final query = _q.text.trim();
    return Dialog(
      alignment: const Alignment(0, -0.7),
      child: SizedBox(
        width: 600,
        height: 420,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
            child: Row(children: [
              Text('Find note: ', style: TextStyle(color: t.accent)),
              Expanded(
                child: Focus(
                  onKeyEvent: (node, e) {
                    if (e is KeyUpEvent) return KeyEventResult.ignored;
                    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                      setState(() => _selected = (_selected + 1).clamp(0, matches.isEmpty ? 0 : matches.length - 1));
                      return KeyEventResult.handled;
                    }
                    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                      setState(() => _selected = (_selected - 1).clamp(0, matches.isEmpty ? 0 : matches.length - 1));
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _q,
                    autofocus: true,
                    style: TextStyle(color: t.text),
                    decoration: const InputDecoration.collapsed(hintText: ''),
                    onChanged: (_) => setState(() => _selected = 0),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ),
              Text('${matches.length}/${widget.vault.notes.length}', style: TextStyle(color: t.faint)),
            ]),
          ),
          Expanded(
            child: matches.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      query.isEmpty ? 'No notes in this vault' : 'Enter creates "$query"',
                      style: TextStyle(color: t.faint),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    itemCount: matches.length,
                    itemBuilder: (context, i) {
                      final rel = widget.vault.relative(matches[i]);
                      final name = stripNoteExtension(baseName(rel));
                      final folder = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
                      final selected = i == _selected;
                      return HoverBox(
                        theme: t,
                        onTap: () => Navigator.of(context).pop(SwitcherChoice.open(matches[i])),
                        builder: (hot) {
                          final on = hot || selected;
                          return Container(
                            color: selected && !hot ? t.accent : null,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(children: [
                              Expanded(
                                child: Text(name,
                                    overflow: TextOverflow.ellipsis, style: TextStyle(color: on ? Colors.black : t.text)),
                              ),
                              if (folder.isNotEmpty)
                                Text(folder, style: TextStyle(color: on ? Colors.black : t.faint)),
                            ]),
                          );
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
