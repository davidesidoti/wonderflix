import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/card_preview.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../playback/play_launcher.dart';

/// Autoplay del carosello; spento nei widget test (`pumpApp`) salvo
/// richiesta, perché un carosello che avanza da solo non si ferma mai.
final carouselAutoplayProvider = Provider<bool>((ref) => true);

/// Ken Burns: zoom e deriva laterale durante una diapositiva (spec C §8.1).
const kenBurnsScale = 0.1;
const kenBurnsDrift = 0.02;

/// Testi della diapositiva che entra: ritardo e passo (spec C §8.1).
const heroTextDelay = Duration(milliseconds: 250);
const heroTextStagger = Duration(milliseconds: 90);

/// Testi della diapositiva che esce: sfumano in questo tempo (spec C §8.1).
const heroTextExit = Duration(milliseconds: 250);

/// Distanza dal basso del pulsante nell'angolo del carosello: sopra i
/// pallini (spec M §8.4).
const heroCornerBottom = 56.0;

/// Trascinamento minimo (o velocità) che cambia diapositiva col dito.
const heroSwipeDistance = 48.0;
const heroSwipeVelocity = 300.0;

/// Titoli in evidenza a tutta larghezza; cambia ogni 8 secondi con una
/// dissolvenza incrociata (spec C §8.1).
class HeroCarousel extends ConsumerStatefulWidget {
  const HeroCarousel({super.key, required this.items, this.corner});

  final List<JellyfinItem> items;

  /// In basso a destra, sopra i pallini: il pulsante "Cosa guardo
  /// stasera?" (spec M §8.4).
  final Widget? corner;

  static const interval = Duration(seconds: 8);

  static const height = 460.0;

  /// Altezza della parte con le immagini: nel layout stretto al massimo
  /// 1,1 volte la larghezza.
  static double heightOf(BuildContext context) =>
      FormFactor.of(context).compact
          ? math.min(height, MediaQuery.sizeOf(context).width * 1.1)
          : height;

  @override
  ConsumerState<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends ConsumerState<HeroCarousel>
    with TickerProviderStateMixin {
  /// Tempo della diapositiva: riempie il puntino e guida il Ken Burns; a
  /// fine corsa passa alla successiva. Si ferma con il mouse sopra, con
  /// un'anteprima di una card aperta e quando la Home è coperta, e riprende
  /// da dove era.
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: HeroCarousel.interval)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _goTo(_index + 1);
        });

  /// Dissolvenza della diapositiva che entra (anche i testi).
  late final AnimationController _fade =
      AnimationController(vsync: this, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && _previous != null) {
            setState(() => _previous = null);
          }
        });

  int _index = 0;
  int? _previous;
  double _previousProgress = 0;
  bool _hovered = false;

  /// Un'anteprima di una card è aperta (spec C §7): conta come il mouse
  /// sopra.
  bool _previewOpen = false;

  /// Spostamento orizzontale del trascinamento in corso (solo col dito).
  double _dragDx = 0;

  /// Falso quando la Home è coperta da un'altra pagina. Un ticker spento
  /// non chiama più il controller ma il suo tempo continua a scorrere:
  /// senza fermarlo, tornando alla Home la diapositiva cambierebbe subito.
  bool _tickersEnabled = true;

  bool get _autoplay =>
      ref.read(carouselAutoplayProvider) && widget.items.length > 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickersEnabled = TickerMode.valuesOf(context).enabled;
    _syncProgress();
  }

  @override
  void didUpdateWidget(HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length == widget.items.length) return;
    final last = widget.items.length - 1;
    if (last >= 0 && _index > last) _index = last;
    _previous = null;
    _progress.value = 0;
    _syncProgress();
  }

  @override
  void dispose() {
    _progress.dispose();
    _fade.dispose();
    super.dispose();
  }

  /// Fa scorrere il tempo della diapositiva solo se nulla lo mette in pausa.
  void _syncProgress() {
    if (_autoplay && !_hovered && !_previewOpen && _tickersEnabled) {
      if (!_progress.isAnimating) unawaited(_progress.forward());
    } else {
      _progress.stop();
    }
  }

  void _goTo(int page) {
    final count = widget.items.length;
    if (count == 0) return;
    final next = page % count;
    if (next == _index) return;
    final motion = WfMotion.of(context);
    setState(() {
      _previous = _index;
      _previousProgress = _progress.value;
      _index = next;
    });
    _fade.duration = motion.duration(WfMotion.crossfade);
    unawaited(_fade.forward(from: 0));
    _progress.value = 0;
    _syncProgress();
  }

  /// Fine di un trascinamento: a sinistra la successiva, a destra la
  /// precedente.
  void _swipeEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragDx < -heroSwipeDistance || velocity < -heroSwipeVelocity) {
      _goTo(_index + 1);
    } else if (_dragDx > heroSwipeDistance || velocity > heroSwipeVelocity) {
      _goTo(_index - 1);
    }
  }

  void _hover(bool hovered) {
    _hovered = hovered;
    _syncProgress();
  }

  /// Opacità dei testi della diapositiva che esce: sfumano nei primi
  /// [heroTextExit] della dissolvenza. Con le animazioni ridotte la
  /// dissolvenza dura `fast` e i testi sfumano insieme alla diapositiva.
  Animation<double> _textExit(WfMotion motion) => ReverseAnimation(
        _fade.drive(CurveTween(
          curve: motion.isReduced
              ? WfMotion.standard
              : Interval(
                  0,
                  heroTextExit.inMicroseconds /
                      WfMotion.crossfade.inMicroseconds,
                  curve: WfMotion.standard,
                ),
        )),
      );

  @override
  Widget build(BuildContext context) {
    ref.listen(cardPreviewProvider.select((s) => s.openId != null),
        (previous, open) {
      _previewOpen = open;
      _syncProgress();
    });
    final form = FormFactor.of(context);
    final height = HeroCarousel.heightOf(context);
    if (widget.items.isEmpty) return SizedBox(height: height);
    final motion = WfMotion.of(context);
    final previous = _previous;
    final current = widget.items[_index];
    final corner = widget.corner;
    // Diapositive con chiave per titolo: quella che esce conserva il suo
    // elemento (e l'immagine già caricata) passando sotto.
    final carousel = MouseRegion(
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      // Col dito si scorre tra le diapositive; col mouse resta com'era.
      child: GestureDetector(
        onHorizontalDragStart: form.touch ? (_) => _dragDx = 0 : null,
        onHorizontalDragUpdate: form.touch
            ? (details) => _dragDx += details.primaryDelta ?? 0
            : null,
        onHorizontalDragEnd: form.touch ? _swipeEnd : null,
        child: SizedBox(
          height: height,
          // Il Ken Burns ingrandisce lo sfondo oltre i bordi: senza ritaglio
          // sborderebbe sotto il carosello, sopra la prima riga.
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Stessa struttura per le due diapositive: passando da attuale
                // a precedente il sottoalbero (logo, pulsanti) non si ricrea.
                if (previous != null && previous < widget.items.length)
                  KeyedSubtree(
                    key: ValueKey('slide-${widget.items[previous].id}'),
                    // Chi esce non riceve più clic.
                    child: IgnorePointer(
                      child: FadeTransition(
                        opacity: kAlwaysCompleteAnimation,
                        child: _HeroSlide(
                          item: widget.items[previous],
                          kenBurns: motion.isReduced
                              ? null
                              : AlwaysStoppedAnimation(_previousProgress),
                          entrance: kAlwaysCompleteAnimation,
                          textOpacity: _textExit(motion),
                        ),
                      ),
                    ),
                  ),
                KeyedSubtree(
                  key: ValueKey('slide-${current.id}'),
                  child: IgnorePointer(
                    ignoring: false,
                    child: FadeTransition(
                      opacity: _fade.drive(CurveTween(curve: WfMotion.standard)),
                      child: _HeroSlide(
                        item: current,
                        kenBurns: motion.isReduced ? null : _progress,
                        entrance:
                            motion.isReduced ? kAlwaysCompleteAnimation : _fade,
                        textOpacity: kAlwaysCompleteAnimation,
                      ),
                    ),
                  ),
                ),
                Positioned(
                    right: form.compact ? 16 : 32,
                    bottom: form.touch ? 0 : 20,
                    child: _dots(motion, touch: form.touch)),
                if (corner != null && !form.compact)
                  Positioned(right: 32, bottom: heroCornerBottom, child: corner),
              ],
            ),
          ),
        ),
      ),
    );
    if (corner == null || !form.compact) return carousel;
    // Nello stretto l'angolo coprirebbe il testo: va sotto il carosello.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        carousel,
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: corner),
      ],
    );
  }

  /// Col dito ogni puntino si tocca su almeno [minTouchTarget] di lato.
  Widget _dots(WfMotion motion, {required bool touch}) => Row(
        children: [
          for (var i = 0; i < widget.items.length; i++)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: ValueKey('hero-dot-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _goTo(i),
                child: Container(
                  constraints: touch
                      ? const BoxConstraints(
                          minWidth: minTouchTarget, minHeight: minTouchTarget)
                      : null,
                  alignment: touch ? Alignment.center : null,
                  padding: const EdgeInsets.fromLTRB(3, 8, 3, 8),
                  child: AnimatedContainer(
                    duration: motion.duration(WfMotion.medium),
                    curve: WfMotion.emphasized,
                    width: i == _index ? 26 : 6,
                    height: 6,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? WfColors.cream.withValues(alpha: 0.3)
                          : WfColors.creamMuted,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    // Il puntino attivo si riempie d'oro con il tempo della
                    // diapositiva (anche con le animazioni ridotte).
                    child: i == _index
                        ? AnimatedBuilder(
                            animation: _progress,
                            builder: (context, _) => FractionallySizedBox(
                              key: const Key('hero-dot-fill'),
                              alignment: Alignment.centerLeft,
                              widthFactor: _progress.value,
                              child: const ColoredBox(color: WfColors.gold),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
        ],
      );
}

/// Elemento [index] dei testi della diapositiva che entra: sale di 10 px in
/// dissolvenza, scaglionato, durante la dissolvenza [entrance]
/// (`kAlwaysCompleteAnimation` = fermo e visibile). Avvolge sempre, così
/// la struttura resta la stessa quando la diapositiva diventa la precedente.
/// Finché l'elemento non ha iniziato a comparire non riceve clic (i
/// pulsanti di un titolo appena scelto sono ancora invisibili).
///
/// Non usa `StaggerItem`: qui il tempo è la dissolvenza del carosello (non
/// un gruppo con un controller suo), la salita è di 10 px invece di 20 e
/// ogni elemento dura `medium`, come chiede lo spec C §8.1.
Widget _enter(Animation<double> entrance, int index, Widget child) {
  final total = WfMotion.crossfade.inMicroseconds;
  final begin =
      ((heroTextDelay + heroTextStagger * index).inMicroseconds / total)
          .clamp(0.0, 1.0);
  final end = (begin + WfMotion.medium.inMicroseconds / total).clamp(0.0, 1.0);
  final t = entrance.drive(
      CurveTween(curve: Interval(begin, end, curve: WfMotion.emphasized)));
  return AnimatedBuilder(
    animation: t,
    child: child,
    builder: (context, child) => IgnorePointer(
      ignoring: t.value <= 0,
      child: Opacity(
        opacity: t.value.clamp(0.0, 1.0),
        child: Transform.translate(
            offset: Offset(0, 10 * (1 - t.value)), child: child),
      ),
    ),
  );
}

class _HeroSlide extends ConsumerWidget {
  const _HeroSlide({
    required this.item,
    required this.kenBurns,
    required this.entrance,
    required this.textOpacity,
  });

  final JellyfinItem item;

  /// Tempo della diapositiva per il Ken Burns; `null` = sfondo fermo.
  final Animation<double>? kenBurns;

  /// Dissolvenza d'entrata per i testi scaglionati;
  /// `kAlwaysCompleteAnimation` = testi fermi.
  final Animation<double> entrance;

  /// Opacità di tutti i testi (sfumano quando la diapositiva esce).
  final Animation<double> textOpacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final logo = urls.logo(item);
    final runtime = item.runtime;
    final seasons = item.childCount;
    final meta = [
      if (item.productionYear != null) '${item.productionYear}',
      if (item.kind == ItemKind.movie && runtime != null) formatRuntime(runtime),
      if (item.kind == ItemKind.series && seasons != null) l.detailSeasons(seasons),
      ...item.genres.take(2),
    ].join(' · ');
    final backdrop = WfImage(image: urls.backdrop(item));
    final compact = FormFactor.of(context).compact;
    final kenBurns = this.kenBurns;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (kenBurns == null)
          backdrop
        else
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: kenBurns,
              builder: (context, child) {
                final t = kenBurns.value;
                final scale = 1 + kenBurnsScale * t;
                return Transform(
                  key: const Key('hero-ken-burns'),
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translateByDouble(
                        -kenBurnsDrift * t * MediaQuery.sizeOf(context).width,
                        0,
                        0,
                        1)
                    ..scaleByDouble(scale, scale, 1, 1),
                  child: child,
                );
              },
              child: backdrop,
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [WfColors.bg, Color(0xCC0A0A0A), Colors.transparent],
              stops: [0, 0.35, 0.75],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [WfColors.bg, Colors.transparent],
              stops: [0, 0.45],
            ),
          ),
        ),
        Positioned(
          left: compact ? 16 : 32,
          right: compact ? 16 : null,
          bottom: 48,
          width: compact ? null : 560,
          child: FadeTransition(
            opacity: textOpacity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _enter(
                  entrance,
                  0,
                  logo != null
                      ? SizedBox(
                          height: compact ? 80 : 110,
                          width: compact ? 240 : 420,
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: WfImage(image: logo, fit: BoxFit.contain),
                          ),
                        )
                      : Text(item.name.toUpperCase(),
                          maxLines: 2,
                          style: WfText.display(compact ? 40 : 56)),
                ),
                const SizedBox(height: 10),
                _enter(entrance, 1,
                    Text(meta, style: const TextStyle(color: WfColors.creamMuted))),
                if (item.overview != null) ...[
                  const SizedBox(height: 10),
                  _enter(
                    entrance,
                    2,
                    Text(item.overview!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.45)),
                  ),
                ],
                const SizedBox(height: 18),
                _enter(
                  entrance,
                  3,
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      WfButton.primary(
                        label: l.actionPlay,
                        icon: LucideIcons.play,
                        onPressed: () => unawaited(playItem(context, ref, item)),
                      ),
                      WfButton.secondary(
                        label: l.actionDetails,
                        icon: LucideIcons.info,
                        onPressed: () => openItem(context, item),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
