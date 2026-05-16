import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/connections_screen.dart';
import 'theme.dart';

void main() {
  runApp(const ProviderScope(child: CcApp()));
}

class CcApp extends StatelessWidget {
  const CcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Claude Companion',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const ConnectionsScreen(),
    );
  }
}
