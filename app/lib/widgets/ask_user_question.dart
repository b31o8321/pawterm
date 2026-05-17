import 'package:flutter/material.dart';

import '../api/protocol.dart';
import '../theme.dart';

class AskUserQuestionWidget extends StatefulWidget {
  final ToolUseBlock toolUse;
  /// 已配对的 tool_result；非空 = answered 态
  final ToolResultBlock? answeredResult;
  /// 提交回调：把答案 + annotations 通过 REST 发回 server
  final void Function(
    String toolUseId,
    Map<String, String> answers,
    Map<String, Map<String, String>>? annotations,
  ) onSubmit;

  const AskUserQuestionWidget({
    super.key,
    required this.toolUse,
    required this.answeredResult,
    required this.onSubmit,
  });

  @override
  State<AskUserQuestionWidget> createState() => _AskUserQuestionWidgetState();
}

class _AskUserQuestionWidgetState extends State<AskUserQuestionWidget> {
  late final List<_Question> _questions;

  @override
  void initState() {
    super.initState();
    _questions = _parseQuestions(widget.toolUse.input);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final answered = widget.answeredResult != null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Opacity(
        opacity: answered ? 0.75 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final q in _questions) ...[
              _QuestionPanel(question: q, readOnly: answered),
              const SizedBox(height: 24),
            ],
            if (answered)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '（已答）',
                  style: TextStyle(color: t.textDim, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Question {
  final String question;
  final String header;
  final bool multiSelect;
  final List<_Option> options;
  _Question({
    required this.question,
    required this.header,
    required this.multiSelect,
    required this.options,
  });
}

class _Option {
  final String label;
  final String description;
  final String? preview;
  _Option({required this.label, required this.description, this.preview});
}

List<_Question> _parseQuestions(Map<String, dynamic> input) {
  final list = (input['questions'] as List?) ?? [];
  return list.map((q) {
    final m = q as Map<String, dynamic>;
    final opts = (m['options'] as List).map((o) {
      final om = o as Map<String, dynamic>;
      return _Option(
        label: om['label'] as String,
        description: om['description'] as String? ?? '',
        preview: om['preview'] as String?,
      );
    }).toList();
    return _Question(
      question: m['question'] as String,
      header: m['header'] as String,
      multiSelect: (m['multiSelect'] as bool?) ?? false,
      options: opts,
    );
  }).toList();
}

class _QuestionPanel extends StatelessWidget {
  final _Question question;
  final bool readOnly;
  const _QuestionPanel({required this.question, required this.readOnly});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // header chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: t.accentSubt,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                question.header,
                style: TextStyle(
                  fontSize: 10,
                  color: t.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                question.question,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 占位：options 渲染（Task 10 将加入点击交互）
        for (final o in question.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surfaceHi,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.label,
                    style: TextStyle(fontSize: 14, color: t.text, fontWeight: FontWeight.w500),
                  ),
                  if (o.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        o.description,
                        style: TextStyle(fontSize: 12, color: t.textMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
