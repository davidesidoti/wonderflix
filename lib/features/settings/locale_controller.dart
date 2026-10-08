import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../profiles/profile_preferences.dart';

/// Lingua scelta dall'utente; `null` = lingua di Windows. È una preferenza
/// del profilo (spec K §9.6).
class LocaleController extends Notifier<Locale?> {
  static const _key = 'locale';

  @override
  Locale? build() {
    final code = ref.watch(profilePreferencesProvider).getString(_key);
    // Vuoto: la lingua di Windows scelta in un profilo.
    return code == null || code.isEmpty ? null : Locale(code);
  }

  Future<void> set(Locale? locale) async {
    final prefs = ref.read(profilePreferencesProvider);
    if (locale == null) {
      await prefs.clearString(_key);
    } else {
      await prefs.setString(_key, locale.languageCode);
    }
    state = locale;
  }
}

final localeProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);
