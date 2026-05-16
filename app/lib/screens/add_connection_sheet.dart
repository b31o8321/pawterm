import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../state/server_config.dart';
import '../theme.dart';

const _emojis = ['🖥️', '💻', '☁️', '🌐', '🏢', '🚀', '⚡', '🔧'];

enum _SheetState { input, detecting, detected, error }

class AddConnectionSheet extends ConsumerStatefulWidget {
  final ServerEntry? editing;
  const AddConnectionSheet({super.key, this.editing});

  @override
  ConsumerState<AddConnectionSheet> createState() => _AddConnectionSheetState();
}

class _AddConnectionSheetState extends ConsumerState<AddConnectionSheet> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _nameCtrl;
  late String _emoji;

  _SheetState _phase = _SheetState.input;
  String? _detectedName;
  String? _detectedVersion;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _urlCtrl = TextEditingController(
        text: e != null ? e.url.replaceFirst(RegExp(r'^https?://'), '') : '');
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _emoji = e?.emoji ?? '🖥️';
    if (e != null) _phase = _SheetState.detected;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  String get _normalizedUrl {
    var v = _urlCtrl.text.trim();
    if (v.isEmpty) return '';
    if (!v.startsWith('http')) v = 'http://$v';
    // default port
    final uri = Uri.tryParse(v);
    if (uri != null && uri.port == 0) {
      v = '${uri.scheme}://${uri.host}:8765${uri.path}';
    }
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  Future<void> _detect() async {
    final url = _normalizedUrl;
    if (url.isEmpty) return;

    setState(() {
      _phase = _SheetState.detecting;
      _errorMsg = null;
    });

    try {
      final res = await http
          .get(Uri.parse('$url/health'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final hostname = body['hostname'] as String? ?? url;
        final version = body['version'] as String? ?? '';
        setState(() {
          _detectedName = hostname;
          _detectedVersion = version;
          _nameCtrl.text = hostname;
          _phase = _SheetState.detected;
        });
      } else {
        setState(() {
          _errorMsg = '服务端返回 ${res.statusCode}';
          _phase = _SheetState.error;
        });
      }
    } catch (e) {
      setState(() {
        _errorMsg = '无法连接，请检查地址和端口';
        _phase = _SheetState.error;
      });
    }
  }

  Future<void> _save() async {
    final url = _normalizedUrl;
    final name = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : (_detectedName ?? url);
    final notifier = ref.read(connectionsProvider.notifier);
    if (widget.editing != null) {
      await notifier.update(widget.editing!.copyWith(
        name: name,
        emoji: _emoji,
        url: url,
      ));
    } else {
      await notifier.add(name: name, emoji: _emoji, url: url);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: t.border),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.editing != null ? '编辑连接' : '添加连接',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.text),
            ),
            const SizedBox(height: 20),

            // URL field
            _Label('服务端地址'),
            TextField(
              controller: _urlCtrl,
              enabled: _phase == _SheetState.input ||
                  _phase == _SheetState.error ||
                  widget.editing != null,
              keyboardType: TextInputType.url,
              style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: t.text),
              decoration: InputDecoration(
                hintText: '192.168.1.x 或 域名',
                suffixText: ':8765',
                suffixStyle: TextStyle(color: t.textDim, fontFamily: 'monospace', fontSize: 12),
              ),
              onSubmitted: (_) {
                if (_phase == _SheetState.input || _phase == _SheetState.error) _detect();
              },
            ),
            const SizedBox(height: 6),
            Text(
              '端口默认 8765，可写 IP:端口 指定其他端口',
              style: TextStyle(fontSize: 11, color: t.textDim),
            ),
            const SizedBox(height: 16),

            // Detecting indicator
            if (_phase == _SheetState.detecting) ...[
              Row(children: [
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
                ),
                const SizedBox(width: 10),
                Text('正在连接并识别服务端…',
                    style: TextStyle(fontSize: 13, color: t.textMuted)),
              ]),
              const SizedBox(height: 20),
            ],

            // Error
            if (_phase == _SheetState.error && _errorMsg != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: t.error.withValues(alpha: 0.08),
                  border: Border.all(color: t.error.withValues(alpha: 0.25)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.error_outline, size: 14, color: t.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_errorMsg!, style: TextStyle(fontSize: 12, color: t.error))),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            // Detected result + name + emoji
            if (_phase == _SheetState.detected) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.07),
                  border: Border.all(color: t.accent.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.check_circle_outline, size: 14, color: t.accent),
                  const SizedBox(width: 8),
                  Text(
                    '已识别${_detectedVersion != null ? '，v$_detectedVersion' : ''}',
                    style: TextStyle(fontSize: 12, color: t.accent),
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              _Label('名称'),
              TextField(
                controller: _nameCtrl,
                style: TextStyle(fontSize: 14, color: t.text),
                decoration: const InputDecoration(hintText: '可修改昵称'),
              ),
              const SizedBox(height: 16),

              _Label('图标'),
              _EmojiPicker(
                selected: _emoji,
                onSelect: (e) => setState(() => _emoji = e),
              ),
              const SizedBox(height: 20),
            ],

            // Actions
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: BorderSide(color: t.border),
                    foregroundColor: t.textMuted,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('取消', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _phase == _SheetState.detecting
                      ? null
                      : _phase == _SheetState.detected
                          ? _save
                          : _detect,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    _phase == _SheetState.detected ? '保存' : '连接',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: t.textMuted)),
    );
  }
}

class _EmojiPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _EmojiPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _emojis.map((e) {
        final isSelected = e == selected;
        return GestureDetector(
          onTap: () => onSelect(e),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isSelected ? t.accentSubt : t.surfaceHi,
              border: Border.all(
                color: isSelected ? t.accent.withValues(alpha: 0.5) : t.border,
                width: isSelected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(e, style: const TextStyle(fontSize: 20))),
          ),
        );
      }).toList(),
    );
  }
}
