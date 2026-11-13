import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/user_config_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../admin/admin_kit.dart';
import '../player/player_settings.dart';
import 'language_preferences.dart';
import 'settings_kit.dart';
import 'subtitle_preview.dart';

/// Lingue di audio e sottotitoli e quando mostrare i sottotitoli (salvate sul
/// server, che le usa per scegliere le tracce), più la dimensione, che resta
/// su questo PC.
class LanguageSettingsSection extends ConsumerWidget {
  const LanguageSettingsSection({super.key});

  /// Larghezza dell'elenco, dell'anteprima e dello spazio tra i due.
  static const listWidth = 640.0;
  static const previewWidth = 300.0;
  static const _gap = 32.0;

  /// Larghezza da cui l'anteprima sta accanto all'elenco: la pagina la dà alla
  /// sezione.
  static const wideWidth = listWidth + _gap + previewWidth;

  /// Salva sul server; se non riesce, lo dice in basso (anche sulla TV).
  static Future<void> save(
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
    final settings = ref.watch(playerSettingsProvider);
    void saveScale(double scale) => unawaited(ref
        .read(playerSettingsProvider.notifier)
        .update(settings.copyWith(subtitleScale: scale)));
    // La dimensione non viene dal server: c'è anche mentre le lingue caricano
    // o se non si leggono. Nello stretto cinque segmenti non ci stanno a una
    // misura leggibile: un menu.
    final size = SettingsRow(
      label: l.settingsSubtitleSize,
      hint: kIsWeb
          ? l.settingsSubtitleSizeHintWeb
          : l.settingsSubtitleSizeHint,
      wideTrailing: true,
      trailing: FormFactor.of(context).compact
          ? SettingsDropdown<double>(
              key: const Key('subtitle-size'),
              value: settings.subtitleScale,
              items: [
                for (final scale in subtitleScaleOptions)
                  DropdownMenuItem(
                      value: scale, child: Text(subtitleScaleLabel(l, scale))),
              ],
              onChanged: (scale) {
                if (scale != null) saveScale(scale);
              },
            )
          : SegmentedButton<double>(
              showSelectedIcon: false,
              segments: [
                for (final scale in subtitleScaleOptions)
                  ButtonSegment(
                      value: scale, label: Text(subtitleScaleLabel(l, scale))),
              ],
              selected: {settings.subtitleScale},
              onSelectionChanged: (selection) => saveScale(selection.first),
            ),
    );
    final list = AdminList(
      children: [
        ...switch (ref.watch(languagePreferencesProvider)) {
          AsyncData(:final value) => _languageRows(context, ref, value),
          AsyncError(:final error) => [
              SettingsRow(
                label: describeError(l, error),
                trailing: TextButton(
                  onPressed: () => ref.invalidate(languagePreferencesProvider),
                  child: Text(l.retry),
                ),
              ),
            ],
          _ => [
              SettingsRow(
                label: l.settingsLoading,
                trailing: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ],
        },
        size,
      ],
    );
    final preview = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l.settingsSubtitlePreview,
            style: const TextStyle(color: WfColors.creamMuted, fontSize: 12),
          ),
        ),
        SubtitlePreview(scale: settings.subtitleScale),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= wideWidth
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: listWidth, child: list),
                const SizedBox(width: _gap),
                SizedBox(width: previewWidth, child: preview),
              ],
            )
          : Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: listWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [list, const SizedBox(height: 20), preview],
                ),
              ),
            ),
    );
  }

  List<Widget> _languageRows(
      BuildContext context, WidgetRef ref, LanguagePreferences preferences) {
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
    return [
      SettingsRow(
        label: l.settingsAudioLanguage,
        wideTrailing: true,
        trailing: SettingsDropdown<String>(
          key: const Key('audio-language'),
          value: preferences.audioLanguage,
          items: languages(preferences.audioLanguage),
          onChanged: (value) => unawaited(save(
              context, ref, preferences.copyWith(audioLanguage: value ?? ''))),
        ),
      ),
      SettingsRow(
        label: l.settingsSubtitleLanguage,
        wideTrailing: true,
        trailing: SettingsDropdown<String>(
          key: const Key('subtitle-language'),
          value: preferences.subtitleLanguage,
          items: languages(preferences.subtitleLanguage),
          onChanged: (value) => unawaited(save(context, ref,
              preferences.copyWith(subtitleLanguage: value ?? ''))),
        ),
      ),
      SettingsRow(
        label: l.settingsSubtitleMode,
        wideTrailing: true,
        trailing: SettingsDropdown<String>(
          key: const Key('subtitle-mode'),
          value: mode,
          items: [
            for (final entry in modes.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (value) => unawaited(
              save(context, ref, preferences.copyWith(subtitleMode: value))),
        ),
      ),
    ];
  }
}
