import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/video/video_engine.dart';
import '../library/item_labels.dart';

/// Barra di avanzamento: posizione, parte già scaricata, salto con clic o
/// trascinamento.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, required this.engine, required this.onSeek});

  final VideoEngine engine;
  final ValueChanged<Duration> onSeek;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  late Duration _position;
  late Duration _duration;
  late Duration _buffer;

  /// Valore durante il trascinamento (secondi): non segue il video.
  double? _dragSeconds;
  final _subscriptions = <StreamSubscription<Duration>>[];

  @override
  void initState() {
    super.initState();
    final engine = widget.engine;
    _position = engine.position;
    _duration = engine.duration;
    _buffer = engine.buffer;
    _subscriptions.addAll([
      engine.positionStream.listen((value) => setState(() => _position = value)),
      engine.durationStream.listen((value) => setState(() => _duration = value)),
      engine.bufferStream.listen((value) => setState(() => _buffer = value)),
    ]);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  static double _seconds(Duration duration) => duration.inMilliseconds / 1000;

  @override
  Widget build(BuildContext context) {
    final max = math.max(_seconds(_duration), 1.0);
    double clamp(double value) => value.clamp(0.0, max);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: WfColors.gold,
        secondaryActiveTrackColor: WfColors.cream.withValues(alpha: 0.35),
        inactiveTrackColor: WfColors.cream.withValues(alpha: 0.15),
        thumbColor: WfColors.gold,
        overlayColor: WfColors.gold.withValues(alpha: 0.2),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      child: Slider(
        value: clamp(_dragSeconds ?? _seconds(_position)),
        max: max,
        secondaryTrackValue: clamp(_seconds(_buffer)),
        onChangeStart: (value) => setState(() => _dragSeconds = value),
        onChanged: (value) => setState(() => _dragSeconds = value),
        onChangeEnd: (value) {
          final target = Duration(milliseconds: (value * 1000).round());
          setState(() {
            _dragSeconds = null;
            _position = target;
          });
          widget.onSeek(target);
        },
      ),
    );
  }
}

/// Tempo trascorso e totale: "12:03 / 1:45:00".
class TimeLabel extends StatefulWidget {
  const TimeLabel({super.key, required this.engine});

  final VideoEngine engine;

  @override
  State<TimeLabel> createState() => _TimeLabelState();
}

class _TimeLabelState extends State<TimeLabel> {
  late Duration _position;
  late Duration _duration;
  final _subscriptions = <StreamSubscription<Duration>>[];

  @override
  void initState() {
    super.initState();
    _position = widget.engine.position;
    _duration = widget.engine.duration;
    _subscriptions.addAll([
      widget.engine.positionStream.listen((value) {
        // Il testo cambia solo ogni secondo.
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        '${formatClock(_position)} / ${formatClock(_duration)}',
        style: const TextStyle(color: WfColors.cream),
      );
}
