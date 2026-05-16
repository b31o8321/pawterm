import 'package:flutter/material.dart';

import '../theme.dart';

/// Full-screen Git view, pushed from Drawer per-project.
/// Currently a placeholder; wire real diff/stage/commit later.
class GitPage extends StatelessWidget {
  final String cwd;
  final String name;
  const GitPage({super.key, required this.cwd, required this.name});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Git', style: TextStyle(fontSize: 14, color: t.text)),
            Text(
              name,
              style: TextStyle(fontSize: 11, color: t.textMuted, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: t.text, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () {},
            child: Text('Stage All', style: TextStyle(color: t.accent, fontSize: 13)),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.alt_route, size: 40, color: t.textDim),
              const SizedBox(height: 12),
              Text(
                'Git diff / stage / commit',
                style: TextStyle(fontSize: 14, color: t.textMuted, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                cwd,
                style: TextStyle(fontSize: 11, color: t.textDim, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 16),
              Text(
                '即将上线',
                style: TextStyle(fontSize: 11, color: t.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
