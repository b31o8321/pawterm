import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';

/// User-selected language preference. `null` = follow system.
enum LangPref { system, en, zh }

extension LangPrefDisplay on LangPref {
  String label(Strings s) {
    switch (this) {
      case LangPref.system:
        return s.settingsLanguageSystem;
      case LangPref.en:
        return s.settingsLanguageEnglish;
      case LangPref.zh:
        return s.settingsLanguageChinese;
    }
  }
}

const _prefsKey = 'lang_pref_v1';

class LangPrefNotifier extends StateNotifier<LangPref> {
  LangPrefNotifier() : super(LangPref.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    switch (raw) {
      case 'en':
        state = LangPref.en;
        break;
      case 'zh':
        state = LangPref.zh;
        break;
      default:
        state = LangPref.system;
    }
  }

  Future<void> set(LangPref next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    switch (next) {
      case LangPref.system:
        await prefs.remove(_prefsKey);
        break;
      case LangPref.en:
        await prefs.setString(_prefsKey, 'en');
        break;
      case LangPref.zh:
        await prefs.setString(_prefsKey, 'zh');
        break;
    }
  }
}

final langPrefProvider =
    StateNotifierProvider<LangPrefNotifier, LangPref>((_) => LangPrefNotifier());

/// Resolved Strings pack based on current preference + system locale.
final stringsProvider = Provider<Strings>((ref) {
  final pref = ref.watch(langPrefProvider);
  switch (pref) {
    case LangPref.en:
      return stringsEn;
    case LangPref.zh:
      return stringsZh;
    case LangPref.system:
      return _systemPickedStrings();
  }
});

Strings _systemPickedStrings() {
  final localeName = ui.PlatformDispatcher.instance.locale.languageCode;
  return localeName == 'zh' ? stringsZh : stringsEn;
}

/// Locale used by [MaterialApp.locale]. Drives date/number formatting and the
/// system "input method" hints. We let our own Strings handle UI text.
final materialLocaleProvider = Provider<Locale?>((ref) {
  final pref = ref.watch(langPrefProvider);
  switch (pref) {
    case LangPref.en:
      return const Locale('en');
    case LangPref.zh:
      return const Locale('zh');
    case LangPref.system:
      return null; // let MaterialApp pick from device
  }
});

/// Convenience extension so non-Consumer widgets can still read strings via
/// `context.l10n.foo`, given they live below a ProviderScope (they all do).
extension StringsContext on BuildContext {
  Strings get l10n => ProviderScope.containerOf(this).read(stringsProvider);
}
