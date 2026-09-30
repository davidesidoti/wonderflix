import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/hero_launch.dart';
import '../app/motion.dart';
import '../app/navigation.dart';
import '../core/jellyfin/item_models.dart';
import '../features/playback/play_launcher.dart';
import 'card_preview.dart';

/// Suffisso della sorgente del volo per l'anteprima: la card e la sua
/// anteprima stanno nella stessa pagina e non possono avere lo stesso tag.
const previewHeroSuffix = '.preview';

/// Avvolge una card: con il mouse fermo sopra per [previewHoverDelay] apre
/// l'anteprima nell'overlay principale (spec C §7). Solo con il mouse: con
/// tocco e tastiera il clic della card apre la scheda.
class CardPreviewHost extends ConsumerStatefulWidget {
  const CardPreviewHost({
    super.key,
    required this.item,
    required this.heroSource,
    required this.child,
  });

  final JellyfinItem item;

  /// Sorgente del volo della card (già resa unica per la pagina), o `null`.
  final String? heroSource;
  final Widget child;

  @override
  ConsumerState<CardPreviewHost> createState() => _CardPreviewHostState();
}

class _CardPreviewHostState extends ConsumerState<CardPreviewHost>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _portal = OverlayPortalController();

  /// Letto in `initState`: in `dispose` `ref` non si usa.
  late final CardPreviewController _previews;
  late final AnimationController _open;

  /// Corpo dell'anteprima: 1 normalmente, 0 in uscita verso la scheda.
  late final AnimationController _body;

  Timer? _hoverTimer;
  ScrollPosition? _scroll;
  Animation<double>? _routeCover;

  /// "Dettagli": l'immagine vola, il resto è già sparito.
  bool _leaving = false;

  /// Chiusa con Esc, rotella, scroll o finestra non attiva: il mouse può
  /// essere ancora sulla card, che torna scoperta e riceve un "enter". La
  /// card non riapre l'anteprima finché il mouse non si è visto fuori.
  bool _dismissed = false;

  bool get _showing => _portal.isShowing;

  @override
  void initState() {
    super.initState();
    _previews = ref.read(cardPreviewProvider.notifier);
    _open = AnimationController(vsync: this, duration: WfMotion.medium);
    _body = AnimationController(vsync: this, duration: WfMotion.fast, value: 1);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // La pagina della card non è più in cima (push, go): via l'anteprima,
    // salvo l'uscita verso la scheda, che si chiude a transizione finita.
    // Siamo nella build: la chiusura avviene al fotogramma dopo.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (!current && _showing && !_leaving) _hideAfterFrame();
    if (current && _leaving) _hideAfterFrame();
  }

  @override
  void didUpdateWidget(CardPreviewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Griglie e righe senza chiavi riusano l'host per un altro titolo (es.
    // tolto da La mia lista): l'anteprima del titolo di prima si chiude, e
    // quella del nuovo titolo non si apre finché il mouse non esce dalla
    // card.
    if (oldWidget.item.id != widget.item.id) {
      _hoverTimer?.cancel();
      _hideAfterFrame(dismiss: true);
    }
  }

  /// Chiusura chiesta durante la build (dipendenze, widget aggiornato): il
  /// provider e l'overlay non si toccano mentre l'albero si costruisce.
  bool _hidePending = false;
  bool _hidePendingDismiss = false;

  void _hideAfterFrame({bool dismiss = false}) {
    _hidePendingDismiss |= dismiss;
    if (_hidePending) return;
    _hidePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dismiss = _hidePendingDismiss;
      _hidePending = false;
      _hidePendingDismiss = false;
      if (mounted) _hide(immediately: true, dismiss: dismiss);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _hide(immediately: true, dismiss: true);
    }
  }

  void _onEnter(PointerEnterEvent event) {
    if (event.kind != PointerDeviceKind.mouse || _showing || _dismissed) return;
    _hoverTimer?.cancel();
    if (_previews.opensImmediately()) {
      _show();
    } else {
      _hoverTimer = Timer(previewHoverDelay, _show);
    }
  }

  void _onExitCard(PointerExitEvent event) => _hoverTimer?.cancel();

  void _show() {
    _hoverTimer?.cancel();
    if (!mounted || _showing) return;
    final motion = WfMotion.of(context);
    _previews.open(this);
    _leaving = false;
    _body.value = 1;
    _open.duration = motion.duration(WfMotion.medium);
    _portal.show();
    unawaited(_open.forward(from: 0));
    _scroll = Scrollable.maybeOf(context)?.position;
    _scroll?.addListener(_onScroll);
    HardwareKeyboard.instance.addHandler(_onKey);
    setState(() {});
  }

  void _onScroll() => _hide(immediately: true, dismiss: true);

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _hide(dismiss: true);
      return true;
    }
    return false;
  }

  /// Dopo una chiusura con [_dismissed]: il primo movimento del mouse fuori
  /// dalla card la riattiva.
  void _watchPointer(PointerEvent event) {
    if (event is! PointerHoverEvent) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final local = box.globalToLocal(event.position);
    if (!(Offset.zero & box.size).contains(local)) _rearm();
  }

  void _rearm() {
    if (!_dismissed) return;
    _dismissed = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_watchPointer);
  }

  void _detach() {
    _scroll?.removeListener(_onScroll);
    _scroll = null;
    HardwareKeyboard.instance.removeHandler(_onKey);
    _routeCover?.removeStatusListener(_onRouteCover);
    _routeCover = null;
  }

  /// Chiude l'anteprima: in dissolvenza breve, o subito. Con [dismiss] la
  /// card non la riapre finché il mouse non ne è uscito ([_dismissed]).
  void _hide({bool immediately = false, bool dismiss = false}) {
    _hoverTimer?.cancel();
    if (!_showing) return;
    // Chiamata durante la build o il layout (un listener del provider, uno
    // scroll corretto dal layout): si rimanda al fotogramma dopo.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _hideAfterFrame(dismiss: dismiss);
      return;
    }
    _detach();
    _previews.close(this);
    if (dismiss && !_dismissed) {
      _dismissed = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_watchPointer);
    }
    void done() {
      if (!mounted) return;
      _leaving = false;
      _portal.hide();
      setState(() {});
    }

    if (immediately) {
      _open.value = 0;
      done();
    } else {
      _open.duration = WfMotion.fast;
      unawaited(_open.reverse().whenComplete(done));
    }
  }

  void _play() {
    _hide(immediately: true);
    unawaited(playItem(context, ref, widget.item));
  }

  void _details() {
    final source = widget.heroSource;
    if (source == null || WfMotion.of(context).isReduced) {
      _hide(immediately: true);
      openItem(context, widget.item);
      return;
    }
    // L'immagine vola verso la testata: resta finché la pagina nuova è
    // entrata; il resto sparisce subito e non riceve più clic.
    setState(() => _leaving = true);
    _detach();
    // Per il resto dell'app l'anteprima è già chiusa (Esc torna indietro,
    // il carosello riparte); il portale resta montato fino a fine
    // transizione, e il listener del provider lo ignora ([_leaving]).
    _previews.close(this);
    unawaited(_body.animateTo(0, duration: WfMotion.fast));
    final cover = ModalRoute.of(context)?.secondaryAnimation;
    _routeCover = cover;
    cover?.addStatusListener(_onRouteCover);
    openItem(context, widget.item, heroSource: '$source$previewHeroSuffix');
  }

  void _onRouteCover(AnimationStatus status) {
    if (status == AnimationStatus.completed) _hide(immediately: true);
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _detach();
    _rearm();
    WidgetsBinding.instance.removeObserver(this);
    final previews = _previews;
    final id = this;
    // Non si modifica un provider mentre l'albero si smonta.
    unawaited(Future.microtask(() => previews.close(id)));
    _open.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Un'altra card ha aperto la sua anteprima: questa si chiude. La
    // chiusura di questa (openId nullo) non conta: troncherebbe la sua
    // dissolvenza.
    ref.listen(cardPreviewProvider, (previous, next) {
      final other = next.openId;
      if (_showing && !_leaving && other != null && !identical(other, this)) {
        _hide(immediately: true);
      }
    });
    final motion = WfMotion.of(context);
    final source = widget.heroSource;
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context, info) {
        final card = MatrixUtils.transformRect(
            info.childPaintTransform, Offset.zero & info.childSize);
        final rect = previewRect(card: card, overlay: info.overlaySize);
        final preview = Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              // In uscita verso la scheda è trasparente anche ai clic: la
              // pagina nuova sta sotto.
              child: IgnorePointer(
                ignoring: _leaving,
                child: MouseRegion(
                  onExit: (_) {
                    if (!_leaving) _hide();
                  },
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        _hide(immediately: true, dismiss: true);
                      }
                    },
                    child: AnimatedBuilder(
                      animation: _open,
                      builder: (context, child) {
                        final t = _open.value;
                        final scale = motion.isReduced
                            ? 1.0
                            : 0.6 + 0.4 * WfMotion.bounce.transform(t);
                        return Opacity(
                          opacity: WfMotion.standard.transform(t).clamp(0.0, 1.0),
                          child: Transform.scale(scale: scale, child: child),
                        );
                      },
                      child: RepaintBoundary(
                        child: CardPreview(
                          item: widget.item,
                          heroTag: source == null
                              ? null
                              : WfHeroTag(widget.item.id,
                                  '$source$previewHeroSuffix'),
                          body: _body,
                          onPlay: _play,
                          onDetails: _details,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
        // I tooltip dei pulsanti cercano l'Overlay più vicino risalendo gli
        // elementi: senza questo troverebbero quello del navigatore della
        // shell, sotto l'overlay principale (asserzione in debug, tooltip
        // coperto dall'anteprima in release). Le zone vuote lasciano passare
        // i clic alla pagina.
        return Overlay.wrap(child: preview);
      },
      child: MouseRegion(
        onEnter: _onEnter,
        onExit: _onExitCard,
        child: widget.child,
      ),
    );
  }
}
