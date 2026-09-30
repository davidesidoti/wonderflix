import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/error_text.dart';
import '../app/hero_launch.dart';
import '../app/theme.dart';
import '../core/jellyfin/item_models.dart';
import '../features/detail/detail_header.dart';
import '../features/library/item_labels.dart';
import '../features/library/library_providers.dart';
import '../features/library/user_data.dart';
import '../l10n/gen/app_localizations.dart';
import 'backdrop_image.dart';
import 'poster_card.dart';
import 'wf_buttons.dart';
import 'wf_image.dart';

/// Sosta del mouse su una card prima che si apra l'anteprima (spec C §7.1).
const previewHoverDelay = Duration(milliseconds: 500);

/// Entro questo tempo dalla chiusura di un'anteprima, la card su cui passa
/// il mouse apre la sua subito (passaggio da una card all'altra).
const previewChainWindow = Duration(milliseconds: 400);

/// Larghezza dell'anteprima rispetto alla card, e minimo (spec C §7.2).
const previewWidthFactor = 1.8;
const previewMinWidth = 300.0;

/// Altezza della parte sotto l'immagine 16:9: pulsanti, dati, generi,
/// avanzamento.
const previewBodyHeight = 124.0;

/// Distanza minima dai bordi della finestra.
const previewMargin = 16.0;

/// Rettangolo dell'anteprima di una card: centrata sulla card, larga
/// [previewWidthFactor] volte (almeno [previewMinWidth]), dentro l'overlay
/// con [previewMargin] di margine.
Rect previewRect({required Rect card, required Size overlay}) {
  final maxWidth = math.max(0.0, overlay.width - 2 * previewMargin);
  final width = math
      .max(previewMinWidth, card.width * previewWidthFactor)
      .clamp(0.0, maxWidth)
      .toDouble();
  final height = width * 9 / 16 + previewBodyHeight;
  final left = (card.center.dx - width / 2).clamp(
      previewMargin, math.max(previewMargin, overlay.width - previewMargin - width));
  final top = (card.center.dy - height / 2).clamp(
      previewMargin, math.max(previewMargin, overlay.height - previewMargin - height));
  return Rect.fromLTWH(left.toDouble(), top.toDouble(), width, height);
}

/// Quale anteprima è aperta (al massimo una) e quando si è chiusa l'ultima.
@immutable
class CardPreviewState {
  const CardPreviewState({this.openId, this.closedAt});

  /// Identità della card che mostra l'anteprima (lo stato del suo host).
  final Object? openId;
  final DateTime? closedAt;
}

class CardPreviewController extends Notifier<CardPreviewState> {
  @override
  CardPreviewState build() => const CardPreviewState();

  void open(Object id) => state = CardPreviewState(openId: id);

  /// Chiude l'anteprima di [id], se è quella aperta.
  void close(Object id) {
    if (!identical(state.openId, id)) return;
    state = CardPreviewState(closedAt: clock.now());
  }

  /// Un'anteprima è aperta o si è appena chiusa: la prossima si apre subito.
  bool opensImmediately() {
    if (state.openId != null) return true;
    final closed = state.closedAt;
    return closed != null && clock.now().difference(closed) < previewChainWindow;
  }
}

final cardPreviewProvider =
    NotifierProvider<CardPreviewController, CardPreviewState>(
        CardPreviewController.new);

/// Contenuto dell'anteprima di una card (spec C §7.3). [onPlay] e
/// [onDetails] li decide l'host (chiude l'anteprima, avvia il volo).
class CardPreview extends ConsumerWidget {
  const CardPreview({
    super.key,
    required this.item,
    required this.heroTag,
    required this.onPlay,
    required this.onDetails,
    this.body = kAlwaysCompleteAnimation,
  });

  final JellyfinItem item;

  /// Tag del volo verso la scheda (sorgente della card + `.preview`).
  final WfHeroTag? heroTag;
  final VoidCallback onPlay;
  final VoidCallback onDetails;

  /// Opacità della parte sotto l'immagine e del titolo: in uscita verso la
  /// scheda sparisce subito, mentre l'immagine vola.
  final Animation<double> body;

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
    final urls = ref.watch(imageUrlsProvider);
    final userData = watchUserData(ref, item);
    final overrides = ref.read(userDataOverridesProvider.notifier);
    final progress = userData.progress;
    final episode = item.kind == ItemKind.episode;
    final logo = episode ? null : urls.logo(item);
    final subtitle = episode ? cardSubtitle(item) : null;
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 12);

    return Material(
      color: WfColors.surface,
      clipBehavior: Clip.antiAlias,
      elevation: 12,
      shadowColor: WfColors.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: WfColors.gold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: GestureDetector(
              key: const Key('preview-image'),
              onTap: onDetails,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    WfHero(
                      tag: heroTag,
                      borderRadius: BorderRadius.zero,
                      child: BackdropImage(
                          backdrop: urls.backdrop(item),
                          fallback: urls.poster(item)),
                    ),
                    FadeTransition(
                      opacity: body,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [WfColors.surface, Color(0x00121212)],
                            stops: [0, 0.6],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 8,
                      child: FadeTransition(
                        opacity: body,
                        child: logo != null
                            ? SizedBox(
                                height: 44,
                                child: Align(
                                  alignment: Alignment.bottomLeft,
                                  child: WfImage(image: logo, fit: BoxFit.contain),
                                ),
                              )
                            : Text(cardTitle(item).toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WfText.display(26)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: FadeTransition(
              opacity: body,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Senza il margine per il tocco (come su desktop, anche
                    // nei test): la riga è alta [_buttonSize].
                    Theme(
                      data: Theme.of(context).copyWith(
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: Row(
                        children: [
                          _RoundButton(
                            icon: LucideIcons.play,
                            tooltip:
                                progress != null ? l.previewResume : l.actionPlay,
                            filled: true,
                            onPressed: onPlay,
                          ),
                          const SizedBox(width: 8),
                          if (!episode) ...[
                            WfIconToggle(
                              icon: LucideIcons.heart,
                              selected: userData.isFavorite,
                              tooltip: userData.isFavorite
                                  ? l.actionRemoveFromList
                                  : l.actionAddToList,
                              size: _buttonSize,
                              iconSize: _iconSize,
                              onPressed: () => unawaited(_toggle(
                                  context, () => overrides.toggleFavorite(item))),
                            ),
                            const SizedBox(width: 8),
                          ],
                          WfIconToggle(
                            icon: LucideIcons.check,
                            selected: userData.played,
                            tooltip: userData.played
                                ? l.actionMarkUnwatched
                                : l.actionMarkWatched,
                            size: _buttonSize,
                            iconSize: _iconSize,
                            onPressed: () => unawaited(_toggle(
                                context, () => overrides.togglePlayed(item))),
                          ),
                          const Spacer(),
                          _RoundButton(
                            icon: LucideIcons.chevronDown,
                            tooltip: l.actionDetails,
                            onPressed: onDetails,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (subtitle != null)
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5)),
                    DefaultTextStyle.merge(
                      style: const TextStyle(fontSize: 12),
                      child: MetaLine(item: item),
                    ),
                    if (item.genres.isNotEmpty)
                      Text(item.genres.take(3).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted),
                    const Spacer(),
                    if (progress != null)
                      SizedBox(
                        key: const Key('preview-progress'),
                        height: 3,
                        child: ProgressStrip(progress: progress),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsanti dell'anteprima: più piccoli di quelli della scheda (44/20) per
/// stare in [previewBodyHeight] con tutte le righe di dati.
const _buttonSize = 36.0;
const _iconSize = 18.0;

/// Pulsante tondo dell'anteprima (play pieno oro, dettagli a contorno).
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          // Il minimo di Material (40) lo allargherebbe.
          minimumSize: const Size.square(_buttonSize),
          fixedSize: const Size.square(_buttonSize),
          backgroundColor: filled ? WfColors.gold : Colors.transparent,
          foregroundColor: filled ? WfColors.bg : WfColors.cream,
          side: filled ? null : const BorderSide(color: WfColors.creamMuted),
        ),
        icon: Icon(icon, size: _iconSize),
      );
}
