import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../social/social_providers.dart';
import 'account_settings_section.dart';
import 'appearance_settings_section.dart';
import 'discord_settings_section.dart';
import 'home_settings_section.dart';
import 'language_settings_section.dart';
import 'notifications_settings_section.dart';
import 'player_settings_section.dart';
import 'settings_kit.dart';
import 'settings_nav.dart';
import 'support_section.dart';
import 'tv_settings_body.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.section});

  /// La sezione da mostrare all'apertura (`/settings?section=<id>`): uno degli
  /// id delle sezioni. Uno sconosciuto o non visibile si ignora.
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

  /// I titoli delle sezioni, dove scorrere con la voce o con `section=<id>`.
  final _sectionKeys = {
    for (final id in _sectionIds) id: GlobalKey(debugLabel: 'settings-$id'),
  };

  /// La sezione accesa nella colonna o nella fila.
  late String _current = widget.section ?? _sectionIds.first;

  /// Le sezioni visibili ora, per lo scroll spy (le riempie `build`).
  var _visible = <String>[];

  /// Un clic ha fatto partire uno scorrimento animato: finché dura, lo scroll
  /// spy non tocca la voce scelta. [_scrollToken] distingue un clic dal
  /// successivo, che interrompe il primo.
  var _animating = false;
  var _scrollToken = 0;

  /// La sezione aperta con `section=<id>`: le sezioni sopra si caricano dopo
  /// (la Home dal server) e spostano il titolo, quindi finché l'utente non
  /// scorre lo si riporta in cima a ogni cambio di altezza.
  String? _pin;

  /// Dove stava la pagina dopo l'ultimo allineamento del pin: se si e' mossa
  /// (tastiera, D-pad, rotella) il pin cade, qualunque cosa l'abbia mossa.
  var _pinOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_spy);
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
    final section = widget.section;
    if (section == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_visible.contains(section)) return;
      unawaited(_select(section, pin: true));
    });
  }

  /// Accende la voce e scorre al titolo della sezione.
  Future<void> _select(String id, {bool pin = false}) async {
    final target = _sectionKeys[id]?.currentContext;
    if (target == null) return;
    setState(() => _current = id);
    _pin = pin ? id : null;
    final token = ++_scrollToken;
    _animating = true;
    try {
      await Scrollable.ensureVisible(
        target,
        duration: WfMotion.of(context).duration(WfMotion.medium),
        curve: WfMotion.emphasized,
      );
    } finally {
      // Niente `_spy` alla fine: una sezione in fondo non arriva in cima, e la
      // voce scelta non deve cambiare da sola.
      if (token == _scrollToken) _animating = false;
    }
    if (token == _scrollToken && _pin == id) _realign();
  }

  /// Riporta in cima il titolo della sezione aperta con `section=<id>`.
  /// Senza durata: il salto e' immediato, e `_aligning` tiene lo spy fuori.
  void _realign() {
    final target = _sectionKeys[_pin]?.currentContext;
    if (target != null) {
      _aligning = true;
      unawaited(Scrollable.ensureVisible(target));
      _aligning = false;
    }
    if (_scroll.hasClients) _pinOffset = _scroll.offset;
  }

  var _aligning = false;

  /// Il pin vale ancora: la pagina non si e' mossa dal suo allineamento.
  /// Altrimenti lo toglie.
  bool _pinHolds() {
    if (_pin == null) return false;
    if (_scroll.hasClients && (_scroll.offset - _pinOffset).abs() > 1) {
      _pin = null;
    }
    return _pin != null;
  }

  bool _onNotification(Notification n) {
    // Solo la pagina: non gli scorrevoli dentro (campi, menu, elenchi).
    if (n is ViewportNotificationMixin && n.depth != 0) return false;
    if (n is ScrollMetricsNotification && !_animating && _pinHolds()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pinHolds()) _realign();
      });
    }
    return false;
  }

  /// Dove sta il titolo di una sezione rispetto alla cima dell'area visibile.
  double? _titleTop(String id) {
    final box = _sectionKeys[id]?.currentContext?.findRenderObject();
    if (box is! RenderBox) return null;
    if (!box.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    return viewport == null
        ? null
        : box.localToGlobal(Offset.zero, ancestor: viewport).dy;
  }

  /// La voce accesa seguendo lo scorrimento: l'ultima sezione il cui titolo è
  /// sopra un terzo dell'altezza, l'ultima in assoluto quando si è in fondo.
  void _spy() {
    if (_animating || _aligning || _pinHolds()) return;
    if (!_scroll.hasClients || _visible.isEmpty) return;
    final position = _scroll.position;
    var found = _visible.first;
    if (position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 1) {
      found = _visible.last;
    } else {
      for (final id in _visible) {
        final top = _titleTop(id);
        if (top != null && top <= position.viewportDimension / 3) found = id;
      }
    }
    if (found != _current) setState(() => _current = found);
  }

  @override
  Widget build(BuildContext context) {
    // Sulla TV un altro corpo, solo per il telecomando (decisione 8): niente
    // voci, ne' spy ne' pin.
    if (FormFactor.of(context).tv) {
      _visible = const [];
      return const TvSettingsBody();
    }
    final l = AppLocalizations.of(context);
    final version = ref.watch(clientInfoProvider).version;
    final push = ref.watch(socialAvailabilityProvider.select((f) => f.push));
    final compact = FormFactor.of(context).compact;
    // Le voci della colonna: le stesse sezioni che la pagina mostra.
    _visible = [
      'account',
      if (push) 'notifications',
      'home',
      'playback',
      'subtitles',
      'app',
      if (!kIsWeb) 'discord',
      'support',
    ];
    final current = _visible.contains(_current) || _visible.isEmpty
        ? _current
        : _visible.first;

    // Una sezione (titolo e righe) è un elemento dell'entrata, larga al più
    // 640 px e a sinistra.
    Widget section(
      int index,
      String id,
      String title,
      SettingsScope? scope,
      Widget body, {
      double bodyWidth = 640,
    }) => StaggerItem(
      index: index,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: bodyWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Il titolo resta largo 640 anche se il corpo è più largo.
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  // La `GlobalKey` serve a scorrere qui; la `ValueKey` ai test.
                  child: KeyedSubtree(
                    key: _sectionKeys[id],
                    child: SettingsSectionTitle(
                      key: ValueKey('settings-section-$id'),
                      title: title,
                      scope: scope,
                    ),
                  ),
                ),
              ),
              body,
            ],
          ),
        ),
      ),
    );

    // Non una ListView: le sezioni uscite dallo schermo verrebbero
    // smontate, e quella delle lingue (provider autoDispose) ricaricata
    // dal server a ogni passaggio.
    final page = NotificationListener<Notification>(
      onNotification: _onNotification,
      child: SingleChildScrollView(
        controller: _scroll,
        // Nel largo il titolo di ogni sezione ha già 32 px sopra.
        padding: EdgeInsets.fromLTRB(32, compact ? 32 : 0, 32, 32),
        child: StaggerGroup(
          count: _sectionCount,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Nel largo il titolo sta nella colonna.
              if (compact)
                StaggerItem(
                  index: 0,
                  child: Text(
                    l.menuSettings.toUpperCase(),
                    style: WfText.display(40),
                  ),
                ),
              section(
                1,
                'account',
                l.settingsAccount,
                SettingsScope.account,
                const AccountSettingsSection(),
              ),
              // Solo con le notifiche push nel plugin (spec V §4.1).
              if (push)
                section(
                  2,
                  'notifications',
                  l.settingsNotifications,
                  SettingsScope.account,
                  const NotificationsSettingsSection(),
                ),
              section(
                3,
                'home',
                l.settingsHome,
                SettingsScope.account,
                const HomeSettingsSection(),
              ),
              section(
                4,
                'playback',
                l.settingsSectionPlayback,
                SettingsScope.device,
                const PlayerSettingsSection(),
              ),
              section(
                5,
                'subtitles',
                l.settingsSectionSubtitles,
                SettingsScope.jellyfin,
                const LanguageSettingsSection(),
                // Nel largo l'anteprima sta a destra dell'elenco.
                bodyWidth: LanguageSettingsSection.wideWidth,
              ),
              section(
                6,
                'app',
                l.settingsSectionApp,
                SettingsScope.device,
                const AppearanceSettingsSection(),
              ),
              // Nel browser la Rich Presence è spenta (spec 1b §4.6).
              if (!kIsWeb)
                section(
                  7,
                  'discord',
                  l.settingsDiscord,
                  SettingsScope.device,
                  const DiscordSettingsSection(),
                ),
              section(
                8,
                'support',
                l.settingsSupport,
                null,
                const SupportSection(),
              ),
              StaggerItem(
                index: 9,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    // Nel largo la versione sta in fondo alla colonna.
                    if (compact)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l.settingsVersion(version),
                          style: const TextStyle(
                            color: WfColors.creamMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Un solo `Flex` per i due schermi: passando dal largo allo stretto la
    // pagina non si ricrea e non perde lo scorrimento.
    return Flex(
      direction: compact ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        compact
            ? SettingsSectionStrip(
                sections: _visible,
                current: current,
                onSelect: _select,
              )
            : SettingsRail(
                sections: _visible,
                current: current,
                version: version,
                onSelect: _select,
              ),
        Expanded(child: page),
      ],
    );
  }
}
