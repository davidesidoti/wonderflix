import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../update/tv_update_tile.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/tv_focusable.dart';
import '../social/social_providers.dart';
import 'account_settings_section.dart';
import 'appearance_settings_section.dart';
import 'discord_settings_section.dart';
import 'home_settings_section.dart';
import 'language_settings_section.dart';
import 'locale_controller.dart';
import 'notifications_settings_section.dart';
import 'player_settings_section.dart';
import 'support_section.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.section});

  /// La sezione da mostrare all'apertura (`/settings?section=…`): per ora
  /// solo [homeSettingsSection]. Le altre si ignorano.
  final String? section;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Elementi dell'entrata: il titolo e le nove sezioni.
  static const _sectionCount = 10;

  final _scroll = SmoothScrollController();

  /// Il titolo della sezione Home, dove scorrere con `section=home`.
  final _homeKey = GlobalKey(debugLabel: 'settings-home');

  @override
  void initState() {
    super.initState();
    _scrollToSection();
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.section != oldWidget.section) _scrollToSection();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Dopo il fotogramma, quando la sezione ha la sua posizione (decisione
  /// 16 del piano 19c).
  void _scrollToSection() {
    if (widget.section != homeSettingsSection) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _homeKey.currentContext;
      if (!mounted || target == null) return;
      unawaited(Scrollable.ensureVisible(
        target,
        duration: WfMotion.of(context).duration(WfMotion.medium),
        curve: WfMotion.emphasized,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    final version = ref.watch(clientInfoProvider).version;
    final push = ref.watch(socialAvailabilityProvider.select((f) => f.push));
    // Sulla TV solo lingua dell'app, player e lingue di riproduzione: il
    // resto si imposta dal PC o dal telefono.
    final tv = FormFactor.of(context).tv;

    Widget section(String title, {Key? key}) => Padding(
          key: key,
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
            if (!tv)
              item(1, [
                section(l.settingsAccount),
                const AccountSettingsSection(),
              ]),
            // Solo con le notifiche push nel plugin (spec V §4.1).
            if (push && !tv)
              item(2, [
                section(l.settingsNotifications),
                const NotificationsSettingsSection(),
              ]),
            item(3, [
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
            if (!tv) ...[
              item(4, [
                section(l.settingsAppearance),
                const AppearanceSettingsSection(),
              ]),
              item(5, [
                section(l.settingsHome, key: _homeKey),
                const HomeSettingsSection(),
              ]),
            ],
            item(6, [
              section(l.settingsPlayer),
              const PlayerSettingsSection(),
            ]),
            item(7, [
              section(l.settingsLanguages),
              const LanguageSettingsSection(),
            ]),
            // Nel browser la Rich Presence è spenta (spec 1b §4.6).
            if (!kIsWeb && !tv)
              item(8, [
                section(l.settingsDiscord),
                const DiscordSettingsSection(),
              ]),
            item(9, [
              if (!tv) ...[
                section(l.settingsSupport),
                const SupportSection(),
              ],
              const SizedBox(height: 40),
              // Sulla TV si scorre solo col focus: senza, la versione e
              // l'aggiornamento sotto i sottotitoli restano fuori schermo.
              Align(
                alignment: Alignment.centerLeft,
                child: TvFocusable(
                  onActivate: () {},
                  child: Padding(
                    padding: EdgeInsets.all(tv ? 6 : 0),
                    child: Text(l.settingsVersion(version),
                        style: const TextStyle(
                            color: WfColors.creamMuted, fontSize: 12.5)),
                  ),
                ),
              ),
              const TvUpdateTile(),
            ]),
          ],
        ),
      ),
    );
  }
}
