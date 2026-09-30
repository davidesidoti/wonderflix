import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/landscape_card.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import '../../ui/shimmer.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/states.dart';
import '../../ui/wf_switcher.dart';
import 'hero_carousel.dart';
import 'home_data.dart';

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

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final home = ref.watch(homeProvider);
    final (state, content) = home.when(
      loading: () => ('loading', const _HomeSkeleton()),
      error: (error, _) => (
        'error',
        ErrorView(error: error, onRetry: () => ref.invalidate(homeProvider)),
      ),
      data: (data) {
        if (data.isEmpty) {
          return (
            'empty',
            Center(
              child: Text(l.homeEmpty,
                  style: const TextStyle(color: WfColors.creamMuted)),
            ),
          );
        }
        // Righe presenti, nell'ordine: l'indice guida l'entrata scaglionata.
        final rows = <Widget>[
          if (data.resume.isNotEmpty)
            _landscapeRow(l.homeContinueWatching, data.resume, 'home.resume'),
          if (data.nextUp.isNotEmpty)
            _landscapeRow(l.homeNextUp, data.nextUp, 'home.nextUp'),
          if (data.latestMovies.isNotEmpty)
            _posterRow(
                l.homeLatestMovies, data.latestMovies, 'home.latestMovies'),
          if (data.latestSeries.isNotEmpty)
            _posterRow(
                l.homeLatestSeries, data.latestSeries, 'home.latestSeries'),
          if (data.favorites.isNotEmpty)
            _posterRow(l.navMyList, data.favorites, 'home.favorites'),
        ];
        return ('data', StaggerGroup(
          key: const Key('home-rows'),
          count: rows.length,
          stagger: homeRowStagger,
          play: _animate,
          onPlayed: () =>
              ref.read(homeEntrancePlayedProvider.notifier).markPlayed(),
          child: ListView(
            controller: _scroll,
            // Il carosello parte dal bordo della finestra, sotto la barra;
            // senza carosello la prima riga inizia sotto la barra.
            padding: EdgeInsets.only(
                top: data.featured.isEmpty ? shellBarHeight : 0, bottom: 40),
            children: [
              if (data.featured.isNotEmpty) HeroCarousel(items: data.featured),
              for (final (i, row) in rows.indexed)
                StaggerItem(index: i, child: row),
            ],
          ),
        ));
      },
    );
    return WfSwitcher(
      expand: true,
      child: KeyedSubtree(key: ValueKey(state), child: content),
    );
  }

  /// Riga di locandine. Nelle righe le card volano dentro con la riga, solo
  /// alla prima entrata della sessione: una riga ricostruita più tardi
  /// (scorrendo, dati aggiornati) è già entrata e le lascia ferme (vedi
  /// `StaggerGroup.nested`).
  Widget _posterRow(String title, List<JellyfinItem> items, String source) =>
      MediaRow(
        title: title,
        height: 300,
        itemCount: items.length,
        animateEntrance: _animate,
        itemBuilder: (context, i) => PosterCard(
          item: items[i],
          width: 160,
          heroSource: '$source.$i',
        ),
      );

  Widget _landscapeRow(String title, List<JellyfinItem> items, String source) =>
      MediaRow(
        title: title,
        height: 230,
        itemCount: items.length,
        animateEntrance: _animate,
        itemBuilder: (context, i) => LandscapeCard(
          item: items[i],
          heroSource: '$source.$i',
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
