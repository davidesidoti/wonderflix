import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_shell.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/shimmer.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/wf_switcher.dart';
import '../settings/home_settings_section.dart';
import 'hero_carousel.dart';
import 'home_layout.dart';
import 'home_providers.dart';
import 'home_row_content.dart';
import 'home_row_view.dart';

/// L'entrata delle righe della Home si vede una volta per sessione
/// (decisione 6b): tornando alla Home dalla barra non si ripete.
class HomeEntrancePlayed extends Notifier<bool> {
  @override
  bool build() => false;

  void markPlayed() => state = true;
}

final homeEntrancePlayedProvider =
    NotifierProvider<HomeEntrancePlayed, bool>(HomeEntrancePlayed.new);

/// Ritardo tra una riga e l'altra nell'entrata della Home.
const homeRowStagger = Duration(milliseconds: 80);

/// Quanto la Home aspetta le righe prima di aprirsi (spec M §8.2 punto 3):
/// quelle più lente entrano dopo, al loro posto.
const homeRevealWait = Duration(milliseconds: 1500);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scroll = SmoothScrollController();

  /// Deciso una volta per istanza della Home: lo stato sta sopra al
  /// `WfSwitcher`, quindi resta lo stesso da scheletro a contenuto.
  late final bool _animate = !ref.read(homeEntrancePlayedProvider);

  /// Scade [homeRevealWait] dopo la composizione, se le righe non sono
  /// ancora arrivate tutte.
  Timer? _revealTimer;

  /// Le righe arrivate quando la Home si è aperta, con il loro posto
  /// nell'entrata scaglionata; `null` finché non si è aperta.
  Map<HomeRowKind, int>? _entrance;

  /// Le righe dell'ultima costruzione: quando scade [homeRevealWait] si apre
  /// con queste, senza leggere altri provider (la composizione potrebbe
  /// essere cambiata un attimo prima della prossima costruzione).
  Map<HomeRowKind, AsyncValue<HomeRowContent>>? _rows;

  /// Le righe arrivate dopo l'apertura che hanno già fatto la loro entrata:
  /// la lista smonta le righe lontane e le ricostruisce scorrendo, e allora
  /// non devono rifarla.
  final _lateEntered = <HomeRowKind>{};

  @override
  void dispose() {
    _revealTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  String get _language => Localizations.localeOf(context).languageCode;

  static bool _settled(AsyncValue<Object?> value) =>
      value.hasValue || value.hasError;

  static bool _failed(AsyncValue<Object?> value) =>
      value.hasError && !value.hasValue;

  /// Per aprire la Home una lettura deve essere finita: una rilettura in
  /// corso (dopo "Riprova", per esempio) conserva il vecchio errore o il
  /// vecchio valore, ma non è ancora arrivata.
  static bool _arrived(AsyncValue<Object?> value) =>
      !value.isLoading && _settled(value);

  /// Apre la Home: entrano insieme le righe già arrivate che si vedono (non
  /// quelle vuote o in errore), nell'ordine e senza buchi.
  void _open(Map<HomeRowKind, AsyncValue<HomeRowContent>> rows) {
    _revealTimer?.cancel();
    _revealTimer = null;
    var index = 0;
    _entrance = {
      for (final MapEntry(:key, :value) in rows.entries)
        if (value.value case final content? when !content.isEmpty) key: index++,
    };
  }

  void _onRevealTimeout() {
    final rows = _rows;
    if (!mounted || rows == null) return;
    setState(() => _open(rows));
  }

  void _retry() {
    ref
      ..invalidate(homeLayoutProvider)
      ..invalidate(homeLatestMoviesProvider)
      ..invalidate(homeLatestSeriesProvider)
      ..invalidate(homeFeaturedProvider)
      ..invalidate(homeRowProvider);
    setState(() {
      _revealTimer?.cancel();
      _revealTimer = null;
      _entrance = null;
      _lateEntered.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // `.value` e non `isLoading`: durante una ricomposizione il valore
    // precedente resta e la Home non torna allo scheletro.
    final layout = ref.watch(homeLayoutProvider).value;
    // Il carosello si guarda anche prima di conoscere la composizione: le
    // sue letture partono insieme a quelle della composizione, non un giro
    // dopo.
    final featured = ref.watch(homeFeaturedProvider);
    final (state, content) = layout == null
        ? ('loading', const _HomeSkeleton())
        : _content(l, layout, featured);
    return WfSwitcher(
      expand: true,
      child: KeyedSubtree(key: ValueKey(state), child: content),
    );
  }

  (String, Widget) _content(AppLocalizations l, HomeLayout layout,
      AsyncValue<List<JellyfinItem>> featured) {
    final rows = <HomeRowKind, AsyncValue<HomeRowContent>>{
      for (final kind in layout.visible)
        kind: ref.watch(homeRowProvider((kind: kind, language: _language))),
    };
    _rows = rows;
    if (_entrance == null) {
      if (_arrived(featured) && rows.values.every(_arrived)) {
        _open(rows);
      } else {
        _revealTimer ??= Timer(homeRevealWait, _onRevealTimeout);
        return ('loading', const _HomeSkeleton());
      }
    }
    final entrance = _entrance!;
    // "Riprova" solo se il carosello e tutte le righe di Jellyfin visibili
    // hanno fallito (spec M §8.2 punto 4).
    if (_failed(featured) &&
        rows.entries
            .where((row) => row.key.fromJellyfin)
            .every((row) => _failed(row.value))) {
      return ('error', ErrorView(error: featured.error!, onRetry: _retry));
    }
    final featuredItems = featured.value ?? const [];
    final shown = <Widget>[
      for (final kind in layout.visible)
        if (rows[kind]!.value case final content? when !content.isEmpty)
          _row(kind, content, entrance[kind]),
    ];
    if (featuredItems.isEmpty && shown.isEmpty) {
      final pending = !_settled(featured) || !rows.values.every(_settled);
      if (pending) return ('loading', const _HomeSkeleton());
      return (
        'empty',
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.homeEmpty,
                  style: const TextStyle(color: WfColors.creamMuted)),
              const _CustomizeLink(),
            ],
          ),
        ),
      );
    }
    return (
      'data',
      StaggerGroup(
        key: const Key('home-rows'),
        count: entrance.length,
        stagger: homeRowStagger,
        play: _animate,
        onPlayed: () =>
            ref.read(homeEntrancePlayedProvider.notifier).markPlayed(),
        child: ListView(
          controller: _scroll,
          // Il carosello parte dal bordo della finestra, sotto la barra;
          // senza carosello la prima riga inizia sotto la barra.
          padding: EdgeInsets.only(
              top: featuredItems.isEmpty ? shellBarHeight : 0, bottom: 40),
          children: [
            if (featuredItems.isNotEmpty) HeroCarousel(items: featuredItems),
            ...shown,
            const Align(
                alignment: Alignment.centerLeft, child: _CustomizeLink()),
          ],
        ),
      ),
    );
  }

  /// Una riga arrivata all'apertura entra con le altre; una arrivata dopo
  /// entra da sola, al suo posto (decisione 6 del piano 19b).
  Widget _row(HomeRowKind kind, HomeRowContent content, int? index) {
    if (index == null) {
      return _LateRow(
        key: ValueKey('home-late-${kind.id}'),
        kind: kind,
        content: content,
        entered: _lateEntered,
        onPlayed: () {
          _lateEntered.add(kind);
          // Se la Home si è aperta senza righe, questa è l'entrata della
          // sessione: la prossima visita non la rifà.
          ref.read(homeEntrancePlayedProvider.notifier).markPlayed();
        },
      );
    }
    return StaggerItem(
      key: ValueKey('home-row-${kind.id}'),
      index: index,
      child: HomeRowView(kind: kind, content: content, animateEntrance: _animate),
    );
  }
}

/// Una riga arrivata dopo l'apertura, con una sua piccola entrata (decisione
/// 6 del piano 19b). Entra una volta sola: la lista smonta le righe lontane
/// e le rimonta scorrendo, con lo stesso widget di prima, quindi se la riga
/// è già entrata ([entered]) lo si decide qui, a ogni montaggio, e non alla
/// costruzione della Home.
class _LateRow extends StatelessWidget {
  const _LateRow({
    super.key,
    required this.kind,
    required this.content,
    required this.entered,
    required this.onPlayed,
  });

  final HomeRowKind kind;
  final HomeRowContent content;
  final Set<HomeRowKind> entered;
  final VoidCallback onPlayed;

  @override
  Widget build(BuildContext context) => StaggerGroup(
        count: 1,
        play: !entered.contains(kind),
        onPlayed: onPlayed,
        child: StaggerItem(
          index: 0,
          child: HomeRowView(kind: kind, content: content, animateEntrance: true),
        ),
      );
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    // Un'unica onda per tutto lo scheletro.
    return WfShimmer(
      child: ListView(
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, shellBarHeight + 32, 32, 32),
        children: [
          const SkeletonBox(height: 380),
          const SizedBox(height: 32),
          for (var row = 0; row < 2; row++) ...[
            const SkeletonBox(width: 240, height: 22),
            const SizedBox(height: 12),
            // Lista orizzontale ferma invece di una Row: nelle finestre
            // strette le locandine in più vengono ritagliate, non debordano.
            SizedBox(
              height: 240,
              child: ListView(
                scrollDirection: Axis.horizontal,
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < 6; i++) ...[
                    const SkeletonBox(width: 160, height: 240),
                    const SizedBox(width: 16),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

/// "Personalizza la Home", in fondo alle righe e nella Home vuota (spec M
/// §8.5).
class _CustomizeLink extends StatelessWidget {
  const _CustomizeLink();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: TextButton.icon(
          key: const Key('home-customize'),
          onPressed: () => openHomeSettings(context),
          icon: const Icon(LucideIcons.slidersHorizontal, size: 16),
          label: Text(AppLocalizations.of(context).homeCustomize),
        ),
      );
}
