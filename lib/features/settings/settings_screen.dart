import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../auth/session_controller.dart';
import 'language_settings_section.dart';
import 'locale_controller.dart';
import 'player_settings_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    final session = ref.watch(sessionControllerProvider);
    final version = ref.watch(clientInfoProvider).version;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 32, bottom: 12),
          child: Text(title, style: WfText.display(24)),
        );

    // Non una ListView: le sezioni uscite dallo schermo verrebbero
    // smontate, e quella delle lingue (provider autoDispose) ricaricata
    // dal server a ogni passaggio.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.menuSettings.toUpperCase(), style: WfText.display(40)),
          section(l.settingsLanguage),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'system', label: Text(l.settingsLanguageSystem)),
                const ButtonSegment(value: 'it', label: Text('Italiano')),
                const ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {locale?.languageCode ?? 'system'},
              onSelectionChanged: (selection) {
                final code = selection.first;
                unawaited(ref
                    .read(localeProvider.notifier)
                    .set(code == 'system' ? null : Locale(code)));
              },
            ),
          ),
          section(l.settingsPlayer),
          const PlayerSettingsSection(),
          section(l.settingsLanguages),
          const LanguageSettingsSection(),
          section(l.settingsAccount),
          if (session is SessionSignedIn)
            Text(l.settingsSignedInAs(session.user.name)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: WfButton.secondary(
              label: l.menuLogout,
              icon: LucideIcons.logOut,
              onPressed: () =>
                  unawaited(ref.read(sessionControllerProvider.notifier).logout()),
            ),
          ),
          const SizedBox(height: 40),
          Text(l.settingsVersion(version),
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 12.5)),
        ],
      ),
    );
  }
}
