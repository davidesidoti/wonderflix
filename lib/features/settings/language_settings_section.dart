import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/user_config_api.dart';
import '../../l10n/gen/app_localizations.dart';
import 'language_preferences.dart';

/// Lingue di audio e sottotitoli e quando mostrare i sottotitoli: sono
/// salvate sul server e il server le usa per scegliere le tracce.
class LanguageSettingsSection extends ConsumerWidget {
  const LanguageSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return switch (ref.watch(languagePreferencesProvider)) {
      AsyncData(:final value) => _LanguageForm(preferences: value),
      AsyncError(:final error) => Row(
          children: [
            Flexible(child: Text(describeError(l, error))),
            TextButton(
              onPressed: () => ref.invalidate(languagePreferencesProvider),
              child: Text(l.retry),
            ),
          ],
        ),
      _ => const Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
    };
  }
}

class _LanguageForm extends ConsumerWidget {
  const _LanguageForm({required this.preferences});

  final LanguagePreferences preferences;

  Future<void> _save(
      BuildContext context, WidgetRef ref, LanguagePreferences next) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(languagePreferencesProvider.notifier).save(next);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l.settingsSaveError)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    List<DropdownMenuItem<String>> languages(String current) => [
          DropdownMenuItem(value: '', child: Text(l.settingsLanguageAny)),
          for (final entry in playbackLanguages.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          if (current.isNotEmpty && !playbackLanguages.containsKey(current))
            DropdownMenuItem(value: current, child: Text(current)),
        ];
    final modes = {
      'Default': l.settingsSubtitleModeDefault,
      'Always': l.settingsSubtitleModeAlways,
      'OnlyForced': l.settingsSubtitleModeOnlyForced,
      'None': l.settingsSubtitleModeNone,
      'Smart': l.settingsSubtitleModeSmart,
    };
    final mode = subtitleModes.contains(preferences.subtitleMode)
        ? preferences.subtitleMode
        : 'Default';

    Widget labeled(String label, Widget field) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(label), const SizedBox(height: 6), field],
          ),
        );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.settingsLanguagesHint,
              style: const TextStyle(color: WfColors.creamMuted)),
          const SizedBox(height: 16),
          labeled(
            l.settingsAudioLanguage,
            DropdownButton<String>(
              key: const Key('audio-language'),
              value: preferences.audioLanguage,
              items: languages(preferences.audioLanguage),
              onChanged: (value) => unawaited(_save(context, ref,
                  preferences.copyWith(audioLanguage: value ?? ''))),
            ),
          ),
          labeled(
            l.settingsSubtitleLanguage,
            DropdownButton<String>(
              key: const Key('subtitle-language'),
              value: preferences.subtitleLanguage,
              items: languages(preferences.subtitleLanguage),
              onChanged: (value) => unawaited(_save(context, ref,
                  preferences.copyWith(subtitleLanguage: value ?? ''))),
            ),
          ),
          labeled(
            l.settingsSubtitleMode,
            DropdownButton<String>(
              key: const Key('subtitle-mode'),
              value: mode,
              items: [
                for (final entry in modes.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) => unawaited(_save(
                  context, ref, preferences.copyWith(subtitleMode: value))),
            ),
          ),
        ],
      ),
    );
  }
}
