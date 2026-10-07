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
import '../../ui/wf_image.dart';
import '../../ui/wf_switcher.dart';
import '../detail/detail_backdrop.dart';
import '../detail/detail_header.dart';
import '../detail/detail_providers.dart';
import '../detail/header_parallax.dart';
import '../detail/primary_action.dart';
import '../library/library_providers.dart';
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

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(itemProvider(widget.collectionId));
    final collection = async.value;
    final (state, content) = async.when(
      loading: () =>
          ('loading', const DetailSkeleton(headerHeight: detailHeaderHeight)),
      error: (error, _) => (
        'error',
        ErrorView(
            error: error,
            onRetry: () => ref.invalidate(itemProvider(widget.collectionId))),
      ),
      data: (item) =>
          ('data', CollectionView(collection: item, controller: _scroll)),
    );
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: detailHeaderHeight,
          child: collection != null
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
  const CollectionView({super.key, required this.collection, this.controller});

  final JellyfinItem collection;

  /// Scroll della pagina (lo segue anche lo sfondo).
  final ScrollController? controller;

  /// Elementi della testata che entrano scaglionati (logo, conteggio,
  /// sinossi, pulsante).
  static const entranceCount = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(collectionItemsProvider(collection.id));
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
          else if (error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: ErrorView(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(collectionItemsProvider(collection.id))),
              ),
            )
          else
            const SliverToBoxAdapter(
              child: Padding(
                  padding: EdgeInsets.only(bottom: 40), child: LoadingView()),
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
    final logo = ref.watch(imageUrlsProvider).logo(collection);
    final list = items;
    final primary = action;
    final overview = collection.overview;
    final watched = list == null
        ? 0
        : watchedCount(list, (item) => watchUserData(ref, item));
    return SizedBox(
      height: detailHeaderHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [WfColors.bg, Color(0xD90A0A0A), Colors.transparent],
                stops: [0, 0.4, 0.8],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [WfColors.bg, Colors.transparent],
                stops: [0, 0.5],
              ),
            ),
          ),
          Positioned(
            left: 32,
            right: 32,
            bottom: detailHeaderTextBottom,
            child: HeaderScrollFade(
              controller: controller,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  StaggerItem(
                    index: 0,
                    child: logo != null
                        ? SizedBox(
                            height: 120,
                            width: 460,
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: WfImage(image: logo, fit: BoxFit.contain),
                            ),
                          )
                        : Text(collection.name.toUpperCase(),
                            maxLines: 2, style: WfText.display(56)),
                  ),
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
                        onPressed: () => unawaited(
                            playItem(context, ref, primary.target)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
