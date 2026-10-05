import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/shimmer.dart';
import '../../ui/states.dart';
import '../search/search_controller.dart';
import 'requestable_poster_card.dart';
import 'requestables_controller.dart';
import 'requests_navigation.dart';
import 'requests_providers.dart';

/// "Da richiedere" in fondo alla ricerca (spec I §9.1): i titoli di Seerr
/// che la ricerca nella libreria non ha trovato. Senza la funzione, o senza
/// titoli da mostrare, non c'è.
class RequestablesSection extends ConsumerWidget {
  const RequestablesSection({super.key, required this.library});

  /// Cosa hanno trovato i risultati della libreria per il termine di adesso;
  /// `null` mentre la ricerca nella libreria è in corso (la sezione aspetta,
  /// per non mostrare doppioni).
  final LibraryMatches? library;

  /// Larghezza delle card, come quelle della libreria.
  static const cardWidth = 150.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(requestsAvailableProvider)) return const SizedBox.shrink();
    final state = ref.watch(requestablesControllerProvider);
    if (state.term.length < SearchController.minLength) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final matches = library;
    final titles = state.titles;
    final Widget body;
    if (state.error != null) {
      body = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(l.requestsSeerrDown,
                style: const TextStyle(color: WfColors.creamMuted)),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => ref
                .read(requestablesControllerProvider.notifier)
                .retry(language: Localizations.localeOf(context).languageCode),
            child: Text(l.retry),
          ),
        ],
      );
    } else if (titles == null || matches == null || state.loading) {
      // Mentre Seerr cerca il termine nuovo i titoli del vecchio non vanno
      // mostrati: non sono più quelli giusti, e si potrebbero aprire.
      body = const _RequestablesSkeleton(key: ValueKey('requestables-skeleton'));
    } else {
      final visible = visibleRequestables(titles, matches);
      if (visible.isEmpty) return const SizedBox.shrink();
      body = Wrap(
        spacing: 16,
        runSpacing: 24,
        children: [
          for (final title in visible)
            RequestablePosterCard(
              key: ValueKey('requestable-${title.mediaType.wire}-${title.tmdbId}'),
              title: title,
              width: cardWidth,
              onTap: () => openRequestable(context, title),
            ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.requestsSectionTitle, style: WfText.display(26)),
          const SizedBox(height: 4),
          Text(l.requestsSectionSubtitle,
              style: const TextStyle(color: WfColors.creamMuted)),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}

/// Locandine vuote mentre Seerr risponde: stessa griglia e stessa altezza
/// delle card vere (locandina, titolo, anno), così il resto non salta.
class _RequestablesSkeleton extends StatelessWidget {
  const _RequestablesSkeleton({super.key});

  /// Locandine nello scheletro.
  static const _count = 6;

  @override
  Widget build(BuildContext context) {
    return WfShimmer(
      child: Wrap(
        spacing: 16,
        runSpacing: 24,
        children: [
          for (var i = 0; i < _count; i++)
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonBox(
                    width: RequestablesSection.cardWidth,
                    height: RequestablesSection.cardWidth * 3 / 2),
                SizedBox(height: 8),
                SkeletonBox(width: 110, height: 12),
                SizedBox(height: 6),
                SkeletonBox(width: 40, height: 10),
              ],
            ),
        ],
      ),
    );
  }
}
