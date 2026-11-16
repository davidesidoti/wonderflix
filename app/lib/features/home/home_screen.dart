import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_shell.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/media_row.dart';
import '../../ui/shimmer.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/ticket_card.dart';
import '../../ui/wf_switcher.dart';
import '../match/match_actions.dart';
import '../match/match_entry.dart';
import '../settings/home_settings_section.dart';
import '../tonight/tonight_dialog.dart';
import 'hero_carousel.dart';
import 'home_glow.dart';
import 'home_layout.dart';
import 'home_providers.dart';
import 'home_row_content.dart';
import 'home_row_view.dart';
import 'home_sections.dart';
import 'tonight_row.dart';

/// L'entrata delle righe della Home si vede una volta per sessione
/// (decisione 6b): tornando alla Home dalla barra non si ripete.
class HomeEntrancePlayed extends Notifier<bool> {
  @override
  bool build() => false;

  void markPlayed() => state = true;
}

final homeEntrancePlayedProvider = NotifierProvider<HomeEntrancePlayed, bool>(
  HomeEntrancePlayed.new,
);

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

  /// Le sezioni arrivate quando la Home si è aperta (per `HomeSection.id`),
  /// con il loro posto nell'entrata scaglionata; `null` finché non si è
  /// aperta. Una sezione unita entra con la prima delle sue righe arrivata:
  /// l'altra si aggiunge al suo posto, senza un'altra entrata.
  Map<String, int>? _entrance;

  /// Le righe dell'ultima costruzione: quando scade [homeRevealWait] si apre
  /// con queste, senza leggere altri provider (la composizione potrebbe
  /// essere cambiata un attimo prima della prossima costruzione).
  Map<HomeRowKind, AsyncValue<HomeRowContent>>? _rows;

  /// Le sezioni arrivate dopo l'apertura che hanno già fatto la loro
  /// entrata: la lista smonta le righe lontane e le ricostruisce scorrendo,
  /// e allora non devono rifarla.
  final _lateEntered = <String>{};

  /// Il titolo mostrato dal carosello, per l'alone; `null` = il primo (il
  /// carosello non avvisa per il primo).
  final _glowId = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _revealTimer?.cancel();
    _scroll.dispose();
    _glowId.dispose();
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

  /// Una riga arrivata con qualcosa (non vuota, non in errore).
  static bool _filled(AsyncValue<HomeRowContent>? row) =>
      !(row?.value?.isEmpty ?? true);

  /// Apre la Home: entrano insieme le sezioni già arrivate che si vedono
  /// (non quelle vuote o in errore), nell'ordine e senza buchi. [rows] è
  /// nell'ordine della composizione.
  void _open(Map<HomeRowKind, AsyncValue<HomeRowContent>> rows) {
    _revealTimer?.cancel();
    _revealTimer = null;
    var index = 0;
    _entrance = {
      for (final section in homeSections(rows.keys.toList()))
        if (section.rows.any((kind) => _filled(rows[kind])))
          section.id: index++,
    };
  }

  void _onRevealTimeout() {
    final rows = _rows;
    if (!mounted || rows == null) return;
    setState(() => _open(rows));
  }

  /// "Cosa guardo stasera?": con il contesto e il `ref` della Home, che
  /// restano montati anche se il carosello prende il posto del pulsante a
  /// finestra aperta (la scelta si fa quando la finestra si chiude).
  void _openTonight() => unawaited(openTonight(context, ref));

  /// "Match": con il contesto della Home, come "Cosa guardo stasera?".
  void _openMatch() => unawaited(openMatchRoom(context, ref));

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

  (String, Widget) _content(
    AppLocalizations l,
    HomeLayout layout,
    AsyncValue<List<JellyfinItem>> featured,
  ) {
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
    final tv = FormFactor.of(context).tv;
    List<JellyfinItem> itemsOf(HomeRowKind kind) => switch (rows[kind]?.value) {
      ItemsRowContent(:final items) => items,
      _ => const [],
    };
    // Stasera c'è se ha almeno un biglietto (non tutti tolti). Senza le due
    // righe non si leggono le serie tolte.
    final hasTonight = (layout.visible.contains(HomeRowKind.resume) ||
            layout.visible.contains(HomeRowKind.nextUp)) &&
        watchTonightTickets(ref,
                resume: itemsOf(HomeRowKind.resume),
                nextUp: itemsOf(HomeRowKind.nextUp))
            .isNotEmpty;
    final shown = <Widget>[
      for (final section in homeSections(layout.visible))
        if (section.rows.any((kind) => _filled(rows[kind])))
          _section(section, rows, itemsOf, entrance[section.id], tv: tv),
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
              Text(
                l.homeEmpty,
                style: const TextStyle(color: WfColors.creamMuted),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _EntryButtons(
                  onTonight: _openTonight,
                  onMatch: _openMatch,
                ),
              ),
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
        child: Stack(
          children: [
            if (featuredItems.isNotEmpty) _glow(featuredItems),
            _list(featuredItems, shown, tv: tv, hasTonight: hasTonight),
          ],
        ),
      ),
    );
  }

  Widget _list(List<JellyfinItem> featuredItems, List<Widget> shown,
          {required bool tv, required bool hasTonight}) =>
      ListView(
          controller: _scroll,
          // Il carosello parte dal bordo della finestra, sotto la barra;
          // senza carosello la prima riga inizia sotto la barra.
          padding: EdgeInsets.only(
            top: featuredItems.isEmpty ? shellBarHeight : 0,
            bottom: 40,
          ),
          children: [
            if (featuredItems.isNotEmpty)
              HeroCarousel(
                items: featuredItems,
                extraAction: tv
                    ? TonightButton(short: true, onPressed: _openTonight)
                    : null,
                autofocusPlay: !hasTonight,
                onCurrentChanged: (item) => _glowId.value = item.id,
              ),
            // Senza Stasera Match e il dado stanno sopra le righe, a destra;
            // in TV "Stasera?" è già nel carosello.
            if (!hasTonight && !(tv && featuredItems.isNotEmpty))
              _TonightCorner(onTonight: _openTonight, onMatch: _openMatch),
            ...shown,
            const Align(
              alignment: Alignment.centerLeft,
              child: _CustomizeLink(),
            ),
          ],
        );

  /// L'alone (spec §5.4): dietro la lista, sotto il carosello, e scorre con
  /// lei. Non è un figlio della lista: la lista non dipinge un figlio uscito
  /// dallo schermo, e l'alone sparirebbe di colpo appena il carosello esce.
  Widget _glow(List<JellyfinItem> items) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: homeGlowHeight,
        child: IgnorePointer(
          child: ListenableBuilder(
            listenable: Listenable.merge([_scroll, _glowId]),
            builder: (context, _) {
              final offset = _scroll.hasClients ? _scroll.offset : 0.0;
              final id = _glowId.value;
              return Transform.translate(
                offset: Offset(0, HeroCarousel.heightOf(context) - offset),
                child: HomeGlow(
                  item: items.firstWhere((item) => item.id == id,
                      orElse: () => items.first),
                ),
              );
            },
          ),
        ),
      );

  /// Una sezione arrivata all'apertura entra con le altre; una arrivata dopo
  /// entra da sola, al suo posto (decisione 6 del piano 19b).
  Widget _section(
    HomeSection section,
    Map<HomeRowKind, AsyncValue<HomeRowContent>> rows,
    List<JellyfinItem> Function(HomeRowKind) itemsOf,
    int? index, {
    required bool tv,
  }) {
    final late = index == null;
    final animate = late || _animate;
    Widget row(HomeRowKind kind) => HomeRowView(
        kind: kind, content: rows[kind]!.value!, animateEntrance: animate);
    final child = switch (section) {
      RowSection(:final kind) => row(kind),
      TonightSection() => TonightRow(
          resume: itemsOf(HomeRowKind.resume),
          nextUp: itemsOf(HomeRowKind.nextUp),
          onTonight: _openTonight,
          onMatch: _openMatch,
          animateEntrance: animate,
          autofocusFirst: tv,
        ),
      // shortcut: fino alla settimana di In arrivo, le due righe di oggi una
      // sotto l'altra.
      UpcomingSection(rows: final kinds) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final kind in kinds)
              if (_filled(rows[kind])) row(kind),
          ],
        ),
    };
    final id = section.id;
    if (late) {
      return _LateRow(
        key: ValueKey('home-late-$id'),
        id: id,
        entered: _lateEntered,
        onPlayed: () {
          _lateEntered.add(id);
          // Se la Home si è aperta senza righe, questa è l'entrata della
          // sessione: la prossima visita non la rifà.
          ref.read(homeEntrancePlayedProvider.notifier).markPlayed();
        },
        child: child,
      );
    }
    return StaggerItem(
        key: ValueKey('home-row-$id'), index: index, child: child);
  }
}

/// Una sezione arrivata dopo l'apertura, con una sua piccola entrata
/// (decisione 6 del piano 19b). Entra una volta sola: la lista smonta le
/// righe lontane e le rimonta scorrendo, con lo stesso widget di prima,
/// quindi se la sezione è già entrata ([entered]) lo si decide qui, a ogni
/// montaggio, e non alla costruzione della Home.
class _LateRow extends StatelessWidget {
  const _LateRow({
    super.key,
    required this.id,
    required this.entered,
    required this.onPlayed,
    required this.child,
  });

  final String id;
  final Set<String> entered;
  final VoidCallback onPlayed;
  final Widget child;

  @override
  Widget build(BuildContext context) => StaggerGroup(
    count: 1,
    play: !entered.contains(id),
    onPlayed: onPlayed,
    child: StaggerItem(index: 0, child: child),
  );
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    // La forma della pagina vera sul suo schermo (spec §11): il carosello a
    // tutta larghezza dal bordo alto, poi una fila di biglietti e una di
    // locandine.
    final side = FormFactor.of(context).compact ? 16.0 : 32.0;
    final ticket = ticketSize(context);
    final poster = rowPosterSize(context).width;
    // Lista orizzontale ferma invece di una Row: nelle finestre strette le
    // card in più vengono ritagliate, non debordano.
    Widget strip(double width, double height) => SizedBox(
          height: height,
          child: ListView(
            scrollDirection: Axis.horizontal,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: side),
            children: [
              for (var i = 0; i < 6; i++) ...[
                SkeletonBox(width: width, height: height),
                const SizedBox(width: 16),
              ],
            ],
          ),
        );
    Widget title() => Padding(
          padding: EdgeInsets.fromLTRB(side, 28, side, 12),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(width: 240, height: 22),
          ),
        );
    // Un'unica onda per tutto lo scheletro.
    return WfShimmer(
      child: ListView(
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SkeletonBox(height: HeroCarousel.heightOf(context), radius: 0),
          title(),
          strip(ticket.width, ticket.height),
          title(),
          strip(poster, poster * 1.5),
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

/// Match e il dado in cima alle righe, a destra, quando Stasera non c'è
/// (spec §6.3).
class _TonightCorner extends StatelessWidget {
  const _TonightCorner({required this.onTonight, required this.onMatch});

  final VoidCallback onTonight;
  final VoidCallback onMatch;

  @override
  Widget build(BuildContext context) {
    final side = FormFactor.of(context).compact ? 16.0 : 32.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 16, side, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Text(
              AppLocalizations.of(context).homeUndecided,
              style: const TextStyle(color: WfColors.creamMuted, fontSize: 13),
            ),
            _EntryButtons(onTonight: onTonight, onMatch: onMatch),
          ],
        ),
      ),
    );
  }
}

/// "Match" e "Cosa guardo stasera?" uno accanto all'altro (spec P §7.2).
class _EntryButtons extends StatelessWidget {
  const _EntryButtons({required this.onTonight, required this.onMatch});

  final VoidCallback onTonight;
  final VoidCallback onMatch;

  @override
  // Wrap: in una finestra stretta il secondo va a capo invece di sbordare.
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      // Match è fuori dalla TV.
      if (!FormFactor.of(context).tv) MatchButton(onPressed: onMatch),
      TonightButton(onPressed: onTonight),
    ],
  );
}
