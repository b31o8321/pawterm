import 'package:flutter/material.dart';

import '../theme.dart';

class DiffView extends StatelessWidget {
  final String oldString;
  final String newString;
  const DiffView({super.key, required this.oldString, required this.newString});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final addText = isDark ? const Color(0xFF6EE787) : const Color(0xFF14773A);
    final delText = isDark ? const Color(0xFFFF8585) : const Color(0xFFB32A2A);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: t.borderSubt, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._lines(oldString, isAdd: false, bg: t.error.withValues(alpha: 0.08), fg: delText),
          ..._lines(newString, isAdd: true, bg: t.success.withValues(alpha: 0.10), fg: addText),
        ],
      ),
    );
  }

  List<Widget> _lines(String text, {required bool isAdd, required Color bg, required Color fg}) {
    if (text.isEmpty) return const [];
    final prefix = isAdd ? '+ ' : '− ';
    return text.split('\n').map((line) {
      return Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
        child: SelectableText(
          '$prefix$line',
          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: fg, height: 1.4),
        ),
      );
    }).toList();
  }
}
