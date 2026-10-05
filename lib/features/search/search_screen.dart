import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/poster_card.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/wf_image.dart';
import '../../ui/wf_switcher.dart';
import '../library/library_providers.dart';
import '../requests/requestables_controller.dart';
import '../requests/requestables_section.dart';
import 'search_controller.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(32),
      children: [
        TextField(
          autofocus: true,
          onChanged: (value) {
            controller.setTerm(value);
            ref.read(requestablesControllerProvider.notifier).setTerm(value,
                language: Localizations.localeOf(context).languageCode);
          },
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            hintText: l.searchHint,
            prefixIcon: const Icon(LucideIcons.search, color: WfColors.creamMuted),
          ),
        ),
        const SizedBox(height: 24),
        WfSwitcher(child: _results(context, l, state)),
        RequestablesSection(libraryIds: _libraryIds(state)),
      ],
    );
  }

  /// Risultati, con una chiave per stato (per [WfSwitcher]).
  Widget _results(BuildContext context, AppLocalizations l, SearchState state) {
    const muted = TextStyle(color: WfColors.creamMuted);
    if (state.term.length < SearchController.minLength) {
      return Text(l.searchPrompt, key: const ValueKey('prompt'), style: muted);
    }
    final error = state.error;
    if (error != null) {
      return ErrorView(
        key: const ValueKey('error'),
        error: error,
        onRetry: () =>
            ref.read(searchControllerProvider.notifier).setTerm(state.term),
      );
    }
    final results = state.results;
    if (results == null) {
      return const SearchResultsSkeleton(key: ValueKey('loading'));
    }
    if (results.isEmpty) {
      return Text(l.searchNoResults(state.term),
          key: const ValueKey('empty'), style: muted);
    }
    return Column(
      key: const ValueKey('data'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (results.movies.isNotEmpty)
          _posterSection(
              l.navMovies, results.movies, 'search.movies', results),
        if (results.series.isNotEmpty)
          _posterSection(
              l.navSeries, results.series, 'search.series', results),
        if (results.people.isNotEmpty) _peopleSection(context, l, results.people),
      ],
    );
  }

  /// Id dei film e delle serie trovati nella libreria, in minuscolo, per
  /// non ripeterli in "Da richiedere"; `null` mentre la ricerca è in corso.
  /// Con un errore della libreria la sezione non aspetta.
  static Set<String>? _libraryIds(SearchState state) {
    if (state.error != null) return const {};
    final results = state.results;
    if (state.loading || results == null) return null;
    return {
      for (final item in [...results.movies, ...results.series])
        item.id.toLowerCase(),
    };
  }

  /// Sezione di locandine; le card entrano di nuovo a ogni ricerca
  /// completata ([results]), non a ogni lettera (mentre si scrive restano
  /// i risultati di prima).
  Widget _posterSection(String title, List<JellyfinItem> items, String source,
          SearchResults results) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: WfText.display(26)),
            const SizedBox(height: 12),
            BatchedEntrance(
              itemCount: items.length,
              resetKey: results,
              child: Wrap(
                spacing: 16,
                runSpacing: 24,
                children: [
                  for (final (i, item) in items.indexed)
                    BatchedEntranceItem(
                      index: i,
                      child: PosterCard(
                          item: item, width: 150, heroSource: '$source.$i'),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _peopleSection(
      BuildContext context, AppLocalizations l, List<JellyfinItem> people) {
    final urls = ref.watch(imageUrlsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.searchPeople, style: WfText.display(26)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final person in people)
              GestureDetector(
                onTap: () => openItem(context, person),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: SizedBox(
                    width: 110,
                    child: Column(
                      children: [
                        ClipOval(
                          child: SizedBox(
                            width: 90,
                            height: 90,
                            child: WfImage(
                                image: urls.poster(person),
                                fallbackIcon: LucideIcons.user),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(person.name,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
