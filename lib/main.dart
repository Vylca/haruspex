import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app/settings.dart';
import 'src/editor/org_theme.dart';
import 'src/ui/hev_theme.dart';
import 'src/ui/workspace.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/LICENSE-Spleen.txt');
    yield LicenseEntryWithLineBreaks(const ['Spleen font'], text);
  });
  final settings = AppSettings();
  await settings.load();
  runApp(OrgPadApp(settings: settings, initialFiles: args));
}

class OrgPadApp extends StatelessWidget {
  const OrgPadApp({super.key, required this.settings, required this.initialFiles});

  final AppSettings settings;
  final List<String> initialFiles;

  @override
  Widget build(BuildContext context) {
    final theme = buildHevTheme(OrgTheme.hev);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'OrgPad',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: theme,
        darkTheme: theme,
        home: Workspace(settings: settings, initialFiles: initialFiles),
      ),
    );
  }
}
