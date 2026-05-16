import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/locale_provider.dart';
import '../theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final pref = ref.watch(langPrefProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.settingsTitle),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: t.text),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: s.settingsBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(label: s.settingsLanguage),
          for (final option in LangPref.values)
            _LangTile(
              option: option,
              selected: pref == option,
              label: option.label(s),
              onTap: () => ref.read(langPrefProvider.notifier).set(option),
            ),
          const SizedBox(height: 24),
          _SectionHeader(label: s.settingsAbout),
          ListTile(
            leading: Icon(Icons.info_outline, size: 18, color: t.textMuted),
            title: Text(s.appTitle, style: TextStyle(color: t.text, fontSize: 13)),
            subtitle: Text(s.appTagline, style: TextStyle(color: t.textMuted, fontSize: 11)),
            dense: true,
          ),
          ListTile(
            leading: Icon(Icons.bookmark_outline, size: 18, color: t.textMuted),
            title: Text(s.settingsVersion, style: TextStyle(color: t.text, fontSize: 13)),
            trailing: Text('0.1.0', style: TextStyle(color: t.textDim, fontSize: 11, fontFamily: 'monospace')),
            dense: true,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: t.textMuted,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _LangTile extends StatelessWidget {
  final LangPref option;
  final bool selected;
  final String label;
  final VoidCallback onTap;
  const _LangTile({
    required this.option,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? t.accent : t.textMuted,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: selected ? t.accent : t.text,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
