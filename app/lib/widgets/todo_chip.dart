import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/locale_provider.dart';
import '../state/todo_list.dart';
import '../theme.dart';

/// 全局 TodoList 进度 chip：进度 N/M + 当前进行中任务的预览。
/// 点击弹出 bottom sheet 看完整列表。
/// watch 一个"上次更新时间戳"provider，每次变更触发一次轻微 scale/glow 动画。
class TodoChip extends ConsumerStatefulWidget {
  const TodoChip({super.key});

  @override
  ConsumerState<TodoChip> createState() => _TodoChipState();
}

class _TodoChipState extends ConsumerState<TodoChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _scale;
  int _lastSeenUpdate = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    // 1 → 1.12 → 1，平滑回弹
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 60),
    ]).animate(_pulseCtrl);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _maybeAnimate(int currentUpdate) {
    if (currentUpdate == _lastSeenUpdate) return;
    if (_lastSeenUpdate != 0) {
      _pulseCtrl.forward(from: 0);
    }
    _lastSeenUpdate = currentUpdate;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final todos = ref.watch(todoListProvider);
    final updatedAt = ref.watch(todoUpdatedAtProvider);

    // 首屏挂载时 _lastSeenUpdate=0；记下当前值但不动画
    if (_lastSeenUpdate == 0) {
      _lastSeenUpdate = updatedAt;
    } else {
      // 后续每次 build 检查时间戳变动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeAnimate(updatedAt);
      });
    }

    if (todos.isEmpty) return const SizedBox.shrink();
    final done = todos.where((e) => e.isCompleted).length;
    final inProgress = todos.firstWhere(
      (e) => e.isInProgress,
      orElse: () => const TodoItem(content: '', activeForm: '', status: ''),
    );
    final label = s.todoChipTpl
        .replaceAll('{done}', '$done')
        .replaceAll('{total}', '${todos.length}');
    return ScaleTransition(
      scale: _scale,
      child: InkWell(
        onTap: () => _openSheet(context),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: t.accentSubt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.accent.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.checklist, size: 12, color: t.accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: t.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (inProgress.content.isNotEmpty) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    inProgress.activeForm.isNotEmpty
                        ? inProgress.activeForm
                        : inProgress.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: t.accent.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _TodoSheet(),
    );
  }
}

class _TodoSheet extends ConsumerWidget {
  const _TodoSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final todos = ref.watch(todoListProvider);
    final done = todos.where((e) => e.isCompleted).length;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.checklist, size: 16, color: t.accent),
                  const SizedBox(width: 8),
                  Text(
                    s.todoSheetTitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  const Spacer(),
                  if (todos.isNotEmpty)
                    Text(
                      '$done / ${todos.length}',
                      style: TextStyle(
                        fontSize: 11,
                        color: t.textDim,
                        fontFamily: 'monospace',
                      ),
                    ),
                ],
              ),
            ),
            Divider(color: t.borderSubt, height: 0.5),
            Flexible(
              child: todos.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: Text(
                          s.todoEmpty,
                          style: TextStyle(fontSize: 13, color: t.textDim),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: todos.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: t.borderSubt, height: 0.5, indent: 50),
                      itemBuilder: (_, i) => _TodoRow(item: todos[i]),
                    ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _TodoRow extends ConsumerWidget {
  final TodoItem item;
  const _TodoRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final (icon, color) = switch (item.status) {
      'completed' => (Icons.check_circle, t.success),
      'in_progress' => (Icons.radio_button_checked, t.accent),
      _ => (Icons.radio_button_unchecked, t.textDim),
    };
    final statusLabel = switch (item.status) {
      'completed' => s.todoStatusCompleted,
      'in_progress' => s.todoStatusInProgress,
      _ => s.todoStatusPending,
    };
    final text = item.isInProgress && item.activeForm.isNotEmpty
        ? item.activeForm
        : item.content;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: item.isCompleted ? t.textDim : t.text,
                    decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: color.withValues(alpha: 0.8),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
