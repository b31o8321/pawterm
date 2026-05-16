import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../api/protocol.dart';
import '../../state/projects_store.dart';
import '../../state/server_config.dart';
import '../../theme.dart';
import '../../widgets/message_view.dart';

class LocalUserInput extends IncomingMessage {
  final String text;
  LocalUserInput(this.text);
}

/// In-progress assistant message being built char-by-char from stream deltas.
class StreamingAssistant extends IncomingMessage {
  final StringBuffer text = StringBuffer();
  bool stopped = false;
}

class ChatTab extends ConsumerStatefulWidget {
  const ChatTab({super.key});

  @override
  ConsumerState<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<ChatTab> with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  final List<IncomingMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _connected = false;
  bool _busy = false;
  String? _error;
  String? _boundKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel?.sink.close();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // After app comes back to foreground, force reconnect if socket died.
      if (!_connected && _boundKey != null) {
        setState(() {
          _channel?.sink.close();
          _channel = null;
          _boundKey = null;
          _error = null;
        });
      }
    }
  }

  String _sessionKey(CurrentSession s) => '${s.cwd}|${s.resumeId ?? "new"}';

  // Throttle reconnect attempts so a dead server doesn't trigger a tight loop.
  // Once attempted, only the user-visible "reconnect" button will retry.
  String? _attemptedKey;
  bool _attempting = false;

  void _ensureConnected(CurrentSession session) {
    final key = _sessionKey(session);
    if (_boundKey == key && _channel != null) return;
    if (_attemptedKey == key) return; // already tried, don't auto-retry

    _channel?.sink.close();
    _attempting = true;
    _attemptedKey = key;
    setState(() {
      _messages.clear();
      _connected = false;
      _busy = false;
      _error = null;
      _boundKey = key;
    });

    final config = ref.read(activeConnectionProvider);
    if (config == null) {
      _attempting = false;
      return;
    }

    // If resuming an existing session, fetch historical messages first.
    if (session.resumeId != null) {
      _loadHistory(config.httpBase, session.cwd, session.resumeId!);
    }

    final uri = Uri.parse('${config.wsBase}/ws/session');
    try {
      _channel = WebSocketChannel.connect(uri);
    } catch (e) {
      _attempting = false;
      setState(() => _error = '$e');
      return;
    }
    _channel!.stream.listen(_onData, onError: _onError, onDone: _onDone);

    final model = ref.read(currentModelProvider);
    final initMsg = {
      'type': 'init',
      'cwd': session.cwd,
      'permission_mode': 'acceptEdits',
      'model': model.id,
      if (session.resumeId != null) 'resume': session.resumeId,
    };
    _channel!.sink.add(jsonEncode(initMsg));
  }

  void _switchModel(ModelOption m) {
    ref.read(currentModelProvider.notifier).state = m;
    if (_channel != null && _connected) {
      _channel!.sink.add(jsonEncode({'type': 'set_model', 'model': m.id}));
    }
  }

  Future<void> _loadHistory(String httpBase, String cwd, String sessionId) async {
    try {
      final uri = Uri.parse('$httpBase/sessions/$sessionId/messages').replace(
        queryParameters: {'cwd': cwd, 'limit': '200'},
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = (data['messages'] as List?) ?? const [];
      final loaded = <IncomingMessage>[];
      for (final item in raw) {
        final inner = (item as Map<String, dynamic>)['message'];
        if (inner is Map<String, dynamic>) {
          final m = IncomingMessage.fromJson(inner);
          if (m is AssistantMsg || m is UserMsg) loaded.add(m);
        }
      }
      if (!mounted) return;
      setState(() {
        // Prepend so live messages come after history.
        _messages
          ..clear()
          ..addAll(loaded);
      });
      _scrollToEnd();
    } catch (_) {
      // History fetch failure is non-fatal — just skip.
    }
  }

  void _manualReconnect() {
    setState(() {
      _channel?.sink.close();
      _channel = null;
      _boundKey = null;
      _attemptedKey = null;
      _attempting = false;
      _error = null;
    });
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final msg = IncomingMessage.fromJson(json);
    setState(() {
      if (msg is SessionReady) {
        _attempting = false;
        _connected = true;
        _error = null;
      } else if (msg is ResultMsg) {
        _busy = false;
        _messages.add(msg);
      } else if (msg is ErrorMsg) {
        _error = msg.message;
        _messages.add(msg);
      } else if (msg is StreamBlockStart) {
        if (msg.kind == 'text') {
          _messages.add(StreamingAssistant());
        }
      } else if (msg is StreamDelta) {
        if (msg.kind == 'text') {
          // Append to current streaming buffer if exists, else create one.
          final last = _messages.isNotEmpty ? _messages.last : null;
          if (last is StreamingAssistant && !last.stopped) {
            last.text.write(msg.text);
          } else {
            final s = StreamingAssistant()..text.write(msg.text);
            _messages.add(s);
          }
        }
      } else if (msg is StreamBlockStop) {
        final last = _messages.isNotEmpty ? _messages.last : null;
        if (last is StreamingAssistant) last.stopped = true;
      } else if (msg is AssistantMsg) {
        // Final non-streaming assistant message arrives after streaming completes.
        // If we already streamed its text, replace the in-progress block.
        if (_messages.isNotEmpty && _messages.last is StreamingAssistant) {
          _messages.removeLast();
        }
        _messages.add(msg);
      } else if (msg is PongMsg || msg is SystemMsg) {
        // skip
      } else {
        _messages.add(msg);
      }
    });
    _scrollToEnd();
  }

  void _onError(Object e) {
    _attempting = false;
    setState(() {
      _error = e.toString();
      _connected = false;
      _channel = null;
    });
  }

  void _onDone() {
    _attempting = false;
    setState(() {
      _connected = false;
      _busy = false;
      _channel = null;
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  void _submit() {
    final text = _textController.text.trim();
    if (text.isEmpty || !_connected || _busy) return;
    setState(() {
      _messages.add(LocalUserInput(text));
      _busy = true;
      _textController.clear();
    });
    _channel?.sink.add(jsonEncode({'type': 'user_message', 'text': text}));
    _scrollToEnd();
  }

  void _interrupt() {
    if (_busy) _channel?.sink.add(jsonEncode({'type': 'interrupt'}));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return _EmptyState(
        icon: Icons.chat_bubble_outline,
        title: '没有进行中的对话',
        subtitle: '从左上角菜单选择项目，或新建对话',
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureConnected(session);
    });

    return Column(
      children: [
        _StatusRow(
          connected: _connected,
          busy: _busy,
          error: _error,
          onStop: _interrupt,
          onReconnect: _manualReconnect,
        ),
        Divider(color: t.borderSubt, height: 0.5, thickness: 0.5),
        Expanded(
          child: _messages.isEmpty
              ? _EmptyState(
                  icon: Icons.send_outlined,
                  title: _connected ? '开始对话' : '正在连接服务端…',
                  subtitle: _connected ? '下方输入消息' : null,
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    if (m is LocalUserInput) return _UserMessage(text: m.text);
                    if (m is StreamingAssistant) return _StreamingMessage(buffer: m);
                    return MessageView(message: m);
                  },
                ),
        ),
        if (_busy)
          LinearProgressIndicator(
            minHeight: 1.5,
            backgroundColor: t.borderSubt,
            color: t.accent,
          ),
        Divider(color: t.borderSubt, height: 0.5, thickness: 0.5),
        _Composer(
          controller: _textController,
          enabled: _connected && !_busy,
          onSubmit: _submit,
          onSwitchModel: _switchModel,
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final bool connected;
  final bool busy;
  final String? error;
  final VoidCallback onStop;
  final VoidCallback onReconnect;
  const _StatusRow({
    required this.connected,
    required this.busy,
    required this.error,
    required this.onStop,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dotColor = error != null
        ? t.error
        : (connected ? (busy ? t.warning : t.success) : t.textDim);
    final statusText = error != null
        ? 'error'
        : (connected ? (busy ? 'streaming' : 'ready') : 'connecting…');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: t.surface,
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(statusText, style: TextStyle(fontSize: 11, color: t.textMuted)),
          const SizedBox(width: 8),
          Text('·', style: TextStyle(color: t.textDim, fontSize: 11)),
          const SizedBox(width: 8),
          Text(
            'sonnet-4.6',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: t.textMuted),
          ),
          const Spacer(),
          if (busy)
            InkWell(
              onTap: onStop,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.stop_circle_outlined, size: 14, color: t.error),
                    const SizedBox(width: 4),
                    Text('stop',
                        style: TextStyle(fontSize: 11, color: t.error, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            )
          else if (error != null || !connected)
            InkWell(
              onTap: onReconnect,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 14, color: t.accent),
                    const SizedBox(width: 4),
                    Text('reconnect',
                        style: TextStyle(fontSize: 11, color: t.accent, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserMessage extends StatelessWidget {
  final String text;
  const _UserMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final maxW = MediaQuery.of(context).size.width * 0.78;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: SelectableText(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                height: 1.45,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends ConsumerWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;
  final void Function(ModelOption) onSwitchModel;
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
    required this.onSwitchModel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final model = ref.watch(currentModelProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 6,
                  enabled: enabled,
                  cursorColor: t.accent,
                  style: TextStyle(fontSize: 14, color: t.text, height: 1.4),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    hintText: enabled ? 'Ask Claude…' : 'Connecting…',
                    hintStyle: TextStyle(color: t.textDim, fontSize: 14),
                  ),
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: Row(
                  children: [
                    _ToolBtn(
                      icon: Icons.attach_file,
                      tooltip: '附件',
                      enabled: enabled,
                      onTap: () {},
                    ),
                    _ToolBtn(
                      icon: Icons.alternate_email,
                      tooltip: '引用文件',
                      enabled: enabled,
                      onTap: () {},
                    ),
                    _ModelPicker(current: model, onPick: onSwitchModel),
                    const Spacer(),
                    _SendButton(enabled: enabled, onTap: onSubmit),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelPicker extends StatelessWidget {
  final ModelOption current;
  final void Function(ModelOption) onPick;
  const _ModelPicker({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PopupMenuButton<ModelOption>(
      tooltip: '切换模型',
      color: t.surface,
      offset: const Offset(0, -8),
      itemBuilder: (_) => knownModels
          .map(
            (m) => PopupMenuItem<ModelOption>(
              value: m,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.id == current.id)
                    Icon(Icons.check, size: 14, color: t.accent)
                  else
                    const SizedBox(width: 14),
                  const SizedBox(width: 8),
                  Text(m.label, style: TextStyle(color: t.text, fontSize: 13)),
                  const SizedBox(width: 8),
                  Text(m.tier, style: TextStyle(color: t.textDim, fontSize: 10, fontFamily: 'monospace')),
                ],
              ),
            ),
          )
          .toList(),
      onSelected: onPick,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: t.surfaceHi,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 12, color: t.textMuted),
            const SizedBox(width: 6),
            Text(
              current.label,
              style: TextStyle(fontSize: 12, color: t.textMuted, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 14, color: t.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  const _ToolBtn({required this.icon, required this.tooltip, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 22,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: enabled ? t.textMuted : t.textDim),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _SendButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Material(
      color: enabled ? t.accent : t.surfaceHi,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 16,
            color: enabled ? Colors.white : t.textDim,
          ),
        ),
      ),
    );
  }
}

class _StreamingMessage extends StatelessWidget {
  final StreamingAssistant buffer;
  const _StreamingMessage({required this.buffer});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'CLAUDE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: t.accent,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            buffer.text.toString(),
            style: TextStyle(fontSize: 14, color: t.text, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _EmptyState({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: t.textDim),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(fontSize: 14, color: t.textMuted, fontWeight: FontWeight.w500)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(fontSize: 12, color: t.textDim)),
          ],
        ],
      ),
    );
  }
}
