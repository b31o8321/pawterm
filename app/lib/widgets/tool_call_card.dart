import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/protocol.dart';
import '../theme.dart';
import 'diff_view.dart';

/// 工具调用卡片 — 把 ToolUseBlock 和它对应的 ToolResultBlock（按 id 配对）
/// 合并成一个折叠卡。
///
/// 折叠态：单行 [icon] [name] [summary] [✓/✗/⏳]  [▾]
/// 展开态：分两段
///   Input  — 调用参数（diff/命令/键值对……）
///   Output — 工具返回（文本，>4000 字符截断）
class ToolCallCard extends StatefulWidget {
  final ToolUseBlock toolUse;
  /// 可选：和这次调用匹配的结果（通过 tool_use_id 配对）。null 表示尚未返回。
  final ToolResultBlock? result;

  const ToolCallCard({super.key, required this.toolUse, this.result});

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  /// 默认折叠：消息流里大量工具调用展开会噪音很大；想看细节再点。
  bool _expanded = false;

  ToolUseBlock get toolUse => widget.toolUse;
  ToolResultBlock? get result => widget.result;

  @override
  Widget build(BuildContext context) {
    // TodoWrite 工具调用：交给顶部全局 TodoChip 展示，消息流里不显示卡片。
    if (toolUse.name == 'TodoWrite') return const SizedBox.shrink();

    final t = AppTokens.of(context);
    final color = _colorFor(t, toolUse.name);
    final icon = _iconFor(toolUse.name);
    // 所有工具都允许展开（即使 input 为空，也能看 output）。
    final hasInputBody = !_isBodyEmpty(toolUse.name);
    final hasOutput = result != null;
    final canExpand = hasInputBody || hasOutput;

    return InkWell(
      onTap: canExpand ? () => setState(() => _expanded = !_expanded) : null,
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(6),
        bottomRight: Radius.circular(6),
      ),
      child: Container(
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
                _statusBadge(t),
                if (canExpand) ...[
                  const SizedBox(width: 6),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: t.textDim,
                  ),
                ],
              ],
            ),
            if (_expanded && canExpand) ...[
              const SizedBox(height: 10),
              if (hasInputBody) ...[
                _SectionLabel('Input', t),
                const SizedBox(height: 4),
                _renderBody(context, t, toolUse.name, toolUse.input),
              ],
              if (hasOutput) ...[
                if (hasInputBody) const SizedBox(height: 10),
                _SectionLabel('Output', t),
                const SizedBox(height: 4),
                _outputBody(t, result!),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// 状态徽章：折叠态下显示 ⏳ running / ✓ done / ✗ error。
  /// 它取代了原来的"+adds −dels"和"NEW"徽章 — 那些细节展开后再看。
  Widget _statusBadge(AppTokens t) {
    if (result == null) {
      return SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: t.textDim,
        ),
      );
    }
    if (result!.isError) {
      return Icon(Icons.close_rounded, size: 14, color: t.error);
    }
    return Icon(Icons.check_rounded, size: 14, color: t.success);
  }

  Widget _outputBody(AppTokens t, ToolResultBlock r) {
    final text = _extractText(r.content);
    final truncated = text.length > 4000 ? '${text.substring(0, 4000)}\n…(truncated)' : text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: r.isError ? t.error.withValues(alpha: 0.3) : t.borderSubt,
          width: 0.5,
        ),
      ),
      child: SelectableText(
        truncated,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: r.isError ? t.error : t.textMuted,
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

  /// 是否有 input body 可展示。除少数没有 input 的工具，绝大多数都有；
  /// Read/Grep/Glob 之前被特例化为"空"，但展开态应当能看到完整参数，所以一律 false。
  bool _isBodyEmpty(String name) => false;

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
      // Read / Grep / Glob 直接走 _KeyValueList（default 分支），展示完整参数。
      case 'TodoWrite':
        return _TodoList(todos: input['todos']);
      default:
        final hasNested = input.values.any((v) => v is Map || v is List);
        return hasNested
            ? _JsonBlock(value: input)
            : _KeyValueList(map: input);
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final AppTokens tokens;
  const _SectionLabel(this.text, this.tokens);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
        color: tokens.textDim,
      ),
    );
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

/// Pretty-JSON 代码块。用于嵌套结构（Map/List）的 tool input / 通用对象展示。
/// 与 _outputBody 相同的视觉规格（黑底 + monospace + textMuted）。
class _JsonBlock extends StatelessWidget {
  final Object? value;
  const _JsonBlock({required this.value});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    const enc = JsonEncoder.withIndent('  ');
    // jsonEncode 对非 JSON-safe 值（如 DateTime）会抛；保护一下
    String text;
    try {
      text = enc.convert(value);
    } catch (_) {
      text = value.toString();
    }
    final truncated = text.length > 4000 ? '${text.substring(0, 4000)}\n…(truncated)' : text;
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
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: t.textMuted,
          height: 1.5,
        ),
      ),
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

class ToolResultView extends StatefulWidget {
  final ToolResultBlock toolResult;
  const ToolResultView({super.key, required this.toolResult});

  @override
  State<ToolResultView> createState() => _ToolResultViewState();
}

class _ToolResultViewState extends State<ToolResultView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = _extractText(widget.toolResult.content);
    final firstLine = _firstLine(text);
    final hasMore = text.length > firstLine.length;
    final preview = (_expanded
            ? (text.length > 4000 ? '${text.substring(0, 4000)}\n…(truncated)' : text)
            : firstLine);
    final color = widget.toolResult.isError ? t.error : t.textMuted;

    return InkWell(
      onTap: hasMore ? () => setState(() => _expanded = !_expanded) : null,
      child: Container(
        margin: const EdgeInsets.only(top: 2, bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                preview,
                maxLines: _expanded ? null : 1,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: widget.toolResult.isError ? t.error : t.textMuted,
                  height: 1.5,
                ),
              ),
            ),
            if (hasMore) ...[
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: t.textDim,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _firstLine(String text) {
    final newline = text.indexOf('\n');
    if (newline < 0) return text;
    return text.substring(0, newline);
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
