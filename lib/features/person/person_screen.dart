import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/item_query.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
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

class PersonScreen extends ConsumerWidget {
  const PersonScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return ref.watch(itemProvider(personId)).when(
          loading: () => const LoadingView(),
          error: (error, _) => ErrorView(
              error: error, onRetry: () => ref.invalidate(itemProvider(personId))),
          data: (person) {
            final films = ref.watch(filmographyProvider(personId));
            final bio = person.overview;
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 200,
                            height: 300,
                            child: WfImage(
                              image: ref.watch(imageUrlsProvider).poster(person),
                              fallbackIcon: LucideIcons.user,
                            ),
                          ),
                        ),
                        const SizedBox(width: 32),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(person.name.toUpperCase(),
                                  style: WfText.display(48)),
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
                          onRetry: () => ref.invalidate(filmographyProvider(personId))),
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
                            onTap: () => openItem(context, items[i]),
                          ),
                          childCount: items.length,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
  }
}
