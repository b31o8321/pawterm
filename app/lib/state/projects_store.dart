import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/sessions_api.dart';
import 'server_config.dart';

class Project {
  final String name;
  final String path;
  const Project({required this.name, required this.path});

  factory Project.fromJson(Map<String, dynamic> json) =>
      Project(name: json['name'] as String, path: json['path'] as String);
}

final projectsProvider = FutureProvider<List<Project>>((ref) async {
  final conn = ref.watch(activeConnectionProvider);
  if (conn == null) return [];
  final resp = await http
      .get(Uri.parse('${conn.httpBase}/projects'))
      .timeout(const Duration(seconds: 5));
  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
  }
  final list = jsonDecode(resp.body) as List;
  return list.map((e) => Project.fromJson(Map<String, dynamic>.from(e))).toList();
});

final selectedProjectProvider = StateProvider<Project?>((ref) => null);

/// Sessions list for a given project path. Family keyed by cwd.
final sessionsProvider = FutureProvider.family<List<SessionSummary>, String>((ref, cwd) async {
  final conn = ref.watch(activeConnectionProvider);
  if (conn == null) return [];
  final api = SessionsApi(conn.httpBase);
  return api.list(cwd);
});

class CurrentSession {
  /// project working directory
  final String cwd;
  /// session_id to resume; null means start a fresh session
  final String? resumeId;
  /// human label shown in app bar
  final String label;
  const CurrentSession({required this.cwd, required this.label, this.resumeId});

  CurrentSession copyWith({String? cwd, String? resumeId, String? label}) =>
      CurrentSession(
        cwd: cwd ?? this.cwd,
        resumeId: resumeId ?? this.resumeId,
        label: label ?? this.label,
      );
}

final currentSessionProvider = StateProvider<CurrentSession?>((ref) => null);

class ModelOption {
  final String id;
  final String label;
  final String tier;
  const ModelOption(this.id, this.label, this.tier);
}

const knownModels = <ModelOption>[
  ModelOption('claude-sonnet-4-6', 'Sonnet 4.6', 'fast'),
  ModelOption('claude-opus-4-7', 'Opus 4.7', 'powerful'),
  ModelOption('claude-haiku-4-5', 'Haiku 4.5', 'cheap'),
];

final currentModelProvider = StateProvider<ModelOption>((ref) => knownModels.first);
