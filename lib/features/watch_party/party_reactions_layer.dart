import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/party_channel/party_channel_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/session_controller.dart';
import 'party_channel.dart';
import 'party_chat_bubble.dart';

/// Un fotogramma di una reazione in volo: opacità, scala e di quanto è
/// salita.
typedef ReactionFrame = ({double opacity, double scale, double lift});

/// Il fotogramma di una reazione partita da [elapsed] (spec E §10.4).
/// Complete: scala da [PartyReactionsLayer.popFrom] a 1, salita di
/// [PartyReactionsLayer.rise] che rallenta, dissolvenza alla fine. Ridotte:
/// solo dissolvenza in entrata e in uscita, ferma.
ReactionFrame reactionFrame(Duration elapsed, {required bool reduced}) {
  double progress(Duration from, Duration span) => span == Duration.zero
      ? 1
      : ((elapsed - from).inMicroseconds / span.inMicroseconds).clamp(0, 1);
  if (reduced) {
    final fadeOutFrom =
        PartyReactionsLayer.reducedFadeIn + PartyReactionsLayer.reducedHold;
    final opacity = elapsed < PartyReactionsLayer.reducedFadeIn
        ? progress(Duration.zero, PartyReactionsLayer.reducedFadeIn)
        : 1 - progress(fadeOutFrom, PartyReactionsLayer.reducedFadeOut);
    return (opacity: opacity, scale: 1, lift: 0);
  }
  final pop = WfMotion.emphasized
      .transform(progress(Duration.zero, PartyReactionsLayer.popDuration));
  final scale = PartyReactionsLayer.popFrom +
      (1 - PartyReactionsLayer.popFrom) * pop;
  final lift = PartyReactionsLayer.rise *
      WfMotion.decelerate
          .transform(progress(Duration.zero, PartyReactionsLayer.flightDuration));
  final fadeFrom =
      PartyReactionsLayer.flightDuration - PartyReactionsLayer.fadeOutDuration;
  final opacity =
      1 - progress(fadeFrom, PartyReactionsLayer.fadeOutDuration);
  return (opacity: opacity, scale: scale, lift: lift);
}

/// Scostamento orizzontale di una reazione, da 0 a
/// [PartyReactionsLayer.maxJitter]: calcolato dall'id, così è stabile (anche
/// nei test) e reazioni diverse non si sovrappongono tutte.
double reactionJitter(String id) {
  var sum = 0;
  for (final unit in id.codeUnits) {
    sum = (sum * 31 + unit) & 0x7fffffff;
  }
  return (sum % (PartyReactionsLayer.maxJitter.toInt() + 1)).toDouble();
}

String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Le reazioni in volo nel player (spec E §10.4): nascono in basso a destra,
/// salgono e svaniscono, con il nome di chi le ha mandate. Un solo ticker
/// per tutte; non prende i clic.
class PartyReactionsLayer extends ConsumerStatefulWidget {
  const PartyReactionsLayer({super.key});

  /// Posizione nel player: a destra, alla stessa altezza della chat.
  static const right = 24.0;
  static const bottom = 150.0;

  /// Scostamento orizzontale massimo.
  static const maxJitter = 80.0;

  /// Dimensione delle emoji.
  static const emojiSize = 40.0;

  /// Reazioni in volo insieme al massimo: le altre si scartano.
  static const maxInFlight = 12;

  /// Animazioni complete: la comparsa con la scala, il volo intero e la
  /// dissolvenza finale (dentro il volo).
  static const popDuration = Duration(milliseconds: 200);
  static const flightDuration = Duration(milliseconds: 2400);
  static const fadeOutDuration = Duration(milliseconds: 600);

  /// Scala di partenza.
  static const popFrom = 0.6;

  /// Di quanto sale.
  static const rise = 140.0;

  /// Animazioni ridotte: entrata, sosta, uscita.
  static const reducedFadeIn = WfMotion.fast;
  static const reducedHold = Duration(milliseconds: 1600);
  static const reducedFadeOut = Duration(milliseconds: 300);

  /// Vita con le animazioni ridotte: entrata + sosta + uscita (le `Duration`
  /// non si sommano in una costante).
  static const reducedLifetime = Duration(milliseconds: 2050);

  /// Spazio del livello: lo scostamento più un'emoji con il nome, e la
  /// salita più un'emoji con il nome.
  static const _itemExtent = 72.0;
  static const width = maxJitter + _itemExtent;
  static const height = rise + _itemExtent;

  @override
  ConsumerState<PartyReactionsLayer> createState() =>
      _PartyReactionsLayerState();
}

class _Flight {
  _Flight(this.event, this.startedAt, this.jitter);

  final PartyReactionEvent event;

  /// Tempo del ticker alla partenza.
  final Duration startedAt;
  final double jitter;
}

class _PartyReactionsLayerState extends ConsumerState<PartyReactionsLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final StreamSubscription<PartyReactionEvent> _subscription;
  final _flights = <_Flight>[];
  Duration _now = Duration.zero;
  bool _reduced = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _subscription = ref
        .read(partyChannelProvider.notifier)
        .reactions
        .listen(_onReaction);
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _ticker.dispose();
    super.dispose();
  }

  Duration get _lifetime => _reduced
      ? PartyReactionsLayer.reducedLifetime
      : PartyReactionsLayer.flightDuration;

  void _onReaction(PartyReactionEvent event) {
    if (!mounted || _flights.length >= PartyReactionsLayer.maxInFlight) {
      return;
    }
    if (!_ticker.isActive) {
      // `elapsed` riparte da zero a ogni partenza del ticker.
      _now = Duration.zero;
      _ticker.start();
    }
    setState(() =>
        _flights.add(_Flight(event, _now, reactionJitter(event.id))));
  }

  void _onTick(Duration elapsed) {
    _now = elapsed;
    setState(() => _flights
        .removeWhere((flight) => elapsed - flight.startedAt >= _lifetime));
    if (_flights.isEmpty) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    _reduced = WfMotion.of(context).isReduced;
    final l = AppLocalizations.of(context);
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    return IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox(
          width: PartyReactionsLayer.width,
          height: PartyReactionsLayer.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final flight in _flights)
                _buildFlight(flight, l,
                    mine: userId != null &&
                        _normalizeId(flight.event.userId) ==
                            _normalizeId(userId)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlight(_Flight flight, AppLocalizations l,
      {required bool mine}) {
    final frame = reactionFrame(_now - flight.startedAt, reduced: _reduced);
    return Positioned(
      key: ValueKey('party-reaction-flight-${flight.event.id}'),
      right: flight.jitter,
      bottom: frame.lift,
      child: Opacity(
        opacity: frame.opacity,
        child: Transform.scale(
          scale: frame.scale,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                flight.event.reaction.emoji,
                style: const TextStyle(
                  fontSize: PartyReactionsLayer.emojiSize,
                  height: 1.1,
                  fontFamilyFallback: partyEmojiFontFallback,
                ),
              ),
              const SizedBox(height: 2),
              _NameLabel(mine ? l.partyChatYou : flight.event.userName),
            ],
          ),
        ),
      ),
    );
  }
}

/// Il nome sotto una reazione: piccolo, su fondo scuro.
class _NameLabel extends StatelessWidget {
  const _NameLabel(this.name);

  /// Opacità del fondo.
  static const backgroundAlpha = 0.65;

  final String name;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: WfColors.bg.withValues(alpha: backgroundAlpha),
          borderRadius: BorderRadius.circular(PartyChatBubble.radius),
        ),
        child: Text(name,
            style: const TextStyle(color: WfColors.cream, fontSize: 11)),
      );
}
