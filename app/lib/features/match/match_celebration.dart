import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/ticket_shape.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';

/// Quanto resta in vista "È un match!" se nessuno lo chiude prima.
const matchCelebrationDuration = Duration(seconds: 2);

/// Il biglietto dello strato: larghezza, locandina 2:3, angoli.
const _ticketWidth = 260.0;
const _posterHeight = _ticketWidth * 3 / 2;
const _ticketRadius = 12.0;

/// Entrata del biglietto: da 0,8 e -4° a dimensione piena.
const _ticketEntrance = Duration(milliseconds: 500);
const _ticketAngle = -4 * math.pi / 180;

/// Lo strato "È un match!" (spec §5.7): la locandina in un biglietto e il
/// testo in oro.
/// Dopo [matchCelebrationDuration], o a un tasto o un clic, chiama [onDone]
/// una volta sola.
class MatchCelebration extends ConsumerStatefulWidget {
  const MatchCelebration(
      {super.key, required this.id, required this.item, required this.onDone});

  /// L'id del match: dà la chiave anche se il titolo non è ancora arrivato.
  final String id;

  /// `null` = titolo non più disponibile: resta il solo testo.
  final JellyfinItem? item;
  final VoidCallback onDone;

  @override
  ConsumerState<MatchCelebration> createState() => _MatchCelebrationState();
}

class _MatchCelebrationState extends ConsumerState<MatchCelebration> {
  late Timer _timer;
  final _focus = FocusNode(debugLabel: 'match-celebration');

  /// Chi aveva il focus (il mazzo): lo riprende alla chiusura.
  FocusNode? _previous;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(matchCelebrationDuration, _finish);
    _previous = FocusManager.instance.primaryFocus;
    // Il mazzo ha già il focus e l'autofocus non lo toglie: va chiesto.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(MatchCelebration old) {
    super.didUpdateWidget(old);
    // Un altro match in coda: stesso strato, il focus resta qui e si
    // restituisce al mazzo solo quando l'ultimo si chiude.
    if (old.id == widget.id) return;
    _done = false;
    _timer.cancel();
    _timer = Timer(matchCelebrationDuration, _finish);
  }

  @override
  void dispose() {
    _timer.cancel();
    _focus.dispose();
    final previous = _previous;
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (previous.context?.mounted ?? false) previous.requestFocus();
      });
    }
    super.dispose();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _timer.cancel();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = widget.item;
    final motion = WfMotion.of(context);
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.handled;
        _finish();
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: motion.duration(WfMotion.medium),
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: ColoredBox(
            color: WfColors.bg.withValues(alpha: 0.82),
            child: Center(
              key: Key('match-celebration-${widget.id}'),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item != null)
                      motion.isReduced
                          ? _ticket(item)
                          : TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: _ticketEntrance,
                              curve: Curves.easeOutBack,
                              builder: (context, t, child) => Transform.rotate(
                                angle: _ticketAngle * (1 - t),
                                child: Transform.scale(
                                    scale: 0.8 + 0.2 * t, child: child),
                              ),
                              child: _ticket(item),
                            ),
                    const SizedBox(height: 22),
                    Text(l.matchItsAMatch,
                        textAlign: TextAlign.center,
                        style: WfText.display(64, color: WfColors.gold)
                            .copyWith(letterSpacing: 2)),
                    const SizedBox(height: 4),
                    Text(l.matchLikedByEveryone,
                        style: const TextStyle(color: WfColors.creamMuted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// La locandina nel biglietto: strappo orizzontale e matrice col nome.
  Widget _ticket(JellyfinItem item) => SizedBox(
        key: const Key('match-celebration-ticket'),
        width: _ticketWidth,
        child: Stack(
          children: [
            ClipPath(
              clipper: const TicketClipper.horizontal(_posterHeight,
                  radius: _ticketRadius),
              child: ColoredBox(
                color: WfColors.surface,
                child: Column(
                  children: [
                    SizedBox(
                      height: _posterHeight,
                      width: _ticketWidth,
                      child: WfImage(
                          image: ref.watch(imageUrlsProvider).poster(item)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                    painter: TicketTearPainter.horizontal(_posterHeight)),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_ticketRadius),
                    border: Border.all(color: WfColors.gold, width: 2),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
