import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../library/library_providers.dart';
import 'search_best.dart';

/// Apre la pagina con tutte le persone trovate per [term]: con push, così
/// Indietro torna a Cerca coi risultati.
void openPeopleSearch(BuildContext context, String term) => unawaited(
    context.push(Uri(path: '/people', queryParameters: {'q': term}).toString()));

class PeopleSearchState {
  const PeopleSearchState({
    this.items = const [],
    this.total = 0,
    this.loading = false,
    this.error,
  });

  final List<JellyfinItem> items;
  final int total;
  final bool loading;
  final Object? error;

  bool get hasMore => items.length < total;
}

/// Le persone di un termine, cento per volta.
class PeopleSearchController extends Notifier<PeopleSearchState> {
  PeopleSearchController(this.term);

  final String term;

  static const pageSize = 100;

  int _generation = 0;
  CancelToken? _cancel;

  @override
  PeopleSearchState build() {
    ref.onDispose(() => _cancel?.cancel());
    // Non si cambia stato dentro build: la prima pagina parte subito dopo.
    unawaited(Future.microtask(_load));
    return const PeopleSearchState(loading: true);
  }

  Future<void> loadMore() async {
    // Dopo un errore si riprova solo dal pulsante, non a ogni scroll.
    if (state.loading || !state.hasMore || state.error != null) return;
    await _load();
  }

  Future<void> retry() => _load();

  /// Carica la pagina dopo quelle che ci sono già.
  Future<void> _load() async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    final previous = state.items;
    state = PeopleSearchState(items: previous, total: state.total, loading: true);
    try {
      final page = await ref.read(libraryApiProvider).searchPeople(
            ref.read(currentUserIdProvider),
            term,
            startIndex: previous.length,
            limit: pageSize,
            cancelToken: cancel,
          );
      if (!ref.mounted || generation != _generation) return;
      state = PeopleSearchState(
          items: [...previous, ...page.items], total: page.totalCount);
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = PeopleSearchState(
          items: previous, total: state.total, error: error);
    }
  }
}

final peopleSearchControllerProvider = NotifierProvider.autoDispose
    .family<PeopleSearchController, PeopleSearchState, String>(
        PeopleSearchController.new);

/// Tutte le persone trovate da Cerca (spec §8.4): la griglia del catalogo di
/// tondi col nome, senza dati per persona.
class PeopleSearchScreen extends ConsumerStatefulWidget {
  const PeopleSearchScreen({super.key, required this.term});

  final String term;

  @override
  ConsumerState<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends ConsumerState<PeopleSearchScreen> {
  final _scroll = SmoothScrollController();

  /// Numero di persone all'ultimo caricamento automatico: evita un ciclo
  /// infinito se il server risponde con pagine vuote.
  int _autoLoadedAt = -1;

  PeopleSearchController get _controller =>
      ref.read(peopleSearchControllerProvider(widget.term).notifier);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 800) unawaited(_controller.loadMore());
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final provider = peopleSearchControllerProvider(widget.term);
    final state = ref.watch(provider);
    final form = FormFactor.of(context);
    final tv = form.tv;
    final side = tv ? 24.0 : (form.compact ? 16.0 : 32.0);
    // Su schermi grandi la prima pagina può non riempire la finestra: senza
    // scroll non scatterebbe mai il caricamento successivo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final current = ref.read(provider);
      if (_scroll.position.extentAfter < 800 &&
          current.hasMore &&
          !current.loading &&
          current.error == null &&
          current.items.length != _autoLoadedAt) {
        _autoLoadedAt = current.items.length;
        unawaited(_controller.loadMore());
      }
    });
    final error = state.error;
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, 32, side, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(l.searchPeople,
                    style: WfText.display(tv ? 22 : (form.compact ? 26 : 30))),
                const SizedBox(width: 10),
                if (state.total > 0)
                  Text('${state.total}',
                      style: const TextStyle(
                          color: WfColors.creamMuted,
                          fontSize: 12.5,
                          fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, 16, side, 0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              crossAxisSpacing: 16,
              mainAxisSpacing: 24,
              // Tondo 72, spazio, nome su due righe e una riga di scorta.
              mainAxisExtent:
                  80 + MediaQuery.textScalerOf(context).scale(56),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => SearchPersonTile(
                key: ValueKey('person-${state.items[i].id}'),
                person: state.items[i],
                term: widget.term,
                onOpened: () {},
              ),
              childCount: state.items.length,
            ),
          ),
        ),
        // Altezza fissa col caricamento o senza: l'elenco non salta quando
        // arriva una pagina.
        SliverToBoxAdapter(
          child: error != null
              ? ErrorView(
                  error: error, onRetry: () => unawaited(_controller.retry()))
              : SizedBox(
                  height: 64,
                  child: state.loading
                      ? const Align(
                          alignment: Alignment.topCenter,
                          child: LinearProgressIndicator(minHeight: 2))
                      : null),
        ),
      ],
    );
  }
}
