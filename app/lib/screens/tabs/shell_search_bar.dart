import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../i18n/locale_provider.dart';
import '../../theme.dart';

/// Chrome ⌘F 风格的终端搜索覆盖条。
///
/// xterm.dart 4.x 把内置 search 抽掉了，但 Buffer.getText() 和
/// TerminalController.setSelection 还在 —— 自己扫一遍 buffer，再用 setSelection
/// 高亮当前匹配。视野滚动复用 terminal.scrollOffsetFromBottom（如果可用）。
class ShellSearchBar extends ConsumerStatefulWidget {
  final Terminal terminal;
  final TerminalController controller;
  final VoidCallback onClose;
  const ShellSearchBar({
    super.key,
    required this.terminal,
    required this.controller,
    required this.onClose,
  });

  @override
  ConsumerState<ShellSearchBar> createState() => _ShellSearchBarState();
}

class _SearchHit {
  final int y; // absolute line index in buffer.lines
  final int startX;
  final int endX;
  const _SearchHit(this.y, this.startX, this.endX);
}

class _ShellSearchBarState extends ConsumerState<ShellSearchBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _caseSensitive = false;
  List<_SearchHit> _hits = const [];
  int _current = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    widget.controller.clearSelection();
    super.dispose();
  }

  void _runSearch(String pattern) {
    if (pattern.isEmpty) {
      setState(() {
        _hits = const [];
        _current = -1;
      });
      widget.controller.clearSelection();
      return;
    }
    final buffer = widget.terminal.buffer;
    final needle = _caseSensitive ? pattern : pattern.toLowerCase();
    final hits = <_SearchHit>[];
    for (var y = 0; y < buffer.lines.length; y++) {
      final line = buffer.lines[y];
      var lineText = line.toString();
      if (!_caseSensitive) lineText = lineText.toLowerCase();
      var from = 0;
      while (true) {
        final idx = lineText.indexOf(needle, from);
        if (idx < 0) break;
        hits.add(_SearchHit(y, idx, idx + needle.length));
        from = idx + needle.length;
        if (from > lineText.length) break;
      }
    }
    setState(() {
      _hits = hits;
      _current = hits.isEmpty ? -1 : 0;
    });
    if (hits.isNotEmpty) _selectHit(0);
  }

  void _selectHit(int i) {
    if (i < 0 || i >= _hits.length) return;
    final hit = _hits[i];
    final base = widget.terminal.buffer.createAnchor(hit.startX, hit.y);
    final extent = widget.terminal.buffer.createAnchor(hit.endX, hit.y);
    widget.controller.setSelection(base, extent);
  }

  void _next() {
    if (_hits.isEmpty) return;
    final n = (_current + 1) % _hits.length;
    setState(() => _current = n);
    _selectHit(n);
  }

  void _prev() {
    if (_hits.isEmpty) return;
    final n = (_current - 1 + _hits.length) % _hits.length;
    setState(() => _current = n);
    _selectHit(n);
  }

  String _counterText(WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    if (_ctrl.text.isEmpty) return '';
    if (_hits.isEmpty) return s.shellSearchNoMatch;
    return s.shellSearchHitCountTpl
        .replaceAll('{n}', '${_current + 1}')
        .replaceAll('{total}', '${_hits.length}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.borderSubt, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: t.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              onChanged: _runSearch,
              onSubmitted: (_) => _next(),
              style: TextStyle(fontSize: 13, color: t.text, fontFamily: 'monospace'),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: s.shellSearchHint,
                hintStyle: TextStyle(color: t.textDim, fontSize: 13),
              ),
            ),
          ),
          if (_ctrl.text.isNotEmpty)
            Text(
              _counterText(ref),
              style: TextStyle(fontSize: 11, color: t.textDim, fontFamily: 'monospace'),
            ),
          const SizedBox(width: 4),
          _BarIcon(
            icon: Icons.text_fields,
            active: _caseSensitive,
            tooltip: s.shellSearchCaseSensitive,
            onTap: () {
              setState(() => _caseSensitive = !_caseSensitive);
              _runSearch(_ctrl.text);
            },
          ),
          _BarIcon(
            icon: Icons.keyboard_arrow_up,
            onTap: _hits.isEmpty ? null : _prev,
          ),
          _BarIcon(
            icon: Icons.keyboard_arrow_down,
            onTap: _hits.isEmpty ? null : _next,
          ),
          _BarIcon(icon: Icons.close, onTap: widget.onClose),
        ],
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String? tooltip;
  final VoidCallback? onTap;
  const _BarIcon({
    required this.icon,
    this.active = false,
    this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final disabled = onTap == null;
    final color = disabled
        ? t.textDim
        : (active ? t.accent : t.textMuted);
    final w = InkResponse(
      onTap: onTap,
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: color),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}
