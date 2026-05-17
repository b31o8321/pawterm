import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/files_api.dart';
import '../../i18n/locale_provider.dart';
import '../../i18n/strings.dart';
import '../../state/projects_store.dart';
import '../../state/server_config.dart';
import '../../theme.dart';

class FilesTab extends ConsumerStatefulWidget {
  const FilesTab({super.key});

  @override
  ConsumerState<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends ConsumerState<FilesTab> {
  String? _path;
  String? _rootPath; // 起始 cwd，用作面包屑相对根 + 决定 "上级" 是否可用
  List<FsEntry> _entries = const [];
  bool _loading = false;
  String? _error;

  /// 进程内目录缓存：path → 上次 ls 的结果。
  /// 进入已访问的目录优先用缓存秒开，同时后台异步刷新；用户下拉/点刷新强制 bypass。
  final Map<String, FsListing> _cache = {};

  String _sessionKey(CurrentSession s) => s.cwd;

  void _initIfNeeded(CurrentSession session) {
    if (_path != null && _rootPath == _sessionKey(session)) return;
    _rootPath = _sessionKey(session);
    _path = session.cwd;
    _ls(session.cwd);
  }

  /// 进入目录。
  /// - [force] = false：优先用 cache 秒开，并后台 refresh
  /// - [force] = true：bypass cache，强制重新拉取（下拉刷新 / 显式点刷新）
  Future<void> _ls(String path, {bool force = false}) async {
    final conn = ref.read(activeConnectionProvider);
    if (conn == null) return;

    // 走缓存：立即把 cached entries 显示出来，loading 仅在 cache miss 才置 true
    final cached = !force ? _cache[path] : null;
    setState(() {
      if (cached != null) {
        _path = cached.path;
        _entries = cached.entries;
        _loading = false;
      } else {
        _path = path;
        _entries = const [];
        _loading = true;
      }
      _error = null;
    });

    try {
      final api = FilesApi(conn.httpBase);
      final listing = await api.ls(path);
      if (!mounted) return;
      _cache[listing.path] = listing;
      // 如果用户已经跳到别的目录，不要回填覆盖
      if (_path != listing.path && _path != path) return;
      setState(() {
        _path = listing.path;
        _entries = listing.entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // cache hit 的情况下网络失败不显示错误（保留旧内容），cache miss 才报错
      if (cached == null) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  String _humanPath(String path) {
    return path.replaceFirst(RegExp(r'^/Users/[^/]+'), '~');
  }

  Future<void> _onTapFile(FsEntry entry) async {
    final s = ref.read(stringsProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DownloadConfirmDialog(entry: entry, strings: s),
    );
    if (confirm != true || !mounted) return;
    await _download(entry);
  }

  Future<void> _download(FsEntry entry) async {
    final conn = ref.read(activeConnectionProvider);
    if (conn == null) return;
    final s = ref.read(stringsProvider);
    final progressNotifier = ValueNotifier<_DownloadState>(
      const _DownloadState(received: 0, total: null, done: false),
    );
    final cancelToken = Completer<void>();
    bool dialogOpen = true;

    // 弹出进度对话框（不阻塞 await）
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DownloadProgressDialog(
        filename: entry.name,
        progress: progressNotifier,
        onCancel: () {
          if (!cancelToken.isCompleted) cancelToken.complete();
        },
      ),
    ).then((_) => dialogOpen = false);

    try {
      final tmpDir = await getTemporaryDirectory();
      final dest = File('${tmpDir.path}/cc-downloads/${entry.name}');
      final api = FilesApi(conn.httpBase);
      final file = await api.download(
        remotePath: entry.path,
        destFile: dest,
        cancelToken: cancelToken,
        onProgress: (recv, total) {
          progressNotifier.value = _DownloadState(received: recv, total: total, done: false);
        },
      );
      progressNotifier.value = _DownloadState(received: file.lengthSync(), total: file.lengthSync(), done: true);
      if (dialogOpen && mounted) Navigator.of(context).pop();

      // 分享出去（让用户存到相册、文件 app、邮件、AirDrop…）
      // ignore: deprecated_member_use — share_plus 跨平台 API 仍然推荐 shareXFiles
      await Share.shareXFiles(
        [XFile(file.path, name: entry.name)],
        subject: s.filesShareSavedFile,
      );
    } on FsCancelledException {
      if (dialogOpen && mounted) Navigator.of(context).pop();
    } catch (e) {
      if (dialogOpen && mounted) Navigator.of(context).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(s.filesDownloadFailedTpl.replaceAll('{err}', '$e')),
      ));
    } finally {
      progressNotifier.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final session = ref.watch(currentSessionProvider);

    if (session == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open, size: 40, color: t.textDim),
              const SizedBox(height: 12),
              Text(s.chatEmptyPickProject,
                  style: TextStyle(fontSize: 14, color: t.textMuted, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initIfNeeded(session);
    });

    return Column(
      children: [
        _PathBar(
          path: _path == null ? '~' : _humanPath(_path!),
          rawPath: _path,
          rootPath: _rootPath,
          onJump: (abs) => _ls(abs),
          onRefresh: _path == null ? null : () => _ls(_path!, force: true),
        ),
        Divider(color: t.borderSubt, height: 0.5, thickness: 0.5),
        Expanded(child: _body(t, s)),
      ],
    );
  }

  Widget _body(AppTokens t, Strings s) {
    if (_loading && _entries.isEmpty) {
      return Center(child: CircularProgressIndicator(strokeWidth: 2, color: t.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: t.error, size: 28),
              const SizedBox(height: 10),
              Text(
                s.filesLoadFailedTpl.replaceAll('{err}', _error!),
                style: TextStyle(color: t.error, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Text(s.filesEmpty, style: TextStyle(color: t.textDim, fontSize: 13)),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        if (_path != null) await _ls(_path!, force: true);
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: _entries.length,
        itemBuilder: (_, i) {
          final e = _entries[i];
          return _FsRow(
            entry: e,
            onTap: () => e.isDir ? _ls(e.path) : _onTapFile(e),
          );
        },
      ),
    );
  }
}

// ── path bar (breadcrumb) ──────────────────────────────────────────

/// 可点击的路径面包屑：`~ / workspace / shulex / claude-companion`，
/// 每段都能 tap 跳到对应那一级。比单纯的"上级"按钮更高效——尤其深路径下。
class _PathBar extends StatelessWidget {
  final String path; // 已经 home-fold 过的展示路径
  final String? rawPath; // 真实绝对路径，用于点击时算出每段的目标 path
  final String? rootPath; // 起始项目根，root 之前的段不允许 jump
  final void Function(String absolutePath) onJump;
  final VoidCallback? onRefresh;
  const _PathBar({
    required this.path,
    required this.rawPath,
    required this.rootPath,
    required this.onJump,
    required this.onRefresh,
  });

  /// 把 `~/workspace/shulex/.../server` 拆成可点击段。每段返回 (label, absolutePath?)。
  /// absolutePath == null 表示该段在 root 之外，禁止跳转。
  List<(String, String?)> _segments() {
    if (rawPath == null || rawPath!.isEmpty) {
      return [('~', null)];
    }
    final raw = rawPath!;
    final segs = raw.split('/').where((s) => s.isNotEmpty).toList();
    // 重建每段对应的累积路径
    final result = <(String, String?)>[];
    var cum = '';
    final isHome = path.startsWith('~');
    if (isHome) {
      // 找到 home 段：raw 形如 /Users/<me>/...；前两段 (Users/<me>) 折叠成 ~
      // 累积 path 跨过 /Users/<me> 为止
      if (segs.length >= 2) {
        cum = '/${segs[0]}/${segs[1]}';
        result.add(('~', _isUnderRoot(cum) ? cum : null));
        for (var i = 2; i < segs.length; i++) {
          cum = '$cum/${segs[i]}';
          result.add((segs[i], _isUnderRoot(cum) ? cum : null));
        }
      } else {
        result.add(('~', null));
      }
    } else {
      // 绝对路径但不在 home 下：完整展开（首段保留 / 前缀）
      result.add(('/', null));
      for (final s in segs) {
        cum = '$cum/$s';
        result.add((s, _isUnderRoot(cum) ? cum : null));
      }
    }
    return result;
  }

  bool _isUnderRoot(String abs) {
    if (rootPath == null) return true;
    return abs == rootPath || abs.startsWith('$rootPath/') || rootPath!.startsWith('$abs/') || rootPath == abs;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final segs = _segments();
    return Container(
      color: t.surface,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true, // 末段总是可见
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < segs.length; i++) ...[
                    _Crumb(
                      label: segs[i].$1,
                      target: segs[i].$2,
                      isLast: i == segs.length - 1,
                      onJump: onJump,
                    ),
                    if (i < segs.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.chevron_right, size: 14, color: t.textDim),
                      ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 18, color: onRefresh == null ? t.textDim : t.textMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  final String label;
  final String? target; // null = 不可跳
  final bool isLast;
  final void Function(String) onJump;
  const _Crumb({
    required this.label,
    required this.target,
    required this.isLast,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final color = isLast ? t.text : (target == null ? t.textDim : t.accent);
    final weight = isLast ? FontWeight.w600 : FontWeight.w500;
    final tappable = !isLast && target != null;
    return InkWell(
      onTap: tappable ? () => onJump(target!) : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: weight,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

// ── file row ────────────────────────────────────────────────────────

class _FsRow extends StatelessWidget {
  final FsEntry entry;
  final VoidCallback onTap;
  const _FsRow({required this.entry, required this.onTap});

  IconData _iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') || lower.endsWith('.webp')) return Icons.image_outlined;
    if (lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.webm')) return Icons.movie_outlined;
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.m4a') || lower.endsWith('.flac')) return Icons.audiotrack_outlined;
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.endsWith('.zip') || lower.endsWith('.tar') || lower.endsWith('.gz') || lower.endsWith('.tgz')) return Icons.folder_zip_outlined;
    if (lower.endsWith('.md') || lower.endsWith('.txt') || lower.endsWith('.log')) return Icons.description_outlined;
    if (lower.endsWith('.ts') || lower.endsWith('.tsx') || lower.endsWith('.js') ||
        lower.endsWith('.jsx') || lower.endsWith('.dart') || lower.endsWith('.py') ||
        lower.endsWith('.rs') || lower.endsWith('.go') || lower.endsWith('.java') ||
        lower.endsWith('.kt') || lower.endsWith('.swift') || lower.endsWith('.c') ||
        lower.endsWith('.cpp') || lower.endsWith('.h') || lower.endsWith('.json')) return Icons.code_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final icon = entry.isDir ? Icons.folder : _iconFor(entry.name);
    final iconColor = entry.isDir ? t.accent : t.textMuted;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.name,
                    style: TextStyle(fontSize: 14, color: t.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!entry.isDir) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${formatBytes(entry.sizeBytes)} · ${_relativeTime(entry.modifiedMs)}',
                      style: TextStyle(fontSize: 10.5, color: t.textDim, fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              entry.isDir ? Icons.chevron_right : Icons.download_outlined,
              size: 16,
              color: t.textDim,
            ),
          ],
        ),
      ),
    );
  }
}

// ── confirm + progress dialogs ──────────────────────────────────────

class _DownloadConfirmDialog extends StatelessWidget {
  final FsEntry entry;
  final Strings strings;
  const _DownloadConfirmDialog({required this.entry, required this.strings});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(strings.filesDownload, style: TextStyle(fontSize: 16, color: t.text)),
      content: Text(
        strings.filesConfirmDownloadTpl
            .replaceAll('{name}', entry.name)
            .replaceAll('{size}', formatBytes(entry.sizeBytes)),
        style: TextStyle(fontSize: 13, color: t.textMuted, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.filesCancel, style: TextStyle(color: t.textMuted)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.filesDownload),
        ),
      ],
    );
  }
}

class _DownloadState {
  final int received;
  final int? total;
  final bool done;
  const _DownloadState({required this.received, required this.total, required this.done});
}

class _DownloadProgressDialog extends StatelessWidget {
  final String filename;
  final ValueListenable<_DownloadState> progress;
  final VoidCallback onCancel;
  const _DownloadProgressDialog({
    required this.filename,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final s = ProviderScope.containerOf(context).read(stringsProvider);
    return AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(s.filesDownloading, style: TextStyle(fontSize: 16, color: t.text)),
      content: ValueListenableBuilder<_DownloadState>(
        valueListenable: progress,
        builder: (_, state, __) {
          final pct = state.total == null || state.total == 0
              ? null
              : state.received / state.total!;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                filename,
                style: TextStyle(fontSize: 13, color: t.text, fontFamily: 'monospace'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: t.borderSubt,
                color: t.accent,
              ),
              const SizedBox(height: 8),
              Text(
                '${formatBytes(state.received)}${state.total != null ? ' / ${formatBytes(state.total!)}' : ''}',
                style: TextStyle(fontSize: 11, color: t.textDim, fontFamily: 'monospace'),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text(s.filesCancel, style: TextStyle(color: t.textMuted)),
        ),
      ],
    );
  }
}

// ── formatting helpers ──────────────────────────────────────────────

String formatBytes(int n) {
  if (n < 1024) return '${n}B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)}KB';
  if (n < 1024 * 1024 * 1024) return '${(n / 1024 / 1024).toStringAsFixed(1)}MB';
  return '${(n / 1024 / 1024 / 1024).toStringAsFixed(2)}GB';
}

String _relativeTime(int ms) {
  if (ms <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inDays >= 365) return DateFormat('yyyy-MM-dd').format(dt);
  if (diff.inDays >= 1) return DateFormat('MM-dd').format(dt);
  return DateFormat('HH:mm').format(dt);
}
