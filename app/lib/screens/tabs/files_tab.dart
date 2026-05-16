import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/projects_store.dart';
import '../../theme.dart';

class FilesTab extends ConsumerWidget {
  const FilesTab({super.key});

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
            Icon(Icons.folder_open, size: 40, color: t.textDim),
            const SizedBox(height: 12),
            Text(
              session == null ? '从左侧选择项目' : 'Files（即将上线）',
              style: TextStyle(fontSize: 14, color: t.textMuted, fontWeight: FontWeight.w500),
            ),
            if (session != null) ...[
              const SizedBox(height: 4),
              Text(
                session.cwd,
                style: TextStyle(fontSize: 11, color: t.textDim, fontFamily: 'monospace'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
