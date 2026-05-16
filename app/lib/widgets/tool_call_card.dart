import 'package:flutter/material.dart';

import '../api/protocol.dart';
import '../theme.dart';
import 'diff_view.dart';

class ToolCallCard extends StatelessWidget {
  final ToolUseBlock toolUse;
  const ToolCallCard({super.key, required this.toolUse});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final color = _colorFor(t, toolUse.name);
    final icon = _iconFor(toolUse.name);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(
          top: BorderSide(color: t.border, width: 0.5),
          right: BorderSide(color: t.border, width: 0.5),
          bottom: BorderSide(color: t.border, width: 0.5),
          left: BorderSide(color: color, width: 3),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Text(
                toolUse.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _summary(t, toolUse.name, toolUse.input)),
              _badge(t, toolUse.name, toolUse.input),
            ],
          ),
          const SizedBox(height: 8),
          _renderBody(context, t, toolUse.name, toolUse.input),
        ],
      ),
    );
  }

  Color _colorFor(AppTokens t, String name) {
    switch (name) {
      case 'Edit':
      case 'Write':
      case 'MultiEdit':
        return t.toolEdit;
      case 'Bash':
        return t.toolBash;
      case 'Read':
        return t.toolRead;
      case 'Grep':
      case 'Glob':
        return t.toolGrep;
      case 'TodoWrite':
        return t.toolTodo;
      case 'WebFetch':
      case 'WebSearch':
        return t.toolWebFetch;
      default:
        return t.textMuted;
    }
  }

  IconData _iconFor(String name) {
    switch (name) {
      case 'Read':
        return Icons.description_outlined;
      case 'Edit':
      case 'MultiEdit':
        return Icons.edit_outlined;
      case 'Write':
        return Icons.note_add_outlined;
      case 'Bash':
        return Icons.terminal;
      case 'Grep':
        return Icons.search;
      case 'Glob':
        return Icons.folder_open_outlined;
      case 'TodoWrite':
        return Icons.checklist;
      case 'WebFetch':
      case 'WebSearch':
        return Icons.public;
      case 'Task':
        return Icons.smart_toy_outlined;
      default:
        return Icons.build_outlined;
    }
  }

  Widget _summary(AppTokens t, String name, Map<String, dynamic> input) {
    String? text;
    switch (name) {
      case 'Edit':
      case 'Write':
      case 'MultiEdit':
      case 'Read':
        text = (input['file_path'] ?? '').toString();
        break;
      case 'Bash':
        text = (input['command'] ?? '').toString();
        break;
      case 'Grep':
        text = (input['pattern'] ?? '').toString();
        break;
      case 'Glob':
        text = (input['pattern'] ?? '').toString();
        break;
      default:
        return const SizedBox.shrink();
    }
    final display = text.contains('/') ? '…/${text.split('/').last}' : text;
    return Text(
      display,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        color: t.textMuted,
      ),
    );
  }

  Widget _badge(AppTokens t, String name, Map<String, dynamic> input) {
    if (name == 'Edit' || name == 'MultiEdit') {
      // try to derive +/- counts from old/new strings
      final oldStr = (input['old_string'] ?? '').toString();
      final newStr = (input['new_string'] ?? '').toString();
      final adds = newStr.isEmpty ? 0 : newStr.split('\n').length;
      final dels = oldStr.isEmpty ? 0 : oldStr.split('\n').length;
      return Text(
        '+$adds −$dels',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: t.textDim,
        ),
      );
    }
    if (name == 'Write') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: t.success.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          'NEW',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: t.success,
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _renderBody(BuildContext context, AppTokens t, String name, Map<String, dynamic> input) {
    switch (name) {
      case 'Edit':
      case 'MultiEdit':
        return DiffView(
          oldString: (input['old_string'] ?? '').toString(),
          newString: (input['new_string'] ?? '').toString(),
        );
      case 'Write':
        return _FilePreview(content: (input['content'] ?? '').toString());
      case 'Bash':
        return _BashLine(command: (input['command'] ?? '').toString());
      case 'Read':
      case 'Grep':
      case 'Glob':
        return const SizedBox.shrink(); // summary line is enough
      case 'TodoWrite':
        return _TodoList(todos: input['todos']);
      default:
        return _KeyValueList(map: input);
    }
  }
}

class _BashLine extends StatelessWidget {
  final String command;
  const _BashLine({required this.command});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.borderSubt, width: 0.5),
      ),
      child: SelectableText(
        '\$ $command',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: t.text,
        ),
      ),
    );
  }
}

class _FilePreview extends StatelessWidget {
  final String content;
  const _FilePreview({required this.content});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final truncated = content.length > 800 ? '${content.substring(0, 800)}\n…' : content;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.borderSubt, width: 0.5),
      ),
      child: SelectableText(
        truncated,
        style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: t.text),
      ),
    );
  }
}

class _KeyValueList extends StatelessWidget {
  final Map<String, dynamic> map;
  const _KeyValueList({required this.map});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: map.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: t.text),
              children: [
                TextSpan(text: '${e.key}: ', style: TextStyle(color: t.textMuted)),
                TextSpan(text: e.value.toString()),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TodoList extends StatelessWidget {
  final dynamic todos;
  const _TodoList({required this.todos});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    if (todos is! List) return Text(todos.toString());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: (todos as List).map((todo) {
        if (todo is! Map) return Text(todo.toString());
        final status = todo['status'] as String? ?? 'pending';
        final content = todo['content']?.toString() ?? '';
        final activeForm = todo['activeForm']?.toString() ?? '';
        final (iconData, color) = switch (status) {
          'completed' => (Icons.check_circle, t.success),
          'in_progress' => (Icons.radio_button_checked, t.accent),
          _ => (Icons.radio_button_unchecked, t.textDim),
        };
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(iconData, size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status == 'in_progress' && activeForm.isNotEmpty ? activeForm : content,
                  style: TextStyle(
                    fontSize: 12,
                    color: status == 'completed' ? t.textDim : t.text,
                    decoration: status == 'completed' ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class ToolResultView extends StatelessWidget {
  final ToolResultBlock toolResult;
  const ToolResultView({super.key, required this.toolResult});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = _extractText(toolResult.content);
    final truncated = text.length > 400 ? '${text.substring(0, 400)}\n…' : text;
    final color = toolResult.isError ? t.error : t.textMuted;
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5)),
      ),
      child: SelectableText(
        truncated,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: toolResult.isError ? t.error : t.textMuted,
          height: 1.5,
        ),
      ),
    );
  }

  String _extractText(dynamic content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is List) {
      return content.map((b) {
        if (b is Map && b['text'] != null) return b['text'].toString();
        return b.toString();
      }).join('\n');
    }
    return content.toString();
  }
}
