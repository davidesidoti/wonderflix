import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/video/video_engine.dart';
import '../library/item_labels.dart';

/// Capitolo in corso in [position] (l'ultimo iniziato).
ChapterMark? chapterAt(List<ChapterMark> chapters, Duration position) {
  ChapterMark? current;
  for (final chapter in chapters) {
    if (chapter.start <= position) current = chapter;
  }
  return current;
}

/// Tacche dei capitoli sulla traccia della barra.
class ChapterTicksPainter extends CustomPainter {
  ChapterTicksPainter({required this.fractions, required this.inset});

  /// Posizione di ogni tacca, 0–1.
  final List<double> fractions;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = WfColors.cream.withValues(alpha: 0.7);
    final track = size.width - 2 * inset;
    for (final fraction in fractions) {
      final x = inset + fraction.clamp(0.0, 1.0) * track;
      canvas.drawRect(
          Rect.fromCenter(center: Offset(x, size.height / 2), width: 2, height: 10),
          paint);
    }
  }

  @override
  bool shouldRepaint(ChapterTicksPainter oldDelegate) =>
      !listEquals(oldDelegate.fractions, fractions) || oldDelegate.inset != inset;
}

/// Barra di avanzamento: posizione, parte già scaricata, tacche dei
/// capitoli, anteprima al passaggio del mouse, salto con clic o
/// trascinamento.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.engine,
    required this.onSeek,
    this.chapters = const [],
    this.preview,
  });

  final VideoEngine engine;
  final ValueChanged<Duration> onSeek;
  final List<ChapterMark> chapters;

  /// Immagine di anteprima per una posizione (trickplay); `null` = solo il
  /// tempo.
  final Widget? Function(Duration position)? preview;

  /// Margine orizzontale della traccia dentro lo Slider (= raggio
  /// dell'alone del cursore): serve a sapere a che punto è il mouse.
  static const trackInset = 16.0;

  static const previewWidth = 240.0;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  late Duration _position;
  late Duration _duration;
  late Duration _buffer;

  /// Valore durante il trascinamento (secondi): non segue il video.
  double? _dragSeconds;

  /// Posizione orizzontale del mouse sopra la barra.
  double? _hoverX;
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
    final durationSeconds = _seconds(_duration);
    final max = math.max(durationSeconds, 1.0);
    double clamp(double value) => value.clamp(0.0, max);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final track = math.max(width - 2 * SeekBar.trackInset, 1.0);
      Duration positionAt(double x) {
        final fraction = ((x - SeekBar.trackInset) / track).clamp(0.0, 1.0);
        return Duration(milliseconds: (fraction * durationSeconds * 1000).round());
      }

      final hoverX = _hoverX;
      final hovered = hoverX == null || durationSeconds <= 0
          ? null
          : positionAt(hoverX);
      return MouseRegion(
        onHover: (event) => setState(() => _hoverX = event.localPosition.dx),
        onExit: (_) => setState(() => _hoverX = null),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: WfColors.gold,
                secondaryActiveTrackColor: WfColors.cream.withValues(alpha: 0.35),
                inactiveTrackColor: WfColors.cream.withValues(alpha: 0.15),
                thumbColor: WfColors.gold,
                overlayColor: WfColors.gold.withValues(alpha: 0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: SeekBar.trackInset),
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
            ),
            // Sopra lo Slider, altrimenti la traccia le copre.
            if (durationSeconds > 0 && widget.chapters.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const Key('chapter-ticks'),
                    painter: ChapterTicksPainter(
                      fractions: [
                        for (final chapter in widget.chapters)
                          if (chapter.start > Duration.zero)
                            _seconds(chapter.start) / durationSeconds,
                      ],
                      inset: SeekBar.trackInset,
                    ),
                  ),
                ),
              ),
            if (hoverX != null && hovered != null)
              Positioned(
                left: (hoverX - SeekBar.previewWidth / 2).clamp(
                    0.0, math.max(width - SeekBar.previewWidth, 0.0)),
                bottom: 40,
                width: SeekBar.previewWidth,
                child: IgnorePointer(
                  child: _SeekPreview(
                    position: hovered,
                    chapter: chapterAt(widget.chapters, hovered),
                    image: widget.preview?.call(hovered),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _SeekPreview extends StatelessWidget {
  const _SeekPreview({required this.position, this.chapter, this.image});

  final Duration position;
  final ChapterMark? chapter;
  final Widget? image;

  @override
  Widget build(BuildContext context) {
    final name = chapter?.name;
    final picture = image;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (picture != null)
          ClipRRect(borderRadius: BorderRadius.circular(6), child: picture),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            name == null
                ? formatClock(position)
                : '${formatClock(position)} · $name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: WfColors.cream),
          ),
        ),
      ],
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
