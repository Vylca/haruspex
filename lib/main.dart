import 'package:flutter/material.dart';

import 'src/app/settings.dart';
import 'src/ui/workspace.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings();
  await settings.load();
  runApp(OrgPadApp(settings: settings, initialFiles: args));
}

class OrgPadApp extends StatelessWidget {
  const OrgPadApp({super.key, required this.settings, required this.initialFiles});

  final AppSettings settings;
  final List<String> initialFiles;

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF0B5CAD), brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: settings.orgTheme(b).selection,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'OrgPad',
        debugShowCheckedModeBanner: false,
        themeMode: settings.themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: Workspace(settings: settings, initialFiles: initialFiles),
      ),
    );
  }
}
