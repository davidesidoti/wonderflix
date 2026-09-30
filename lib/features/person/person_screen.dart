import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/hero_launch.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/wf_image.dart';
import '../detail/detail_providers.dart';
import '../library/library_providers.dart';

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
          : const LoadingView();
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
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WfHero(
                  tag: launch?.tag,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 200,
                    height: 300,
                    child: WfImage(image: photo, fallbackIcon: LucideIcons.user),
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.toUpperCase(), style: WfText.display(48)),
                      if (bio != null) ...[
                        const SizedBox(height: 12),
                        Text(bio,
                            maxLines: 10,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(height: 1.5)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (films == null)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(32), child: LoadingView()),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
            sliver: SliverToBoxAdapter(
              child: Text(l.personOnServer, style: WfText.display(28)),
            ),
          ),
          ...films.when(
            loading: () => const [SliverToBoxAdapter(child: LoadingView())],
            error: (error, _) => [
              SliverToBoxAdapter(
                child: ErrorView(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(filmographyProvider(widget.personId))),
              ),
            ],
            data: (items) => [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 24,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.55,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => PosterCard(
                      item: items[i],
                      heroSource: 'person.$i',
                    ),
                    childCount: items.length,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
