import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';

/// "−49:55 · finisce alle 23:41": quanto manca e, con [withEnd], a che ora si
/// finisce a velocità [rate]. `null` finché la durata non è nota.
String? formatRemaining(
  AppLocalizations l, {
  required Duration position,
  required Duration duration,
  required DateTime now,
  double rate = 1,
  bool withEnd = true,
}) {
  if (duration <= Duration.zero) return null;
  final clock = formatClock(_left(position, duration));
  if (!withEnd) return l.playerTimeLeftShort(clock);
  final end = _endAt(now, position: position, duration: duration, rate: rate);
  return l.playerTimeLeft(clock, DateFormat.Hm(l.localeName).format(end));
}

Duration _left(Duration position, Duration duration) =>
    duration > position ? duration - position : Duration.zero;

/// Ora di fine a velocità [rate] (zero o meno vale 1×).
DateTime _endAt(DateTime now,
        {required Duration position,
        required Duration duration,
        required double rate}) =>
    now.add(_left(position, duration) * (1 / (rate > 0 ? rate : 1)));

const _tabular = [FontFeature.tabularFigures()];

/// Tempo trascorso: "12:03". Il testo cambia solo ogni secondo.
class PositionLabel extends StatefulWidget {
  const PositionLabel({super.key, required this.engine});

  final VideoEngine engine;

  @override
  State<PositionLabel> createState() => _PositionLabelState();
}

class _PositionLabelState extends State<PositionLabel> {
  late Duration _position = widget.engine.position;
  StreamSubscription<Duration>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.engine.positionStream.listen((value) {
      if (value.inSeconds != _position.inSeconds) {
        setState(() => _position = value);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        formatClock(_position),
        style: const TextStyle(
            color: WfColors.cream,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: _tabular),
      );
}

/// Tempo che resta e ora di fine; vuoto finché non si sa la durata.
class RemainingLabel extends StatefulWidget {
  const RemainingLabel(
      {super.key, required this.engine, this.rate = 1, this.withEnd = true});

  final VideoEngine engine;
  final double rate;
  final bool withEnd;

  @override
  State<RemainingLabel> createState() => _RemainingLabelState();
}

class _RemainingLabelState extends State<RemainingLabel> {
  late Duration _position = widget.engine.position;
  late Duration _duration = widget.engine.duration;
  final _subscriptions = <StreamSubscription<Duration>>[];

  /// Rifà il testo quando l'ora di fine cambia minuto (anche in pausa, dove
  /// la posizione non si muove).
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      widget.engine.positionStream.listen((value) {
        if (value.inSeconds != _position.inSeconds) {
          setState(() => _position = value);
        }
      }),
      widget.engine.durationStream
          .listen((value) => setState(() => _duration = value)),
    ]);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _minute?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = clock.now();
    _minute?.cancel();
    if (widget.withEnd && _duration > Duration.zero) {
      final end = _endAt(now,
          position: _position, duration: _duration, rate: widget.rate);
      const minute = Duration.millisecondsPerMinute;
      _minute = Timer(
          Duration(milliseconds: minute - end.millisecondsSinceEpoch % minute),
          () => setState(() {}));
    }
    final text = formatRemaining(AppLocalizations.of(context),
        position: _position,
        duration: _duration,
        now: now,
        rate: widget.rate,
        withEnd: widget.withEnd);
    if (text == null) return const SizedBox.shrink();
    return Text(
      text,
      style: const TextStyle(
          color: WfColors.creamMuted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          fontFeatures: _tabular),
    );
  }
}
