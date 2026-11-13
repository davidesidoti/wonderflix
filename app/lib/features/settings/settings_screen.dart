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
import 'notifications_settings_section.dart';
import 'player_settings_section.dart';
import 'settings_kit.dart';
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
  /// Elementi dell'entrata: il titolo, le otto sezioni e il piede.
  static const _sectionCount = 10;

  /// Gli id delle sezioni, nell'ordine della pagina.
  static const _sectionIds = [
    'account',
    'notifications',
    'home',
    'playback',
    'subtitles',
    'app',
    'discord',
    'support',
  ];

  final _scroll = SmoothScrollController();

  /// I titoli delle sezioni, dove scorrere con `section=<id>`.
  final _sectionKeys = {
    for (final id in _sectionIds) id: GlobalKey(debugLabel: 'settings-$id'),
  };

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
      final target = _sectionKeys[homeSettingsSection]?.currentContext;
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
    final version = ref.watch(clientInfoProvider).version;
    final push = ref.watch(socialAvailabilityProvider.select((f) => f.push));
    // Sulla TV solo riproduzione, audio e sottotitoli e lingua dell'app: il
    // resto si imposta dal PC o dal telefono.
    final tv = FormFactor.of(context).tv;

    // Una sezione (titolo e righe) è un elemento dell'entrata, larga al più
    // 640 px e a sinistra.
    Widget section(
      int index,
      String id,
      String title,
      SettingsScope? scope,
      Widget body,
    ) => StaggerItem(
      index: index,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // La `GlobalKey` serve a scorrere qui; la `ValueKey` ai test.
              KeyedSubtree(
                key: _sectionKeys[id],
                child: SettingsSectionTitle(
                  key: ValueKey('settings-section-$id'),
                  title: title,
                  scope: scope,
                ),
              ),
              body,
            ],
          ),
        ),
      ),
    );

    Widget appSection(int index) => section(index, 'app', l.settingsSectionApp,
        SettingsScope.device, const AppearanceSettingsSection());

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
              section(1, 'account', l.settingsAccount, SettingsScope.account,
                  const AccountSettingsSection()),
            // Solo con le notifiche push nel plugin (spec V §4.1).
            if (push && !tv)
              section(2, 'notifications', l.settingsNotifications,
                  SettingsScope.account, const NotificationsSettingsSection()),
            if (!tv)
              section(3, 'home', l.settingsHome, SettingsScope.account,
                  const HomeSettingsSection()),
            // La TV parte dalla lingua dell'app, come il suo elenco.
            if (tv) appSection(3),
            section(4, 'playback', l.settingsSectionPlayback,
                SettingsScope.device, const PlayerSettingsSection()),
            section(5, 'subtitles', l.settingsSectionSubtitles,
                SettingsScope.jellyfin, const LanguageSettingsSection()),
            if (!tv) appSection(6),
            // Nel browser la Rich Presence è spenta (spec 1b §4.6).
            if (!kIsWeb && !tv)
              section(7, 'discord', l.settingsDiscord, SettingsScope.device,
                  const DiscordSettingsSection()),
            if (!tv)
              section(8, 'support', l.settingsSupport, null,
                  const SupportSection()),
            StaggerItem(
              index: 9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
