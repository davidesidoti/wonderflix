import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../auth/session_controller.dart';
import '../profiles/avatar_dialog.dart';
import '../profiles/profile_switch.dart';
import 'appearance_settings_section.dart';
import 'discord_settings_section.dart';
import 'language_settings_section.dart';
import 'locale_controller.dart';
import 'player_settings_section.dart';
import 'support_section.dart';

/// Diametro dell'avatar in Impostazioni → Account.
const _accountAvatarSize = 64.0;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Elementi dell'entrata: il titolo e le sette sezioni.
  static const _sectionCount = 8;

  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    final session = ref.watch(sessionControllerProvider);
    final version = ref.watch(clientInfoProvider).version;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 32, bottom: 12),
          child: Text(title, style: WfText.display(24)),
        );

    // Una sezione (titolo e contenuto) è un elemento dell'entrata.
    Widget item(int index, List<Widget> children) => StaggerItem(
          index: index,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );

    // Non una ListView: le sezioni uscite dallo schermo verrebbero
    // smontate, e quella delle lingue (provider autoDispose) ricaricata
    // dal server a ogni passaggio.
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.all(32),
      child: StaggerGroup(
        count: _sectionCount,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaggerItem(
              index: 0,
              child: Text(l.menuSettings.toUpperCase(),
                  style: WfText.display(40)),
            ),
            item(1, [
              section(l.settingsLanguage),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: 'system', label: Text(l.settingsLanguageSystem)),
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
            ]),
            item(2, [
              section(l.settingsAppearance),
              const AppearanceSettingsSection(),
            ]),
            item(3, [
              section(l.settingsPlayer),
              const PlayerSettingsSection(),
            ]),
            item(4, [
              section(l.settingsLanguages),
              const LanguageSettingsSection(),
            ]),
            item(5, [
              section(l.settingsDiscord),
              const DiscordSettingsSection(),
            ]),
            item(6, [
              section(l.settingsAccount),
              if (session is SessionSignedIn)
                Row(
                  children: [
                    UserAvatar(
                      userId: session.user.id,
                      name: session.user.name,
                      size: _accountAvatarSize,
                      imageTag: session.user.primaryImageTag,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Text(l.settingsSignedInAs(session.user.name))),
                  ],
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (session is SessionSignedIn)
                    WfButton.secondary(
                      label: l.settingsChangeImage,
                      icon: LucideIcons.imagePlus,
                      onPressed: () => unawaited(showAvatarDialog(context,
                          userId: session.user.id,
                          name: session.user.name,
                          imageTag: session.user.primaryImageTag)),
                    ),
                  WfButton.secondary(
                    label: l.profilesSwitch,
                    icon: LucideIcons.users,
                    onPressed: () => unawaited(changeProfile(context, ref)),
                  ),
                  WfButton.secondary(
                    label: l.menuLogout,
                    icon: LucideIcons.logOut,
                    onPressed: () => unawaited(
                        ref.read(sessionControllerProvider.notifier).logout()),
                  ),
                ],
              ),
            ]),
            item(7, [
              section(l.settingsSupport),
              const SupportSection(),
              const SizedBox(height: 40),
              Text(l.settingsVersion(version),
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12.5)),
            ]),
          ],
        ),
      ),
    );
  }
}
