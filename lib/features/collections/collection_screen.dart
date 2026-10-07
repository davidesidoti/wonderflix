import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_shell.dart';
import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_switcher.dart';
import '../detail/detail_backdrop.dart';
import '../detail/detail_header.dart';
import '../detail/detail_providers.dart';
import '../detail/header_parallax.dart';
import '../detail/primary_action.dart';
import '../library/user_data.dart';
import '../playback/play_launcher.dart';
import 'collections_logic.dart';
import 'collections_providers.dart';

/// "Riprendi "Titolo"" o "Riproduci "Titolo"" (spec K §8.2).
String collectionActionLabel(AppLocalizations l, PrimaryAction action) =>
    switch (action) {
      ResumeAction() => l.collectionResume(action.target.name),
      PlayAction() => l.collectionPlay(action.target.name),
    };

/// Pagina di una saga, `/collection/:id` (spec K §8.2). Come la scheda di un
/// titolo: lo sfondo è un livello dietro, il contenuto sfuma tra caricamento,
/// errore e dati.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key, required this.collectionId});

  final String collectionId;

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  final _scroll = SmoothScrollController();

  /// Stato di caricamento: la saga o i suoi titoli non sono ancora arrivati.
  static const (String, Widget) _loading =
      ('loading', DetailSkeleton(headerHeight: detailHeaderHeight));

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(itemProvider(widget.collectionId));
    // I titoli partono insieme alla saga, non dopo: finché non sono arrivati
    // (o falliti) la pagina resta lo scheletro, e la testata non compare
    // senza conteggio e pulsante.
    final titles = ref.watch(collectionItemsProvider(widget.collectionId));
    final titlesSettled = titles.hasValue || titles.hasError;
    final collection = async.value;
    final (state, content) = async.when(
      loading: () => _loading,
      error: (error, _) => (
        'error',
        ErrorView(
            error: error,
            onRetry: () => ref.invalidate(itemProvider(widget.collectionId))),
      ),
      data: (item) => titlesSettled
          ? (
              'data',
              CollectionView(
                  collectionId: widget.collectionId,
                  collection: item,
                  controller: _scroll),
            )
          : _loading,
    );
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: detailHeaderHeight,
          // Lo sfondo entra con la testata, non prima.
          child: collection != null && state != 'loading'
              ? DetailBackdrop(
                  item: collection, launch: null, controller: _scroll)
              : const SizedBox.shrink(),
        ),
        Positioned.fill(
          child: WfSwitcher(
            expand: true,
            child: KeyedSubtree(key: ValueKey(state), child: content),
          ),
        ),
      ],
    );
  }
}

/// Testata e griglia dei titoli di una saga (spec K §8.2).
class CollectionView extends ConsumerWidget {
  const CollectionView({
    super.key,
    required this.collectionId,
    required this.collection,
    this.controller,
  });

  /// Id della rotta: la stessa chiave dei provider della pagina, che può
  /// non essere scritta come l'`Id` del server.
  final String collectionId;

  final JellyfinItem collection;

  /// Scroll della pagina (lo segue anche lo sfondo).
  final ScrollController? controller;

  /// Elementi della testata che entrano scaglionati (logo, conteggio,
  /// sinossi, pulsante).
  static const entranceCount = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(collectionItemsProvider(collectionId));
    final items = async.value;
    final error = async.error;
    final target = items == null
        ? null
        : sagaTarget(items, (item) => watchUserData(ref, item));
    final action =
        target == null ? null : primaryActionFor(target, watchUserData(ref, target));
    final page = StaggerGroup(
      count: entranceCount,
      child: CustomScrollView(
        controller: controller,
        slivers: [
          SliverToBoxAdapter(
            child: CollectionHeader(
                collection: collection,
                items: items,
                action: action,
                controller: controller),
          ),
          if (items != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.55,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) =>
                      PosterCard(item: items[i], heroSource: 'collection.$i'),
                  childCount: items.length,
                ),
              ),
            )
          // Con un nuovo tentativo in corso si torna allo scheletro: l'errore
          // di prima resta nello stato, ma non è più quello che si vede.
          else if (error != null && !async.isLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: ErrorView(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(collectionItemsProvider(collectionId))),
              ),
            )
          else
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: PosterGridSkeleton(count: 6, shrinkWrap: true),
              ),
            ),
        ],
      ),
    );
    final scroll = controller;
    // Senza controller (vista montata da sola) niente titolo nella barra.
    if (scroll == null) return page;
    final reduced = WfMotion.of(context).isReduced;
    return ShellHeaderPublisher(
      controller: scroll,
      visibleAt: (offset) => barTitleVisible(offset, reduced: reduced),
      header: ShellHeader(
        title: collection.name,
        actionLabel: action == null ? null : collectionActionLabel(l, action),
        onAction: action == null
            ? null
            : () => unawaited(playItem(context, ref, action.target)),
      ),
      child: page,
    );
  }
}

/// Parte alta della pagina di una saga (spec K §8.2): logo o nome,
/// "N film · M visti", sinossi e pulsante principale. Lo sfondo è dietro
/// alla pagina (`DetailBackdrop`), come nella scheda di un titolo.
class CollectionHeader extends ConsumerWidget {
  const CollectionHeader({
    super.key,
    required this.collection,
    required this.items,
    required this.action,
    this.controller,
  });

  final JellyfinItem collection;

  /// `null` finché i titoli non sono arrivati.
  final List<JellyfinItem>? items;

  /// `null` senza titoli.
  final PrimaryAction? action;

  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final list = items;
    final primary = action;
    final overview = collection.overview;
    final watched = list == null
        ? 0
        : watchedCount(list, (item) => watchUserData(ref, item));
    return DetailHeaderFrame(
      controller: controller,
      children: [
        StaggerItem(index: 0, child: HeaderTitle(item: collection)),
        if (list != null) ...[
          const SizedBox(height: 12),
          StaggerItem(
            index: 1,
            child: Text(
                '${l.collectionFilmCount(list.length)} · '
                '${l.collectionWatched(watched)}',
                style: const TextStyle(color: WfColors.creamMuted)),
          ),
        ],
        if (overview != null) ...[
          const SizedBox(height: 12),
          StaggerItem(
            index: 2,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Text(overview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.45)),
            ),
          ),
        ],
        if (primary != null) ...[
          const SizedBox(height: 20),
          StaggerItem(
            index: 3,
            child: WfButton.primary(
              label: collectionActionLabel(l, primary),
              icon: LucideIcons.play,
              onPressed: () =>
                  unawaited(playItem(context, ref, primary.target)),
            ),
          ),
        ],
      ],
    );
  }
}
