import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/server_config.dart';
import '../theme.dart';
import 'add_connection_sheet.dart';
import 'main_shell.dart';

class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(connectionsProvider);
    final active = ref.watch(activeConnectionProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(onAdd: () => _showAddSheet(context)),
            Expanded(
              child: connections.isEmpty
                  ? _EmptyState(onAdd: () => _showAddSheet(context))
                  : _ConnectionList(connections: connections, active: active),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddConnectionSheet(),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onAdd;
  const _Header({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Connections',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: t.text,
                letterSpacing: -0.4,
              ),
            ),
          ),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: t.accentSubt,
                border: Border.all(color: t.accent.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.add, size: 18, color: t.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.border),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(child: Text('🖥️', style: TextStyle(fontSize: 36))),
            ),
            const SizedBox(height: 20),
            Text(
              '还没有连接',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.text),
            ),
            const SizedBox(height: 8),
            Text(
              '添加一台运行了 Claude Companion Server\n的机器，就能从手机控制它。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: t.textMuted, height: 1.7),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加第一台'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionList extends ConsumerWidget {
  final List<ServerEntry> connections;
  final ServerEntry? active;
  const _ConnectionList({required this.connections, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = connections
        .where((e) => e.lastConnected != null)
        .toList()
      ..sort((a, b) => b.lastConnected!.compareTo(a.lastConnected!));
    final others = connections.where((e) => e.lastConnected == null).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (recent.isNotEmpty) ...[
          _SectionLabel('最近使用'),
          for (final e in recent)
            _ConnCard(entry: e, isActive: e.id == active?.id),
        ],
        if (others.isNotEmpty) ...[
          _SectionLabel(recent.isEmpty ? '全部' : '其他'),
          for (final e in others)
            _ConnCard(entry: e, isActive: e.id == active?.id),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: t.textDim,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _ConnCard extends ConsumerWidget {
  final ServerEntry entry;
  final bool isActive;
  const _ConnCard({required this.entry, required this.isActive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);

    return GestureDetector(
      onTap: () => _connect(context, ref),
      onLongPress: () => _showActions(context, ref),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isActive
              ? Color.lerp(t.surface, t.accent, 0.04)
              : t.surface,
          border: Border.all(
            color: isActive ? t.accent.withValues(alpha: 0.3) : t.border,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _Avatar(emoji: entry.emoji, isActive: isActive),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.url.replaceFirst(RegExp(r'^https?://'), ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                        color: t.textMuted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (isActive)
                          _Tag(label: '已连接', accent: true)
                        else if (entry.lastConnected != null)
                          _Tag(label: '上次 ${_ago(entry.lastConnected!)}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: t.textDim),
            ],
          ),
        ),
      ),
    );
  }

  void _connect(BuildContext context, WidgetRef ref) {
    ref.read(activeConnectionProvider.notifier).state = entry;
    ref.read(connectionsProvider.notifier).touch(entry.id);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: t.textMuted),
              title: Text('编辑', style: TextStyle(color: t.text, fontSize: 15)),
              onTap: () {
                Navigator.pop(ctx);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => AddConnectionSheet(editing: entry),
                );
              },
            ),
            Divider(color: t.borderSubt, height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline, color: t.error),
              title: Text('删除', style: TextStyle(color: t.error, fontSize: 15)),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(connectionsProvider.notifier).remove(entry.id);
                if (ref.read(activeConnectionProvider)?.id == entry.id) {
                  ref.read(activeConnectionProvider.notifier).state = null;
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}m 前';
    if (diff.inDays < 1) return '${diff.inHours}h 前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${(diff.inDays / 7).floor()}周前';
  }
}

class _Avatar extends StatelessWidget {
  final String emoji;
  final bool isActive;
  const _Avatar({required this.emoji, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Stack(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: t.accentSubt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
        ),
        Positioned(
          bottom: -1,
          right: -1,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF22C55E) : t.textDim,
              shape: BoxShape.circle,
              border: Border.all(color: t.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final bool accent;
  const _Tag({required this.label, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: accent ? t.accentSubt : t.surfaceHi,
        border: Border.all(
          color: accent ? t.accent.withValues(alpha: 0.22) : t.border,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: accent ? t.accent : t.textDim,
        ),
      ),
    );
  }
}
