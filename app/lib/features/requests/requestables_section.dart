import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/shimmer.dart';
import '../../ui/form_factor.dart';
import '../../ui/media_row.dart';
import '../../ui/states.dart';
import '../search/search_controller.dart';
import 'requestable_poster_card.dart';
import 'requestables_controller.dart';
import 'requests_navigation.dart';
import 'requests_providers.dart';

/// "Da richiedere" in fondo alla ricerca (spec I §9.1, revisione §8.2): i
/// titoli di Seerr che la ricerca nella libreria non ha trovato, in una fila.
/// Senza la funzione, o senza titoli da mostrare, non c'è.
class RequestablesSection extends ConsumerWidget {
  const RequestablesSection({
    super.key,
    required this.library,
    this.term = '',
    this.onOpened,
  });

  /// Cosa hanno trovato i risultati della libreria per il termine di adesso;
  /// `null` mentre la ricerca nella libreria è in corso (la sezione aspetta,
  /// per non mostrare doppioni).
  final LibraryMatches? library;

  /// Il termine cercato, sottolineato nei titoli.
  final String term;

  /// Prima di aprire un titolo (la ricerca salva il termine).
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(requestsAvailableProvider)) return const SizedBox.shrink();
    final state = ref.watch(requestablesControllerProvider);
    if (state.term.length < SearchController.minLength) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final titleSize = form.tv ? 22.0 : (form.compact ? 26.0 : 30.0);
    final size = rowPosterSize(context);
    Widget row(Key key, int count, IndexedWidgetBuilder builder) => MediaRow(
          key: key,
          title: l.requestsSectionTitle,
          subtitle: l.requestsSectionSubtitle,
          titleSize: titleSize,
          topSpacing: 0,
          side: 0,
          height: size.rowHeight + RequestablePosterCard.statusHeight,
          itemCount: count,
          itemBuilder: builder,
        );
    final matches = library;
    final titles = state.titles;
    final Widget body;
    if (state.error != null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.requestsSectionTitle, style: WfText.display(titleSize)),
          const SizedBox(height: 4),
          Text(l.requestsSectionSubtitle,
              style: const TextStyle(color: WfColors.creamMuted)),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(l.requestsSeerrDown,
                    style: const TextStyle(color: WfColors.creamMuted)),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                // Su oro sottile il bordo oro largo 2 si distingue poco: crema.
                style: ButtonStyle(
                    side: tvButtonSide(form.tv,
                        const BorderSide(color: WfColors.gold), tvFocusSideOnGold)),
                onPressed: () => ref
                    .read(requestablesControllerProvider.notifier)
                    .retry(
                        language: Localizations.localeOf(context).languageCode),
                child: Text(l.retry),
              ),
            ],
          ),
        ],
      );
    } else if (titles == null || matches == null || state.loading) {
      // Mentre Seerr cerca il termine nuovo i titoli del vecchio non vanno
      // mostrati: non sono più quelli giusti, e si potrebbero aprire.
      body = row(const ValueKey('requestables-skeleton'), 6,
          (context, _) => _SkeletonCard(width: size.width));
    } else {
      final visible = visibleRequestables(titles, matches);
      if (visible.isEmpty) return const SizedBox.shrink();
      body = row(const ValueKey('requestables-row'), visible.length,
          (context, i) {
        final title = visible[i];
        return RequestablePosterCard(
          key: ValueKey('requestable-${title.mediaType.wire}-${title.tmdbId}'),
          title: title,
          width: size.width,
          term: term,
          onTap: () {
            onOpened?.call();
            openRequestable(context, title);
          },
        );
      });
    }
    return Padding(padding: const EdgeInsets.only(bottom: 32), child: body);
  }
}

/// Una locandina vuota mentre Seerr risponde: stessa misura delle card vere
/// (locandina, titolo, anno e stato), così il resto non salta.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return WfShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBox(width: width, height: width * 3 / 2),
          const SizedBox(height: 8),
          SkeletonBox(width: width * 0.7, height: 12),
          const SizedBox(height: 6),
          const SkeletonBox(width: 60, height: 10),
          const SizedBox(height: 8),
          const SkeletonBox(width: 76, height: 22),
        ],
      ),
    );
  }
}
