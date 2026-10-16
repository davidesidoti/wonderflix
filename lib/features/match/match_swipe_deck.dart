import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'match_card.dart';

/// Quanta parte della larghezza della carta basta per votare (spec P §7.3).
const matchSwipeThreshold = 0.3;

/// Velocità orizzontale (px/s) oltre la quale basta uno scatto.
const matchSwipeVelocity = 800.0;

/// Rotazione massima della carta, in radianti (12°).
const matchSwipeMaxAngle = 12 * math.pi / 180;

/// Rapporto larghezza / altezza della carta.
const _cardAspect = 1.5;

/// Quante carte si vedono impilate.
const _visibleCards = 3;

/// Di quanto si rimpicciolisce ogni carta sotto la prima.
const _peekScaleStep = 0.04;

/// Fin dove vola la carta, in larghezze di carta.
const _flyDistance = 1.4;

const _buttonSize = 28.0;
const _labelBorder = 3.0;

/// Il mazzo del match: la carta in cima si trascina o si vota con ✗ ✓ e ← →.
/// [cards] ha in [0] la carta in cima. Il voto parte a fine volo, una volta
/// sola per carta; la pagina toglie la carta votata da [cards].
class MatchSwipeDeck extends StatefulWidget {
  const MatchSwipeDeck(
      {super.key,
      required this.cards,
      required this.onVote,
      this.enabled = true});

  final List<JellyfinItem> cards;

  /// `true` = sì, `false` = no. Risponde `false` se il voto non è partito: la
  /// carta torna al centro e si può votare di nuovo.
  final Future<bool> Function(bool yes) onVote;
  final bool enabled;

  @override
  State<MatchSwipeDeck> createState() => _MatchSwipeDeckState();
}

class _MatchSwipeDeckState extends State<MatchSwipeDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this);

  /// Spostamento orizzontale della carta in cima.
  double _dx = 0;

  /// Da dove parte l'animazione in corso, e verso dove (1 sì, -1 no, 0 torna).
  double _from = 0;
  int _dir = 0;

  /// Un voto è in volo (o la carta sta tornando): i nuovi si ignorano.
  bool _busy = false;
  double _width = 1;

  @override
  void didUpdateWidget(MatchSwipeDeck old) {
    super.didUpdateWidget(old);
    // Un'altra carta in cima (voto riuscito o carta tornata): si riparte.
    if (widget.cards.firstOrNull?.id != old.cards.firstOrNull?.id) {
      _anim.stop();
      _dx = 0;
      _dir = 0;
      _busy = false;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  bool get _canVote => widget.enabled && !_busy && widget.cards.isNotEmpty;

  void _run(int dir) {
    _dir = dir;
    _from = _dx;
    _busy = true;
    final motion = WfMotion.of(context);
    _anim.duration = motion.duration(WfMotion.medium);
    _anim.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      if (_dir == 0) {
        setState(() {
          _dx = 0;
          _busy = false;
        });
      } else {
        unawaited(widget.onVote(_dir > 0).then((sent) {
          // Un voto riuscito cambia la carta in cima (didUpdateWidget); uno
          // fallito, anche subito, lascia la stessa carta: va rimessa in gioco.
          if (!sent && mounted) {
            setState(() {
              _anim.value = 0;
              _dx = 0;
              _dir = 0;
              _busy = false;
            });
          }
        }));
      }
    });
  }

  void _vote(bool yes) {
    if (_canVote) _run(yes ? 1 : -1);
  }

  void _dragEnd(DragEndDetails details) {
    if (!_canVote) return;
    final velocity = details.primaryVelocity ?? 0;
    final farEnough = _dx.abs() > _width * matchSwipeThreshold;
    // Lo scatto decide il lato; altrimenti la distanza.
    if (velocity.abs() > matchSwipeVelocity) {
      _vote(velocity > 0);
    } else if (farEnough) {
      _vote(_dx > 0);
    } else {
      _run(0);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is! KeyDownEvent ||
        HardwareKeyboard.instance.isAltPressed ||
        (key != LogicalKeyboardKey.arrowRight &&
            key != LogicalKeyboardKey.arrowLeft)) {
      return KeyEventResult.ignored;
    }
    _vote(key == LogicalKeyboardKey.arrowRight);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shown = widget.cards.take(_visibleCards).toList();
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: _cardAspect,
            child: LayoutBuilder(builder: (context, box) {
              _width = box.maxWidth;
              return Stack(
                children: [
                  for (var i = shown.length - 1; i >= 1; i--)
                    Positioned.fill(
                      key: ValueKey(shown[i].id),
                      child: Transform.scale(
                          scale: 1 - _peekScaleStep * i,
                          child: MatchCard(item: shown[i])),
                    ),
                  if (shown.isNotEmpty)
                    Positioned.fill(
                      key: ValueKey(shown[0].id),
                      child: _top(shown[0], l),
                    ),
                ],
              );
            }),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _VoteButton(
                  key: const Key('match-no'),
                  tooltip: l.matchNo,
                  icon: LucideIcons.x,
                  color: WfColors.error,
                  onPressed: () => _vote(false)),
              const SizedBox(width: 32),
              _VoteButton(
                  key: const Key('match-yes'),
                  tooltip: l.matchYes,
                  icon: LucideIcons.check,
                  color: WfColors.online,
                  onPressed: () => _vote(true)),
            ],
          ),
        ],
      ),
    );
  }

  /// La carta in cima: trascinata, in volo o di ritorno.
  Widget _top(JellyfinItem item, AppLocalizations l) {
    final reduced = WfMotion.of(context).isReduced;
    return GestureDetector(
      onHorizontalDragUpdate:
          _canVote ? (d) => setState(() => _dx += d.delta.dx) : null,
      onHorizontalDragEnd: _dragEnd,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final t = WfMotion.emphasized.transform(_anim.value);
          final flying = _dir != 0 && _busy;
          // Ridotto: la carta non vola né ruota, si dissolve soltanto.
          final target = (flying && !reduced) ? _dir * _width * _flyDistance : _dx;
          final x = _busy && _dir == 0
              ? _from * (1 - t)
              : (flying && !reduced ? _from + (target - _from) * t : _dx);
          final progress =
              (x.abs() / (_width * matchSwipeThreshold)).clamp(0.0, 1.0);
          final angle = reduced ? 0.0 : x.sign * matchSwipeMaxAngle * progress;
          return Opacity(
            opacity: flying && reduced ? 1 - _anim.value : 1,
            child: Transform.translate(
              offset: Offset(x, 0),
              child: Transform.rotate(
                angle: angle,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child!,
                    _Label(
                        opacityKey: const Key('match-label-yes'),
                        text: l.matchYes,
                        color: WfColors.online,
                        opacity: x > 0 ? progress : 0,
                        alignment: Alignment.topLeft),
                    _Label(
                        opacityKey: const Key('match-label-no'),
                        text: l.matchNo,
                        color: WfColors.error,
                        opacity: x < 0 ? progress : 0,
                        alignment: Alignment.topRight),
                  ],
                ),
              ),
            ),
          );
        },
        child: MatchCard(item: item),
      ),
    );
  }
}

/// "SÌ" / "NO" sulla carta, in proporzione alla distanza.
class _Label extends StatelessWidget {
  const _Label(
      {required this.opacityKey,
      required this.text,
      required this.color,
      required this.opacity,
      required this.alignment});

  final Key opacityKey;
  final String text;
  final Color color;
  final double opacity;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Opacity(
            key: opacityKey,
            opacity: opacity,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: color, width: _labelBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(text.toUpperCase(),
                  style: WfText.display(32).copyWith(color: color)),
            ),
          ),
        ),
      );
}

class _VoteButton extends StatelessWidget {
  const _VoteButton(
      {super.key,
      required this.tooltip,
      required this.icon,
      required this.color,
      required this.onPressed});

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        iconSize: _buttonSize,
        padding: const EdgeInsets.all(16),
        style: IconButton.styleFrom(
          backgroundColor: WfColors.surfaceHigh,
          foregroundColor: color,
          side: BorderSide(color: color, width: 2),
        ),
        icon: Icon(icon),
        onPressed: onPressed,
      );
}
