import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/requests/requests_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../friends/friends_controller.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import '../playback/play_launcher.dart';
import '../recommendations/recommend_panel.dart';
import '../requests/request_seasons.dart';
import '../social/social_providers.dart';
import '../watch_party/party_mode_menu.dart';
import '../watch_party/watch_party_providers.dart';
import 'header_parallax.dart';
import 'item_actions_menu.dart';
import 'primary_action.dart';

/// Altezza della testata della scheda (sfondo, logo, dati, azioni).
const detailHeaderHeight = 560.0;

/// Altezza dello sfondo dietro la testata: nel layout stretto è l'immagine
/// 16:9 sopra i testi.
double detailBackdropHeight(BuildContext context) =>
    FormFactor.of(context).compact
        ? MediaQuery.sizeOf(context).width * 9 / 16
        : detailHeaderHeight;

/// Margine tra il blocco dei testi (fino alla riga dei pulsanti) e il fondo
/// della testata.
const detailHeaderTextBottom = 28.0;

/// Elementi della scheda che entrano scaglionati: 5 della testata (logo,
/// dati, generi, trama, pulsanti) e le righe sotto.
const detailEntranceCount = 9;

/// Parte alta di una scheda: logo o titolo, dati, trama, azioni. Lo sfondo
/// è un livello a parte dietro alla pagina (`DetailBackdrop`). I testi sono
/// elementi 0–4 dello `StaggerGroup` della scheda.
class DetailHeader extends ConsumerWidget {
  const DetailHeader(
      {super.key, required this.item, required this.primary, this.controller});

  final JellyfinItem item;

  /// `null` finché non si sa cosa riprodurre (serie ancora in caricamento).
  final PrimaryAction? primary;

  /// Scroll della pagina: il testo sfuma salendo (spec C §9.1).
  final ScrollController? controller;

  Future<void> _toggle(BuildContext context, Future<void> Function() action) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(l, error))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final userData = watchUserData(ref, item);
    final overrides = ref.read(userDataOverridesProvider.notifier);
    final action = primary;
    final canCreateParty = ref.watch(syncPlayAccessProvider).canCreate;
    final overview = item.overview;
    final hasTrailer =
        item.localTrailerCount > 0 || remoteTrailerUri(item) != null;
    // Serie della libreria con stagioni che mancano (spec I §9.3): la
    // scheda di Seerr si carica solo per le serie con l'id TMDB.
    final tmdbId = item.kind == ItemKind.series ? item.tmdbId : null;
    final seasonsKey = tmdbId == null
        ? null
        : (
            type: RequestMediaType.tv,
            tmdbId: tmdbId,
            language: Localizations.localeOf(context).languageCode,
          );
    final canRequestSeasons =
        seasonsKey != null && ref.watch(seasonsToRequestProvider(seasonsKey));
    // "Consiglia a…" (spec N §7.2): film e serie, con la funzione del plugin
    // e almeno un amico.
    final canRecommend =
        const {ItemKind.movie, ItemKind.series}.contains(item.kind) &&
            ref.watch(socialAvailabilityProvider.select((f) => f.recommendations)) &&
            ref.watch(friendsControllerProvider
                .select((s) => s.snapshot.friends.isNotEmpty));

    final compact = FormFactor.of(context).compact;
    // Le azioni, `null` quando non ci sono: sul PC pulsanti con il testo,
    // nello stretto icone e menu "⋯".
    final play = action == null
        ? null
        : WfButton.primary(
            label: primaryActionLabel(l, action),
            icon: LucideIcons.play,
            onPressed: () => unawaited(playItem(context, ref, action.target)),
          );
    final VoidCallback? restart = action is ResumeAction
        ? () => unawaited(
            playItem(context, ref, action.target, fromStart: true))
        : null;
    // Film ed episodi; per una serie l'azione riproduce il prossimo
    // episodio da vedere, e la coda parte da lì. Il contesto è quello del
    // pulsante: il menu delle modalità si apre sotto.
    final void Function(BuildContext)? together = canCreateParty &&
            action != null &&
            const {ItemKind.movie, ItemKind.episode, ItemKind.series}
                .contains(item.kind)
        ? (buttonContext) => unawaited(watchTogether(
              buttonContext,
              ref,
              action.target,
              start:
                  action is ResumeAction ? action.position : Duration.zero,
            ))
        : null;
    final VoidCallback? trailer =
        hasTrailer ? () => unawaited(playTrailer(context, ref, item)) : null;
    final VoidCallback? recommend = canRecommend
        ? () => openRecommendPanel(
            context, ref, RecommendSubject(itemId: item.id, name: item.name))
        : null;
    final VoidCallback? requestSeasons = seasonsKey != null && canRequestSeasons
        ? () => unawaited(
            showRequestSeasonsDialog(context, ref, seasonsKey, item.name))
        : null;
    final favorite = WfIconToggle(
      icon: LucideIcons.heart,
      selected: userData.isFavorite,
      tooltip:
          userData.isFavorite ? l.actionRemoveFromList : l.actionAddToList,
      onPressed: () =>
          unawaited(_toggle(context, () => overrides.toggleFavorite(item))),
    );
    final played = WfIconToggle(
      icon: LucideIcons.check,
      selected: userData.played,
      tooltip: userData.played ? l.actionMarkUnwatched : l.actionMarkWatched,
      onPressed: () =>
          unawaited(_toggle(context, () => overrides.togglePlayed(item))),
    );

    return DetailHeaderFrame(
      controller: controller,
      children: [
        StaggerItem(index: 0, child: HeaderTitle(item: item)),
        const SizedBox(height: 12),
        StaggerItem(index: 1, child: MetaLine(item: item)),
        if (item.genres.isNotEmpty) ...[
          const SizedBox(height: 6),
          StaggerItem(
            index: 2,
            child: Text(item.genres.join(' · '),
                style: const TextStyle(color: WfColors.creamMuted)),
          ),
        ],
        if (overview != null) ...[
          const SizedBox(height: 12),
          StaggerItem(
            index: 3,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Text(overview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.45)),
            ),
          ),
        ],
        const SizedBox(height: 20),
        StaggerItem(
          index: 4,
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?play,
                    if (play != null) const SizedBox(height: 12),
                    // Le azioni secondarie come icone; quelle che non ci
                    // stanno finiscono nel menu "⋯".
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (restart != null)
                          _ActionIcon(
                              icon: LucideIcons.rotateCcw,
                              label: l.actionRestart,
                              onPressed: restart),
                        if (together != null)
                          Builder(
                            builder: (buttonContext) => _ActionIcon(
                                icon: LucideIcons.users,
                                label: l.watchPartyWatchTogether,
                                onPressed: () => together(buttonContext)),
                          ),
                        if (trailer != null)
                          _ActionIcon(
                              icon: LucideIcons.clapperboard,
                              label: l.actionTrailer,
                              onPressed: trailer),
                        favorite,
                        played,
                        ItemActionsButton(item: item, extra: [
                          if (recommend != null)
                            (label: l.recommendButton, onSelected: recommend),
                          if (requestSeasons != null)
                            (
                              label: l.requestsMoreSeasons,
                              onSelected: requestSeasons
                            ),
                        ]),
                      ],
                    ),
                  ],
                )
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ?play,
                    if (restart != null)
                      WfButton.secondary(
                        label: l.actionRestart,
                        icon: LucideIcons.rotateCcw,
                        onPressed: restart,
                      ),
                    if (together != null)
                      Builder(
                        // Il menu delle modalità si apre sotto il
                        // pulsante (spec F §9.1).
                        builder: (buttonContext) => WfButton.secondary(
                          label: l.watchPartyWatchTogether,
                          icon: LucideIcons.users,
                          onPressed: () => together(buttonContext),
                        ),
                      ),
                    if (trailer != null)
                      WfButton.secondary(
                        label: l.actionTrailer,
                        icon: LucideIcons.clapperboard,
                        onPressed: trailer,
                      ),
                    favorite,
                    played,
                    ItemActionsButton(item: item),
                    if (recommend != null)
                      WfButton.secondary(
                        label: l.recommendButton,
                        icon: LucideIcons.send,
                        onPressed: recommend,
                      ),
                    // Dopo i toggle: la scheda di Seerr arriva dopo due
                    // richieste, e prima dei toggle li farebbe saltare.
                    if (requestSeasons != null)
                      WfButton.secondary(
                        label: l.requestsMoreSeasons,
                        icon: LucideIcons.plus,
                        onPressed: requestSeasons,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Cornice di una testata (scheda e pagina della saga): altezza
/// [detailHeaderHeight], i due gradienti sopra lo sfondo e, in basso a
/// sinistra, il blocco dei testi [children], che sfuma salendo con lo scroll
/// (spec C §9.1). Lo sfondo è un livello a parte dietro alla pagina
/// (`DetailBackdrop`).
class DetailHeaderFrame extends StatelessWidget {
  const DetailHeaderFrame(
      {super.key, required this.controller, required this.children});

  /// Scroll della pagina; senza, il testo non sfuma.
  final ScrollController? controller;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
    if (FormFactor.of(context).compact) {
      // Altezza dal contenuto: l'immagine 16:9 (lo sfondo dietro) sfuma nel
      // fondo, i testi e le azioni sotto.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: detailBackdropHeight(context),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [WfColors.bg, Colors.transparent],
                  stops: [0, 0.5],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _ScrollFade(controller: controller, child: text),
          ),
        ],
      );
    }
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
            child: _ScrollFade(controller: controller, child: text),
          ),
        ],
      ),
    );
  }
}

/// Primo elemento di una testata: il logo di [item] o, senza, il nome in
/// maiuscolo.
class HeaderTitle extends ConsumerWidget {
  const HeaderTitle({super.key, required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logo = ref.watch(imageUrlsProvider).logo(item);
    return logo != null
        ? SizedBox(
            height: 120,
            width: 460,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: WfImage(image: logo, fit: BoxFit.contain),
            ),
          )
        : Text(item.name.toUpperCase(),
            maxLines: 2,
            style: WfText.display(FormFactor.of(context).compact ? 36 : 56));
  }
}

/// Azione secondaria della testata nello stretto: icona tonda con il nome
/// nel tooltip, come i toggle accanto.
class _ActionIcon extends StatelessWidget {
  const _ActionIcon(
      {required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => WfIconToggle(
      icon: icon, selected: false, tooltip: label, onPressed: onPressed);
}

/// Opacità e salita del testo della testata con lo scroll.
class _ScrollFade extends StatelessWidget {
  const _ScrollFade({required this.controller, required this.child});

  final ScrollController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scroll = controller;
    if (scroll == null) return child;
    final reduced = WfMotion.of(context).isReduced;
    return AnimatedBuilder(
      animation: scroll,
      child: child,
      builder: (context, child) {
        final p = headerParallax(
            scroll.hasClients ? scroll.offset : 0, reduced: reduced);
        // Sparito del tutto non riceve più clic (i pulsanti sono invisibili).
        return IgnorePointer(
          ignoring: p.textOpacity == 0,
          child: Opacity(
            opacity: p.textOpacity,
            child: Transform.translate(
                offset: Offset(0, p.textShift), child: child),
          ),
        );
      },
    );
  }
}

/// "2024 · 2h 46m · ★ 8.4 · [PG-13]".
class MetaLine extends StatelessWidget {
  const MetaLine({super.key, required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final runtime = item.runtime;
    final seasons = item.childCount;
    final rating = item.communityRating;
    final official = item.officialRating;
    const muted = TextStyle(color: WfColors.creamMuted);
    final parts = [
      if (item.productionYear != null) '${item.productionYear}',
      if (item.kind != ItemKind.series && runtime != null) formatRuntime(runtime),
      if (item.kind == ItemKind.series && seasons != null) l.detailSeasons(seasons),
    ];
    return Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (parts.isNotEmpty) Text(parts.join(' · '), style: muted),
        if (rating != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.star, size: 14, color: WfColors.gold),
              const SizedBox(width: 4),
              Text(rating.toStringAsFixed(1),
                  style: const TextStyle(
                      color: WfColors.gold, fontWeight: FontWeight.w600)),
            ],
          ),
        if (official != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: WfColors.creamMuted),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(official, style: muted.copyWith(fontSize: 12)),
          ),
      ],
    );
  }
}
