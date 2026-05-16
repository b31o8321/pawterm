// Wire protocol between the Flutter app and the Claude Companion server.

sealed class OutgoingMessage {
  Map<String, dynamic> toJson();
}

class InitMessage extends OutgoingMessage {
  final String cwd;
  final String permissionMode;
  InitMessage({required this.cwd, this.permissionMode = 'acceptEdits'});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'init',
        'cwd': cwd,
        'permission_mode': permissionMode,
      };
}

class UserTextMessage extends OutgoingMessage {
  final String text;
  UserTextMessage(this.text);

  @override
  Map<String, dynamic> toJson() => {'type': 'user_message', 'text': text};
}

class InterruptMessage extends OutgoingMessage {
  @override
  Map<String, dynamic> toJson() => {'type': 'interrupt'};
}

class PingMessage extends OutgoingMessage {
  @override
  Map<String, dynamic> toJson() => {'type': 'ping'};
}

abstract class IncomingMessage {
  static IncomingMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'session_ready':
        return SessionReady(
          sessionKey: json['session_key'] as String? ?? '',
          cwd: json['cwd'] as String? ?? '',
          permissionMode: json['permission_mode'] as String? ?? 'acceptEdits',
        );
      case 'assistant':
        return AssistantMsg(
          model: json['model'] as String?,
          content: ((json['content'] as List?) ?? [])
              .map((b) => ContentBlock.fromJson(Map<String, dynamic>.from(b)))
              .toList(),
        );
      case 'user':
        return UserMsg(
          content: ((json['content'] as List?) ?? [])
              .map((b) => ContentBlock.fromJson(Map<String, dynamic>.from(b)))
              .toList(),
        );
      case 'result':
        return ResultMsg(
          durationMs: (json['duration_ms'] as num?)?.toInt(),
          totalCostUsd: (json['total_cost_usd'] as num?)?.toDouble(),
          sessionId: json['session_id'] as String?,
          numTurns: (json['num_turns'] as num?)?.toInt(),
          isError: (json['is_error'] as bool?) ?? false,
        );
      case 'system':
        return SystemMsg(
          subtype: json['subtype'] as String?,
          data: Map<String, dynamic>.from(json['data'] ?? {}),
        );
      case 'error':
        return ErrorMsg(message: json['message'] as String? ?? 'Unknown error');
      case 'pong':
        return PongMsg();
      case 'stream_block_start':
        return StreamBlockStart(
          index: (json['index'] as num?)?.toInt() ?? 0,
          kind: json['kind'] as String? ?? 'unknown',
        );
      case 'stream_delta':
        return StreamDelta(
          index: (json['index'] as num?)?.toInt() ?? 0,
          kind: json['kind'] as String? ?? 'text',
          text: json['text'] as String? ?? '',
        );
      case 'stream_block_stop':
        return StreamBlockStop(index: (json['index'] as num?)?.toInt() ?? 0);
      default:
        return UnknownMsg(raw: json);
    }
  }
}

class StreamBlockStart extends IncomingMessage {
  final int index;
  final String kind;
  StreamBlockStart({required this.index, required this.kind});
}

class StreamDelta extends IncomingMessage {
  final int index;
  final String kind;
  final String text;
  StreamDelta({required this.index, required this.kind, required this.text});
}

class StreamBlockStop extends IncomingMessage {
  final int index;
  StreamBlockStop({required this.index});
}

class SessionReady extends IncomingMessage {
  final String sessionKey;
  final String cwd;
  final String permissionMode;
  SessionReady({required this.sessionKey, required this.cwd, required this.permissionMode});
}

class AssistantMsg extends IncomingMessage {
  final List<ContentBlock> content;
  final String? model;
  AssistantMsg({required this.content, this.model});
}

class UserMsg extends IncomingMessage {
  final List<ContentBlock> content;
  UserMsg({required this.content});
}

class ResultMsg extends IncomingMessage {
  final int? durationMs;
  final double? totalCostUsd;
  final String? sessionId;
  final int? numTurns;
  final bool isError;
  ResultMsg({this.durationMs, this.totalCostUsd, this.sessionId, this.numTurns, this.isError = false});
}

class SystemMsg extends IncomingMessage {
  final String? subtype;
  final Map<String, dynamic> data;
  SystemMsg({this.subtype, required this.data});
}

class ErrorMsg extends IncomingMessage {
  final String message;
  ErrorMsg({required this.message});
}

class PongMsg extends IncomingMessage {}

class UnknownMsg extends IncomingMessage {
  final Map<String, dynamic> raw;
  UnknownMsg({required this.raw});
}

sealed class ContentBlock {
  static ContentBlock fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'text':
        return TextBlock(text: json['text'] as String? ?? '');
      case 'thinking':
        return ThinkingBlock(text: json['text'] as String? ?? '');
      case 'tool_use':
        return ToolUseBlock(
          id: json['id'] as String? ?? '',
          name: json['name'] as String? ?? '',
          input: Map<String, dynamic>.from(json['input'] ?? {}),
        );
      case 'tool_result':
        return ToolResultBlock(
          toolUseId: json['tool_use_id'] as String? ?? '',
          content: json['content'],
          isError: (json['is_error'] as bool?) ?? false,
        );
      default:
        return UnknownBlock(raw: json);
    }
  }
}

class TextBlock extends ContentBlock {
  final String text;
  TextBlock({required this.text});
}

class ThinkingBlock extends ContentBlock {
  final String text;
  ThinkingBlock({required this.text});
}

class ToolUseBlock extends ContentBlock {
  final String id;
  final String name;
  final Map<String, dynamic> input;
  ToolUseBlock({required this.id, required this.name, required this.input});
}

class ToolResultBlock extends ContentBlock {
  final String toolUseId;
  final dynamic content;
  final bool isError;
  ToolResultBlock({required this.toolUseId, required this.content, required this.isError});
}

class UnknownBlock extends ContentBlock {
  final Map<String, dynamic> raw;
  UnknownBlock({required this.raw});
}
