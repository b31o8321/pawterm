import 'dart:convert';

import 'package:http/http.dart' as http;

class ChatStartResponse {
  final String sessionId;
  final String cwd;
  final String permissionMode;
  final String? resumed;
  ChatStartResponse({
    required this.sessionId,
    required this.cwd,
    required this.permissionMode,
    this.resumed,
  });
  factory ChatStartResponse.fromJson(Map<String, dynamic> j) => ChatStartResponse(
        sessionId: j['session_id'] as String,
        cwd: j['cwd'] as String,
        permissionMode: j['permission_mode'] as String,
        resumed: j['resumed'] as String?,
      );
}

class ChatApiException implements Exception {
  final int status;
  final String message;
  ChatApiException(this.status, this.message);
  @override
  String toString() => 'ChatApiException($status): $message';
}

/// REST 客户端：与 chat-rest.ts 一一对应。
/// SSE 事件流是另一条 socket（见 SseClient），不在此类中处理。
class ChatApi {
  final String httpBase;
  ChatApi(this.httpBase);

  Future<ChatStartResponse> start({
    required String cwd,
    String? permissionMode,
    String? resume,
    String? model,
  }) async {
    final resp = await http.post(
      Uri.parse('$httpBase/chat/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'cwd': cwd,
        if (permissionMode != null) 'permission_mode': permissionMode,
        if (resume != null) 'resume': resume,
        if (model != null) 'model': model,
      }),
    );
    if (resp.statusCode != 200) {
      throw ChatApiException(resp.statusCode, resp.body);
    }
    return ChatStartResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> sendMessage(String sessionId, String text) async {
    final resp = await http.post(
      Uri.parse('$httpBase/chat/$sessionId/message'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (resp.statusCode != 200) {
      throw ChatApiException(resp.statusCode, resp.body);
    }
  }

  Future<void> answerQuestion(
    String sessionId,
    String toolUseId,
    Map<String, String> answers,
    Map<String, Map<String, String>>? annotations,
  ) async {
    final resp = await http.post(
      Uri.parse('$httpBase/chat/$sessionId/answer-question'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tool_use_id': toolUseId,
        'answers': answers,
        if (annotations != null) 'annotations': annotations,
      }),
    );
    if (resp.statusCode != 200) {
      throw ChatApiException(resp.statusCode, resp.body);
    }
  }

  Future<void> interrupt(String sessionId) async {
    await http.post(Uri.parse('$httpBase/chat/$sessionId/interrupt'));
  }

  Future<void> setModel(String sessionId, String model) async {
    await http.post(
      Uri.parse('$httpBase/chat/$sessionId/set-model'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'model': model}),
    );
  }

  Future<void> setPermissionMode(String sessionId, String mode) async {
    await http.post(
      Uri.parse('$httpBase/chat/$sessionId/set-permission-mode'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'mode': mode}),
    );
  }

  Future<void> close(String sessionId) async {
    await http.delete(Uri.parse('$httpBase/chat/$sessionId'));
  }
}
