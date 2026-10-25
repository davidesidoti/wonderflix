import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'player_extras.dart';

/// Quanto diventa piccolo il film nel post-play (spec D §12.1).
const postPlayScale = 0.42;

/// Margine del film piccolo (e del resto) dai bordi.
const postPlayInset = 32.0;

/// Angoli del film piccolo e dell'immagine.
const postPlayRadius = 12.0;

/// Spazio tra il film piccolo, le informazioni e l'immagine.
const postPlayGap = 24.0;

/// Margine e spazio nel layout stretto (spec §4.5).
const postPlayCompactInset = 16.0;

/// Il film piccolo, in una schermata di [size].
Rect postPlayFilmRect(Size size, {bool compact = false}) {
  final inset = compact ? postPlayCompactInset : postPlayInset;
  return Rect.fromLTWH(inset, inset, size.width * postPlayScale,
      size.height * postPlayScale);
}

/// Nel layout stretto, tutto lo spazio sotto il film.
Rect _compactBelow(Size size) => Rect.fromLTRB(
      postPlayCompactInset,
      postPlayFilmRect(size, compact: true).bottom + postPlayCompactInset,
      size.width - postPlayCompactInset,
      size.height - postPlayCompactInset,
    );

/// Lo spazio sotto il film diviso in due, il lato lungo a metà: [first]
/// è la parte a sinistra (o in alto), se no l'altra.
Rect _compactHalf(Size size, {required bool first}) {
  final below = _compactBelow(size);
  const half = postPlayCompactInset / 2;
  if (below.width >= below.height) {
    return first
        ? Rect.fromLTRB(below.left, below.top, below.center.dx - half,
            below.bottom)
        : Rect.fromLTRB(below.center.dx + half, below.top, below.right,
            below.bottom);
  }
  return first
      ? Rect.fromLTRB(below.left, below.top, below.right, below.center.dy - half)
      : Rect.fromLTRB(below.left, below.center.dy + half, below.right,
          below.bottom);
}

/// Il riquadro a destra del film piccolo, in una schermata di [size]: lì
/// stanno l'immagine del prossimo titolo o il pannello del voto. Nel layout
/// stretto è sotto il film, accanto (o sotto) le informazioni, e c'è solo
/// il voto.
Rect postPlaySideRect(Size size, {bool compact = false}) => compact
    ? _compactHalf(size, first: false)
    : Rect.fromLTRB(
        postPlayFilmRect(size).right + postPlayGap,
        postPlayInset,
        size.width - postPlayInset,
        size.height - postPlayInset,
      );

/// Il riquadro delle informazioni, sotto il film. Nel layout stretto è
/// largo quanto la schermata; con il voto ([shared]) ne lascia metà a lui.
Rect postPlayInfoRect(Size size,
    {bool compact = false, bool shared = false}) {
  if (compact) {
    return shared ? _compactHalf(size, first: true) : _compactBelow(size);
  }
  final film = postPlayFilmRect(size);
  return Rect.fromLTRB(film.left, film.bottom + postPlayGap, film.right,
      size.height - postPlayInset);
}

/// Il film: nel post-play si rimpicciolisce in alto a sinistra con angoli
/// arrotondati e un bordo crema, poi torna a tutto schermo. La struttura
/// non cambia mai (il video non si rimonta); il `Transform` sposta anche i
/// clic.
class PostPlayFrame extends StatelessWidget {
  const PostPlayFrame({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = WfMotion.of(context);
    final inset = FormFactor.of(context).compact
        ? postPlayCompactInset
        : postPlayInset;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: active ? 1 : 0),
      duration: motion.duration(WfMotion.slow),
      curve: WfMotion.emphasized,
      builder: (context, t, child) {
        final scale = lerpDouble(1, postPlayScale, t)!;
        final shift = inset * t;
        // Raggio e bordo nelle coordinate del figlio (che è scalato).
        final radius = BorderRadius.circular(postPlayRadius * t / scale);
        return Transform(
          transform: Matrix4.translationValues(shift, shift, 0)
              .multiplied(Matrix4.diagonal3Values(scale, scale, 1)),
          child: ClipRRect(
            borderRadius: radius,
            clipBehavior: t == 0 ? Clip.none : Clip.antiAlias,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: t == 0
                  ? const BoxDecoration()
                  : BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(
                          color: WfColors.cream.withValues(alpha: 0.35 * t),
                          width: 1.5 / scale),
                    ),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

/// Informazioni del post-play (spec D §12.1): sotto il film piccolo
/// "PROSSIMO EPISODIO", serie, episodio, trama e pulsanti; a destra
/// l'immagine dell'episodio. Entra sfumando a metà del rimpicciolimento.
/// Senza [episode] (coda finita, resta solo il voto del party) non c'è la
/// colonna sotto il film.
class PostPlayLayer extends ConsumerWidget {
  const PostPlayLayer({
    super.key,
    required this.episode,
    required this.countdown,
    required this.paused,
    required this.onPlay,
    required this.onWatchCredits,
    this.label,
    this.showImage = true,
    this.waiting = false,
    this.countdownSeconds = PlayNowButton.countdownFrom,
  });

  final JellyfinItem? episode;

  /// L'immagine a destra; senza, il riquadro resta al pannello del voto.
  final bool showImage;

  /// Il party aspetta i voti: al posto di "Riproduci ora" un pulsante spento.
  final bool waiting;

  /// Da quanti secondi parte il conto di "Riproduci ora".
  final int countdownSeconds;

  /// Occhiello; di default "Prossimo episodio" (nel watch party può essere
  /// "Prossimo nella coda", spec H §9.1).
  final String? label;

  final bool countdown;

  /// Video in pausa o in caricamento: il conto alla rovescia è fermo.
  final bool paused;
  final VoidCallback onPlay;
  final VoidCallback onWatchCredits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final shrink = motion.duration(WfMotion.slow);
    final fade = motion.duration(WfMotion.medium);
    final total = shrink ~/ 2 + fade;
    final start = (shrink ~/ 2).inMicroseconds / total.inMicroseconds;
    final episode = this.episode;
    // Nel layout stretto le informazioni vanno sotto il film, senza
    // l'immagine (spec §4.5).
    final compact = FormFactor.of(context).compact;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: WfMotion.standard),
      builder: (context, t, child) =>
          Opacity(opacity: t.clamp(0.0, 1.0), child: child),
      child: LayoutBuilder(builder: (context, constraints) {
        if (episode == null) return const SizedBox.expand();
        final overview = episode.overview;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: postPlayInfoRect(constraints.biggest,
                  compact: compact, shared: !showImage),
              // I pulsanti si dispongono sempre: con poco spazio (finestra
              // bassa, testo grande) cede la trama.
              child: Align(
                alignment: Alignment.topLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text((label ?? l.playerNextEpisodeTitle).toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WfText.display(20, color: WfColors.gold)),
                    const SizedBox(height: 8),
                    // Lo spazio tra l'occhiello e i pulsanti: prima la serie
                    // e l'episodio, poi la trama con quello che resta.
                    Flexible(
                      child: LayoutBuilder(
                        builder: (context, area) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints:
                                  BoxConstraints(maxHeight: area.maxHeight),
                              child: _PostPlayTitles(
                                title: cardTitle(episode).toUpperCase(),
                                subtitle: cardSubtitle(episode) ?? episode.name,
                                width: area.maxWidth,
                              ),
                            ),
                            if (overview != null)
                              Flexible(child: _PostPlayOverview(overview)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (waiting)
                          WfButton.primary(
                            key: const Key('post-play-waiting'),
                            label: l.ratingWaiting,
                            icon: LucideIcons.hourglass,
                            onPressed: null,
                          )
                        else
                          PlayNowButton(
                              countdown: countdown,
                              seconds: countdownSeconds,
                              paused: paused,
                              onPressed: onPlay),
                        WfButton.secondary(
                          label: l.playerWatchCredits,
                          icon: LucideIcons.film,
                          onPressed: onWatchCredits,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (showImage && !compact)
              Positioned.fromRect(
                rect: postPlaySideRect(constraints.biggest),
                // Limitata nei due sensi: in una finestra molto larga il 16:9
                // largo quanto lo spazio rimasto uscirebbe dal fondo.
                child: Align(
                  alignment: Alignment.topLeft,
                  child: AspectRatio(
                    key: const Key('post-play-image'),
                    aspectRatio: 16 / 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(postPlayRadius),
                        boxShadow: [
                          BoxShadow(
                              color: WfColors.bg.withValues(alpha: 0.8),
                              blurRadius: 32,
                              offset: const Offset(0, 12)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(postPlayRadius),
                        child: WfImage(image: urls.landscape(episode)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// Serie ed episodio del post-play. Se non entrano neppure senza la trama
/// (finestra minima con il testo oltre il 200% circa), l'ultima difesa è
/// rimpicciolire il nome della serie: i pulsanti sotto restano visibili.
class _PostPlayTitles extends StatelessWidget {
  const _PostPlayTitles({
    required this.title,
    required this.subtitle,
    required this.width,
  });

  final String title;
  final String subtitle;

  /// Larghezza della colonna: il nome della serie finisce con i puntini lì,
  /// anche quando si rimpicciolisce.
  final double width;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: width,
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WfText.display(40)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ],
      );
}

/// Trama del post-play: al massimo [maxLines] righe, ma solo quelle intere
/// che entrano nello spazio rimasto (ellissi sull'ultima); se non ne entra
/// nessuna sparisce, e i pulsanti sotto restano al loro posto.
class _PostPlayOverview extends StatelessWidget {
  const _PostPlayOverview(this.text);

  final String text;

  /// Righe con spazio a volontà.
  static const maxLines = 3;

  /// Spazio sopra la trama.
  static const gap = 10.0;

  static const style = TextStyle(color: WfColors.creamMuted, height: 1.45);

  @override
  Widget build(BuildContext context) {
    final fontSize = DefaultTextStyle.of(context).style.merge(style).fontSize ??
        kDefaultFontSize;
    final line = MediaQuery.textScalerOf(context).scale(fontSize) *
        style.height!;
    return LayoutBuilder(builder: (context, constraints) {
      final lines = constraints.hasBoundedHeight
          ? math.min(maxLines, ((constraints.maxHeight - gap) / line).floor())
          : maxLines;
      if (lines <= 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: gap),
        child: Text(text,
            maxLines: lines, overflow: TextOverflow.ellipsis, style: style),
      );
    });
  }
}
