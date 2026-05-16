import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'i18n/locale_provider.dart';
import 'screens/connections_screen.dart';
import 'state/prefs.dart';
import 'theme.dart';

void main() {
  runApp(const ProviderScope(child: CcApp()));
}

class CcApp extends ConsumerWidget {
  const CcApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(prefsProvider);
    final locale = ref.watch(materialLocaleProvider);
    return MaterialApp(
      title: 'Claude Companion',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: const ConnectionsScreen(),
    );
  }
}
