import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/projects_store.dart';
import '../../theme.dart';

class GitTab extends ConsumerWidget {
  const GitTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final session = ref.watch(currentSessionProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alt_route, size: 40, color: t.textDim),
            const SizedBox(height: 12),
            Text(
              session == null ? '从左侧选择项目' : 'Git diff / stage / commit',
              style: TextStyle(fontSize: 14, color: t.textMuted, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              '即将上线',
              style: TextStyle(fontSize: 12, color: t.textDim),
            ),
          ],
        ),
      ),
    );
  }
}
