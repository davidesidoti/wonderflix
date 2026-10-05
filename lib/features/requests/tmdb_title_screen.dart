import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../core/requests/tmdb_images.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/backdrop_image.dart';
import '../../ui/skeletons.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_switcher.dart';
import '../detail/detail_header.dart';
import '../library/item_labels.dart';
import 'request_title_controller.dart';
import 'requests_providers.dart';
import 'season_picker.dart';

/// L'etichetta al posto di Richiedi (spec I §9.2); `null` se non serve.
String? titleStatusLabel(AppLocalizations l, TitleDetails details) =>
    switch (details.status) {
      TitleStatus.pending => details.requestedByMe
          ? l.requestsRequestedByYou
          : l.requestsBadgeRequested,
      TitleStatus.processing => l.requestsBadgeComing,
      TitleStatus.partial => l.requestsPartlyAvailable,
      TitleStatus.none => details.requested
          ? (details.requestedByMe
              ? l.requestsRequestedByYou
              : l.requestsBadgeRequested)
          : null,
      TitleStatus.available => null,
    };

/// La scheda di un titolo che non è (tutto) nella libreria (spec I §9.2):
/// dati di Seerr, Richiedi e, per le serie, le stagioni.
class TmdbTitleScreen extends ConsumerWidget {
  const TmdbTitleScreen({super.key, required this.type, required this.tmdbId});

  /// La scheda di una rotta `/tmdb/:type/:tmdbId`; `null` se tipo o id non
  /// valgono.
  static TmdbTitleScreen? fromRoute(String? type, String? tmdbId, {Key? key}) {
    final mediaType = RequestMediaType.tryParse(type);
    final id = int.tryParse(tmdbId ?? '');
    if (mediaType == null || id == null || id <= 0) return null;
    return TmdbTitleScreen(key: key, type: mediaType, tmdbId: id);
  }

  final RequestMediaType type;
  final int tmdbId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleKey = (
      type: type,
      tmdbId: tmdbId,
      language: Localizations.localeOf(context).languageCode,
    );
    final provider = requestTitleControllerProvider(titleKey);
    final state = ref.watch(provider);
    // I permessi partono insieme alla scheda: la scheda esce solo quando
    // si sa se si può chiedere, così Richiedi non compare dopo. Se i
    // permessi falliscono si va avanti senza Richiedi (niente scheletro
    // senza fine); nei tentativi di Riverpod `hasError` resta vero.
    final me = ref.watch(requestsMeProvider);
    final meReady = me.hasValue || me.hasError;
    final error = state.error;
    final (name, content) = switch (state.details) {
      TitleDetails() when meReady => (
          'data',
          _TmdbTitleView(titleKey: titleKey),
        ),
      null when error != null => (
          'error',
          ErrorView(
              error: error,
              onRetry: () => unawaited(ref.read(provider.notifier).load())),
        ),
      _ => (
          'loading',
          const DetailSkeleton(headerHeight: detailHeaderHeight),
        ),
    };
    return WfSwitcher(
      expand: true,
      child: KeyedSubtree(key: ValueKey(name), child: content),
    );
  }
}

class _TmdbTitleView extends ConsumerStatefulWidget {
  const _TmdbTitleView({required this.titleKey});

  final RequestTitleKey titleKey;

  @override
  ConsumerState<_TmdbTitleView> createState() => _TmdbTitleViewState();
}

class _TmdbTitleViewState extends ConsumerState<_TmdbTitleView> {
  /// Larghezza massima dell'elenco delle stagioni.
  static const _seasonsMaxWidth = 560.0;

  /// Rotella dolce, come nelle pagine della libreria.
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref
        .read(requestTitleControllerProvider(widget.titleKey).notifier)
        .submit();
    if (outcome == null) return;
    messenger.showSnackBar(
        SnackBar(content: Text(requestOutcomeText(l, outcome))));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final provider = requestTitleControllerProvider(widget.titleKey);
    final state = ref.watch(provider);
    final details = state.details!;
    final controller = ref.read(provider.notifier);
    final canRequest = ref.watch(requestsMeProvider).value?.canRequest ?? false;
    final showSeasons =
        details.mediaType == RequestMediaType.tv && details.seasons.isNotEmpty;
    // Lo sfondo sta dentro la testata e scorre con lei.
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        TmdbTitleHeader(
          details: details,
          state: state,
          canRequest: canRequest,
          onRequest: () => unawaited(_request()),
        ),
        if (showSeasons)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.requestsSeasons, style: WfText.display(26)),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _seasonsMaxWidth),
                  child: SeasonPicker(
                    seasons: details.seasons,
                    selected: canRequest ? state.selected : const {},
                    enabled: canRequest && !state.sending,
                    onToggle: controller.toggleSeason,
                    onToggleAll: controller.toggleAll,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// La testata della scheda da richiedere: come la testata delle schede
/// della libreria (`DetailHeader`), con i dati di Seerr.
class TmdbTitleHeader extends StatelessWidget {
  const TmdbTitleHeader({
    super.key,
    required this.details,
    required this.state,
    required this.canRequest,
    required this.onRequest,
  });

  final TitleDetails details;
  final RequestTitleState state;
  final bool canRequest;
  final VoidCallback onRequest;

  /// Larghezza massima della trama, come nelle schede della libreria.
  static const _overviewMaxWidth = 680.0;

  static Uri? _trailerUri(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
        ? uri
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const muted = TextStyle(color: WfColors.creamMuted);
    final isSeries = details.mediaType == RequestMediaType.tv;
    final year = details.year;
    final runtime = details.runtimeMinutes;
    final overview = details.overview;
    final meta = [
      if (year != null) '$year',
      isSeries ? l.requestsKindSeries : l.requestsKindMovie,
      if (!isSeries && runtime != null && runtime > 0)
        formatRuntime(Duration(minutes: runtime)),
      if (isSeries && details.seasons.isNotEmpty)
        l.detailSeasons(details.seasons.length),
    ].join(' · ');
    final itemId = details.jellyfinItemId;
    final watchable = details.status == TitleStatus.available ||
        details.status == TitleStatus.partial;
    final trailer = _trailerUri(details.trailerUrl);
    final showRequest = canRequest && details.canBeRequested;
    final status = showRequest ? null : titleStatusLabel(l, details);
    final chosen = state.selected.length;
    final allChosen = chosen == details.requestableSeasons.length;

    return SizedBox(
      height: detailHeaderHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Sotto le due sfumature, così scorre con loro.
          BackdropImage(
            backdrop: TmdbImages.backdrop(details.backdropPath),
            fallback: TmdbImages.poster(details.posterPath),
          ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(details.title.toUpperCase(),
                    maxLines: 2, style: WfText.display(56)),
                const SizedBox(height: 12),
                Text(meta, style: muted),
                if (details.genres.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(details.genres.join(' · '), style: muted),
                ],
                if (overview != null && overview.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: _overviewMaxWidth),
                    child: Text(overview,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.45)),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showRequest)
                      WfButton.primary(
                        label: isSeries && !allChosen
                            ? l.requestsRequestSeasons(chosen)
                            : l.requestsRequest,
                        icon: LucideIcons.plus,
                        onPressed: state.sending || (isSeries && chosen == 0)
                            ? null
                            : onRequest,
                      ),
                    if (status != null) RequestStatusChip(label: status),
                    if (itemId != null && watchable)
                      WfButton.secondary(
                        label: l.requestsWatch,
                        icon: LucideIcons.play,
                        onPressed: () => openItemById(context, itemId),
                      ),
                    if (trailer != null)
                      WfButton.secondary(
                        label: l.actionTrailer,
                        icon: LucideIcons.clapperboard,
                        onPressed: () => unawaited(launchUrl(trailer,
                            mode: LaunchMode.externalApplication)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo stato di un titolo già chiesto o arrivato, al posto di Richiedi.
class RequestStatusChip extends StatelessWidget {
  const RequestStatusChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WfColors.gold),
      ),
      child: Text(label,
          style: const TextStyle(
              color: WfColors.gold, fontWeight: FontWeight.w600)),
    );
  }
}
