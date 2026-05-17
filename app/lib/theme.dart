import 'package:flutter/material.dart';

/// Semantic color tokens for the entire app. Looked up via `AppTokens.of(context)`.
class AppTokens {
  final Color bg;
  final Color surface;
  final Color surfaceHi;
  final Color border;
  final Color borderSubt;
  final Color text;
  final Color textMuted;
  final Color textDim;
  final Color accent;
  final Color accentSubt;
  final Color success;
  final Color error;
  final Color warning;

  // Tool semantic colors
  final Color toolEdit;
  final Color toolBash;
  final Color toolRead;
  final Color toolGrep;
  final Color toolTodo;
  final Color toolWebFetch;

  const AppTokens({
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.border,
    required this.borderSubt,
    required this.text,
    required this.textMuted,
    required this.textDim,
    required this.accent,
    required this.accentSubt,
    required this.success,
    required this.error,
    required this.warning,
    required this.toolEdit,
    required this.toolBash,
    required this.toolRead,
    required this.toolGrep,
    required this.toolTodo,
    required this.toolWebFetch,
  });

  static const dark = AppTokens(
    bg: Color(0xFF0B1210),
    surface: Color(0xFF141B18),
    surfaceHi: Color(0xFF1A221E),
    border: Color(0xFF2A332E),
    borderSubt: Color(0xFF1E2622),
    text: Color(0xFFE6E6E6),
    textMuted: Color(0xFF9BA39E),
    textDim: Color(0xFF6B746F),
    accent: Color(0xFF10B981),
    accentSubt: Color(0x2410B981), // ~14% alpha
    success: Color(0xFF22C55E),
    error: Color(0xFFEF4444),
    warning: Color(0xFFEAB308),
    toolEdit: Color(0xFF10B981),     // accent green
    toolBash: Color(0xFFA78BFA),     // violet
    toolRead: Color(0xFF3B82F6),     // blue
    toolGrep: Color(0xFF06B6D4),     // cyan
    toolTodo: Color(0xFFA78BFA),     // violet
    toolWebFetch: Color(0xFFEAB308), // yellow
  );

  static const light = AppTokens(
    bg: Color(0xFFF8FAF9),
    surface: Color(0xFFFFFFFF),
    surfaceHi: Color(0xFFF2F6F4),
    border: Color(0xFFDDE5E1),
    borderSubt: Color(0xFFEAF0EC),
    text: Color(0xFF1A1F1C),
    textMuted: Color(0xFF565F5A),
    textDim: Color(0xFF8E948F),
    accent: Color(0xFF059669),
    accentSubt: Color(0x1A059669), // ~10% alpha
    success: Color(0xFF16A34A),
    error: Color(0xFFDC2626),
    warning: Color(0xFFCA8A04),
    toolEdit: Color(0xFF059669),
    toolBash: Color(0xFF7C3AED),
    toolRead: Color(0xFF2563EB),
    toolGrep: Color(0xFF0891B2),
    toolTodo: Color(0xFF7C3AED),
    toolWebFetch: Color(0xFFCA8A04),
  );

  static AppTokens of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}

ThemeData buildTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? AppTokens.dark : AppTokens.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: Colors.white,
    primaryContainer: t.accentSubt,
    onPrimaryContainer: t.accent,
    secondary: t.accent,
    onSecondary: Colors.white,
    surface: t.surface,
    onSurface: t.text,
    surfaceContainerHighest: t.surfaceHi,
    error: t.error,
    onError: Colors.white,
    outline: t.border,
    outlineVariant: t.borderSubt,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    fontFamily: 'Inter',
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 0,
      titleTextStyle: TextStyle(
        color: t.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: t.text, size: 22),
    ),
    dividerTheme: DividerThemeData(color: t.borderSubt, thickness: 0.5, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: t.textMuted,
      textColor: t.text,
      dense: true,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      width: 320,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surfaceHi,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: t.border, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: t.border, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: t.accent, width: 1.2),
      ),
      hintStyle: TextStyle(color: t.textDim, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: t.text, fontSize: 14, height: 1.5),
      bodyMedium: TextStyle(color: t.text, fontSize: 13, height: 1.5),
      bodySmall: TextStyle(color: t.textMuted, fontSize: 11),
      titleSmall: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: t.text, fontSize: 15, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(color: t.textDim, fontSize: 10, fontFamily: 'monospace'),
    ),
    splashColor: t.accent.withValues(alpha: 0.06),
    highlightColor: t.accent.withValues(alpha: 0.04),
    textSelectionTheme: TextSelectionThemeData(
      // 选区色用 50% accent：与 14%/10% 气泡底色拉开 36~40 个 alpha 等级，
      // 长按选中时"选了 vs 没选"差异明显，不会糊成一片绿。
      selectionColor: t.accent.withValues(alpha: 0.50),
      cursorColor: t.accent,
      selectionHandleColor: t.accent,
    ),
  );
}
