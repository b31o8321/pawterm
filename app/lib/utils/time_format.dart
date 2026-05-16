import 'package:intl/intl.dart';

/// Format a chat message timestamp relative to *now*, locale-aware.
///
///   今天     → "14:32"
///   昨天     → "昨天 14:32" / "Yesterday 14:32"
///   今年内    → "05-12 14:32"
///   往年     → "2025-12-31 14:32"
///
/// [yesterdayLabel] should come from the active i18n Strings pack.
String formatMessageTime(DateTime ts, {required String yesterdayLabel}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tsDay = DateTime(ts.year, ts.month, ts.day);
  final daysAgo = today.difference(tsDay).inDays;

  final hm = DateFormat('HH:mm').format(ts);
  if (daysAgo == 0) return hm;
  if (daysAgo == 1) return '$yesterdayLabel $hm';
  if (ts.year == now.year) return '${DateFormat('MM-dd').format(ts)} $hm';
  return '${DateFormat('yyyy-MM-dd').format(ts)} $hm';
}

/// Convert a wire timestamp (epoch ms or null) into a [DateTime] safely.
DateTime? tsFromMillis(int? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
