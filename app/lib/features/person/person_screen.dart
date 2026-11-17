import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/hero_launch.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/expandable_text.dart';
import '../../ui/form_factor.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../detail/detail_providers.dart';
import '../library/library_providers.dart';
import '../requests/requests_navigation.dart';
import '../requests/requests_providers.dart';

/// Film e serie del server in cui compare la persona, dal più recente.
final filmographyProvider =
    FutureProvider.autoDispose.family<List<JellyfinItem>, String>((ref, personId) async {
  final page = await ref.watch(libraryApiProvider).items(
        ItemQuery(
          kinds: const {ItemKind.movie, ItemKind.series},
          sort: CatalogSort.year,
          personId: personId,
        ),
        userId: ref.watch(currentUserIdProvider),
        startIndex: 0,
        limit: 200,
      );
  return page.items;
});

class PersonScreen extends ConsumerStatefulWidget {
  const PersonScreen({super.key, required this.personId, this.launch});

  final String personId;

  /// Dati del volo Hero dal volto del cast (`extra` di go_router).
  final HeroLaunch? launch;

  @override
  ConsumerState<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends ConsumerState<PersonScreen> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(itemProvider(widget.personId));
    final person = async.value;
    final launch = widget.launch;
    if (person == null && (launch == null || async.hasError)) {
      return async.hasError
          ? ErrorView(
              error: async.error!,
              onRetry: () => ref.invalidate(itemProvider(widget.personId)))
          : const PersonSkeleton();
    }
    // La testata (foto, nome, biografia) sta sempre nella stessa posizione
    // dell'albero: con un volo in arrivo la foto (Hero) c'è già mentre la
    // persona carica.
    final photo = person != null
        ? ref.watch(imageUrlsProvider).poster(person)
        : launch!.image;
    final name = person?.name ?? launch?.title ?? '';
    final bio = person?.overview;
    final films =
        person == null ? null : ref.watch(filmographyProvider(widget.personId));
    // Nello stretto la foto sta sopra il nome, più piccola (non in TV).
    final form = FormFactor.of(context);
    final compact = form.compact && !form.tv;
    final tv = form.tv;
    final side = compact ? 16.0 : 32.0;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name.toUpperCase(), style: WfText.display(compact ? 28 : 48)),
        if (bio != null) ...[
          const SizedBox(height: 12),
          // L'InkWell di "Altro" vuole un Material sopra.
          Material(
            type: MaterialType.transparency,
            child: ExpandableText(bio,
                maxLines: 4,
                tvFocusable: tv,
                style: const TextStyle(height: 1.5)),
          ),
        ],
      ],
    );
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, 32, side, 0),
          sliver: SliverToBoxAdapter(
            child: Flex(
              direction: compact ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WfHero(
                  tag: launch?.tag,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: compact ? 140 : 200,
                    height: compact ? 210 : 300,
                    child: WfImage(image: photo, fallbackIcon: LucideIcons.user),
                  ),
                ),
                const SizedBox(width: 32, height: 16),
                // Nello stretto niente Expanded: la colonna è sull'asse che
                // scorre.
                if (compact) details else Expanded(child: details),
              ],
            ),
          ),
        ),
        if (films == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 32),
              child: PosterGridSkeleton(count: 6, shrinkWrap: true),
            ),
          )
        else
          ...films.when(
            loading: () => [
              _title(l, side),
              const SliverToBoxAdapter(
                  child: PosterGridSkeleton(count: 6, shrinkWrap: true)),
            ],
            error: (error, _) => [
              _title(l, side),
              SliverToBoxAdapter(
                child: ErrorView(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(filmographyProvider(widget.personId))),
              ),
            ],
            data: (items) => items.isEmpty
                ? [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(side, 32, side, 32),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.personNoTitles,
                                style:
                                    const TextStyle(color: WfColors.creamMuted)),
                            if (ref.watch(requestsAvailableProvider)) ...[
                              const SizedBox(height: 16),
                              WfButton.secondary(
                                label: l.personSearchRequests,
                                icon: LucideIcons.search,
                                onPressed: () => openRequests(context),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ]
                : tv
                    ? [
                        SliverToBoxAdapter(
                          child: MediaRow(
                            title: l.personOnServer,
                            side: 32,
                            titleSize: 28,
                            height: rowPosterSize(context).rowHeight,
                            itemCount: items.length,
                            itemBuilder: (context, i) => PosterCard(
                              item: items[i],
                              width: rowPosterSize(context).width,
                              heroSource: 'person.$i',
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
                      ]
                    : [
                        _title(l, side),
                        BatchedEntrance(
                          itemCount: items.length,
                          child: SliverPadding(
                            padding: EdgeInsets.fromLTRB(side, 0, side, 32),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 180,
                                mainAxisSpacing: 24,
                                crossAxisSpacing: 16,
                                childAspectRatio: 0.55,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) => BatchedEntranceItem(
                                  index: i,
                                  child: PosterCard(
                                    item: items[i],
                                    heroSource: 'person.$i',
                                  ),
                                ),
                                childCount: items.length,
                              ),
                            ),
                          ),
                        ),
                      ],
          ),
      ],
    );
  }

  Widget _title(AppLocalizations l, double side) => SliverPadding(
        padding: EdgeInsets.fromLTRB(side, 32, side, 16),
        sliver: SliverToBoxAdapter(
          child: Text(l.personOnServer, style: WfText.display(28)),
        ),
      );
}
