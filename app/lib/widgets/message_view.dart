import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../api/protocol.dart';
import '../theme.dart';
import 'tool_call_card.dart';

class MessageView extends StatelessWidget {
  final IncomingMessage message;
  const MessageView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final msg = message;

    if (msg is AssistantMsg) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(label: 'CLAUDE', color: t.accent),
            const SizedBox(height: 6),
            ...msg.content.map((b) => _renderBlock(context, b)),
          ],
        ),
      );
    }

    if (msg is UserMsg) {
      // Server-side UserMessage carries tool_result blocks.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: msg.content.map((b) => _renderBlock(context, b)).toList(),
      );
    }

    if (msg is ResultMsg) {
      return _ResultLine(message: msg);
    }

    if (msg is ErrorMsg) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.error.withValues(alpha: 0.4), width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: t.error, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg.message, style: TextStyle(color: t.error, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _renderBlock(BuildContext context, ContentBlock block) {
    final t = AppTokens.of(context);

    if (block is TextBlock) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: MarkdownBody(
          data: block.text,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(color: t.text, fontSize: 13, height: 1.6),
            code: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: t.accent,
              backgroundColor: t.surfaceHi,
            ),
            codeblockDecoration: BoxDecoration(
              color: t.surfaceHi,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: t.border, width: 0.5),
            ),
            codeblockPadding: const EdgeInsets.all(10),
            blockquoteDecoration: BoxDecoration(
              color: t.surfaceHi,
              border: Border(left: BorderSide(color: t.accent, width: 3)),
            ),
            h1: TextStyle(color: t.text, fontSize: 16, fontWeight: FontWeight.w600),
            h2: TextStyle(color: t.text, fontSize: 14, fontWeight: FontWeight.w600),
            h3: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600),
            listBullet: TextStyle(color: t.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    if (block is ThinkingBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border(left: BorderSide(color: t.textDim, width: 2)),
          ),
          child: Text(
            block.text,
            style: TextStyle(
              color: t.textMuted,
              fontStyle: FontStyle.italic,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    if (block is ToolUseBlock) {
      return ToolCallCard(toolUse: block);
    }

    if (block is ToolResultBlock) {
      return ToolResultView(toolResult: block);
    }

    return const SizedBox.shrink();
  }
}

class _Header extends StatelessWidget {
  final String label;
  final Color color;
  const _Header({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _now(),
          style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: t.textDim),
        ),
      ],
    );
  }

  String _now() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

class _ResultLine extends StatelessWidget {
  final ResultMsg message;
  const _ResultLine({required this.message});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final duration = message.durationMs != null ? '${(message.durationMs! / 1000).toStringAsFixed(1)}s' : '-';
    final cost = message.totalCostUsd != null ? '\$${message.totalCostUsd!.toStringAsFixed(4)}' : '-';
    final turns = message.numTurns?.toString() ?? '-';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      child: Row(
        children: [
          Text(
            cost,
            style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: t.textDim),
          ),
          _sep(t),
          Text(duration, style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: t.textDim)),
          _sep(t),
          Text('turn $turns', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: t.textDim)),
        ],
      ),
    );
  }

  Widget _sep(AppTokens t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text('·', style: TextStyle(color: t.textDim, fontSize: 11)),
      );
}
