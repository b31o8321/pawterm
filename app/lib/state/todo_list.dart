import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 复刻 claude-code 的 TodoWrite 任务清单模型。
/// 模型通过 TodoWrite 工具增删改这个列表，我们把全部调用 merge 成一个全局状态，
/// 在 UI 上用一条 chip 展示进度，而不是为每次 TodoWrite 工具调用单独显示卡片。
class TodoItem {
  /// 任务正文（imperative，"Run tests"）
  final String content;
  /// 现在进行时（"Running tests"），用于 in_progress 状态显示
  final String activeForm;
  /// pending / in_progress / completed
  final String status;

  const TodoItem({
    required this.content,
    required this.activeForm,
    required this.status,
  });

  factory TodoItem.fromJson(Map<String, dynamic> j) => TodoItem(
        content: j['content']?.toString() ?? '',
        activeForm: j['activeForm']?.toString() ?? '',
        status: j['status']?.toString() ?? 'pending',
      );

  bool get isCompleted => status == 'completed';
  bool get isInProgress => status == 'in_progress';
}

/// 解析 TodoWrite 工具调用 input 的 todos 字段成 TodoItem 列表。
List<TodoItem> parseTodos(dynamic raw) {
  if (raw is! List) return const [];
  final result = <TodoItem>[];
  for (final e in raw) {
    if (e is Map) result.add(TodoItem.fromJson(Map<String, dynamic>.from(e)));
  }
  return result;
}

class TodoListNotifier extends StateNotifier<List<TodoItem>> {
  TodoListNotifier() : super(const []);

  /// 完整替换列表（TodoWrite 每次调用都传完整 todos 数组——它是"覆盖式更新"）。
  /// 同时返回 true 如果实际发生了变化，false 表示无变化（用于 UI 决定要不要做动效）。
  bool replace(List<TodoItem> next) {
    if (_eq(state, next)) return false;
    state = next;
    return true;
  }

  void clear() {
    if (state.isEmpty) return;
    state = const [];
  }

  static bool _eq(List<TodoItem> a, List<TodoItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].content != b[i].content ||
          a[i].activeForm != b[i].activeForm ||
          a[i].status != b[i].status) {
        return false;
      }
    }
    return true;
  }
}

final todoListProvider =
    StateNotifierProvider<TodoListNotifier, List<TodoItem>>((_) => TodoListNotifier());

/// 「上一次 TodoList 内容变更的时间戳」—— 给 UI 的动效用。
/// 每次 replace 成功后 chat_tab 写一下，TodoChip watch 它，在变更瞬间触发 scale/glow。
final todoUpdatedAtProvider = StateProvider<int>((_) => 0);
