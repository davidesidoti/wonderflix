import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import 'player_commands.dart';
import 'seek_segments.dart';

/// Capitolo in corso in [position] (l'ultimo iniziato).
ChapterMark? chapterAt(List<ChapterMark> chapters, Duration position) {
  ChapterMark? current;
  for (final chapter in chapters) {
    if (chapter.start <= position) current = chapter;
  }
  return current;
}

/// Nome della zona nell'anteprima della barra.
String seekZoneLabel(AppLocalizations l, SeekZoneKind kind) => switch (kind) {
      SeekZoneKind.recap => l.playerSegmentRecap,
      SeekZoneKind.intro => l.playerSegmentIntro,
      SeekZoneKind.outro => l.playerSegmentOutro,
    };

/// Disegno della barra (spec D §8): tratti per capitolo, parte scaricata e
/// vista, zone rigate, cursore.
class SeekBarPainter extends CustomPainter {
  SeekBarPainter({
    required this.segments,
    required this.zones,
    required this.duration,
    required this.position,
    required this.buffer,
    required this.hover,
    required this.hoveredSegment,
    required this.emphasis,
    required this.thumb,
    required this.thumbOpacity,
  });

  final List<SeekSegment> segments;
  final List<SeekZone> zones;
  final Duration duration;
  final Duration position;
  final Duration buffer;

  /// 0 = a riposo, 1 = mouse sulla barra.
  final double hover;

  /// Tratto sotto il mouse (`null` = nessuno) e quanto è cresciuto (0–1).
  final int? hoveredSegment;
  final double emphasis;

  /// Scala del cursore: 0 nascosto, 1 intero (il rimbalzo può superarlo).
  final double thumb;

  /// Opacità del cursore (0–1): con il movimento ridotto il cursore non
  /// cresce (spec D §6.2), sfuma soltanto.
  final double thumbOpacity;

  /// Altezze della traccia (spec D §8.2).
  static const restHeight = 4.0;
  static const hoverHeight = 6.0;
  static const hoveredSegmentHeight = 9.0;
  static const thumbRadius = 7.0;

  /// Alone del cursore oltre il suo raggio.
  static const thumbHalo = 4.0;

  /// Passo e spessore delle righe delle zone (spec D §8.3).
  static const stripeSpacing = 6.0;
  static const stripeWidth = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = SeekBar.trackInset;
    final track = math.max(size.width - 2 * inset, 1.0);
    final centerY = size.height / 2;
    final total = duration.inMicroseconds;
    final base = lerpDouble(restHeight, hoverHeight, hover)!;
    final inactive = Paint()..color = WfColors.cream.withValues(alpha: 0.15);
    if (total <= 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(inset, centerY - base / 2, inset + track,
                  centerY + base / 2),
              Radius.circular(base / 2)),
          inactive);
      return;
    }
    double x(Duration value) =>
        inset + (value.inMicroseconds / total).clamp(0.0, 1.0) * track;
    final buffered = Paint()..color = WfColors.cream.withValues(alpha: 0.35);
    final played = Paint()..color = WfColors.gold;
    final stripe = Paint()
      ..color = WfColors.bg.withValues(alpha: 0.55)
      ..strokeWidth = stripeWidth;
    final last = segments.length - 1;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final left = x(segment.start) + (i > 0 ? seekSegmentGap / 2 : 0);
      final right = x(segment.end) - (i < last ? seekSegmentGap / 2 : 0);
      if (right <= left) continue;
      final height = i == hoveredSegment
          ? lerpDouble(base, hoveredSegmentHeight, emphasis)!
          : base;
      final rect = Rect.fromLTRB(
          left, centerY - height / 2, right, centerY + height / 2);
      void fill(double end, Paint paint) {
        final clipped = math.min(right, end);
        if (clipped > left) {
          canvas.drawRect(
              Rect.fromLTRB(left, rect.top, clipped, rect.bottom), paint);
        }
      }

      canvas.save();
      canvas.clipRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(height / 2)));
      canvas.drawRect(rect, inactive);
      fill(x(buffer), buffered);
      fill(x(position), played);
      for (final zone in zones) {
        final zoneLeft = math.max(left, x(zone.start));
        final zoneRight = math.min(right, x(zone.end));
        if (zoneRight <= zoneLeft) continue;
        canvas.save();
        canvas.clipRect(
            Rect.fromLTRB(zoneLeft, rect.top, zoneRight, rect.bottom));
        // Righe diagonali: si parte abbastanza a sinistra da coprire tutta
        // l'altezza fin dal bordo della zona.
        for (var start = zoneLeft - rect.height;
            start < zoneRight;
            start += stripeSpacing) {
          canvas.drawLine(Offset(start, rect.bottom),
              Offset(start + rect.height, rect.top), stripe);
        }
        canvas.restore();
      }
      canvas.restore();
    }
    if (thumb > 0) {
      final center = Offset(x(position), centerY);
      canvas.drawCircle(
          center,
          (thumbRadius + thumbHalo) * thumb,
          Paint()
            ..color = WfColors.gold.withValues(alpha: 0.25 * thumbOpacity));
      canvas.drawCircle(center, thumbRadius * thumb,
          Paint()..color = WfColors.gold.withValues(alpha: thumbOpacity));
    }
  }

  @override
  bool shouldRepaint(SeekBarPainter oldDelegate) =>
      !listEquals(oldDelegate.segments, segments) ||
      !listEquals(oldDelegate.zones, zones) ||
      oldDelegate.duration != duration ||
      oldDelegate.position != position ||
      oldDelegate.buffer != buffer ||
      oldDelegate.hover != hover ||
      oldDelegate.hoveredSegment != hoveredSegment ||
      oldDelegate.emphasis != emphasis ||
      oldDelegate.thumb != thumb ||
      oldDelegate.thumbOpacity != thumbOpacity;
}

/// Barra di avanzamento (spec D §8): tratti per capitolo, zone rigate,
/// anteprima al passaggio del mouse e durante il trascinamento, salto con
/// clic o trascinamento.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.engine,
    required this.onSeek,
    this.chapters = const [],
    this.zones = const [],
    this.preview,
  });

  final VideoEngine engine;
  final ValueChanged<Duration> onSeek;
  final List<ChapterMark> chapters;

  /// Riassunto, intro e titoli di coda (`seekZones`).
  final List<SeekZone> zones;

  /// Immagine di anteprima per una posizione (trickplay); `null` = solo il
  /// tempo.
  final Widget? Function(Duration position)? preview;

  /// Margine orizzontale della traccia: il cursore (raggio 7) non esce dalla
  /// barra.
  static const trackInset = 8.0;

  /// Altezza dell'area che risponde a mouse e clic.
  static const height = 28.0;

  static const previewWidth = 240.0;

  /// Distanza dell'anteprima dalla barra.
  static const previewGap = 6.0;

  /// Scala da cui cresce l'anteprima (spec D §8.4).
  static const previewFromScale = 0.92;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> with TickerProviderStateMixin {
  late Duration _position;
  late Duration _duration;
  late Duration _buffer;
  final _subscriptions = <StreamSubscription<Duration>>[];

  /// Larghezza e tratti dell'ultimo layout.
  double _width = 0;
  List<SeekSegment> _segments = const [];

  /// Mouse sopra la barra e trascinamento in corso: posizione x.
  double? _hoverX;
  double? _dragX;

  /// Ultima posizione dell'anteprima: resta mentre sfuma via.
  double? _previewX;
  bool _previewShown = false;
  int? _hoveredSegment;

  /// Toglie l'anteprima dall'albero a dissolvenza finita. Un timer e non
  /// `onEnd`: se entrata e uscita cadono nello stesso frame la dissolvenza va
  /// da 0 a 0, non parte e `onEnd` non scatta mai.
  Timer? _previewTimer;

  late final AnimationController _hover =
      AnimationController(vsync: this, duration: WfMotion.fast);
  late final AnimationController _emphasis =
      AnimationController(vsync: this, duration: WfMotion.fast);
  late final AnimationController _thumb =
      AnimationController(vsync: this, duration: WfMotion.fast);

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
    _previewTimer?.cancel();
    _hover.dispose();
    _emphasis.dispose();
    _thumb.dispose();
    super.dispose();
  }

  double get _track => math.max(_width - 2 * SeekBar.trackInset, 1.0);

  Duration _positionAt(double x) {
    final fraction = ((x - SeekBar.trackInset) / _track).clamp(0.0, 1.0);
    return Duration(
        milliseconds: (fraction * _duration.inMilliseconds).round());
  }

  int? _segmentAt(double x) {
    final position = _positionAt(x);
    for (var i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      final last = i == _segments.length - 1;
      if (position >= segment.start &&
          (position < segment.end || (last && position <= segment.end))) {
        return i;
      }
    }
    return null;
  }

  /// Il puntatore è su [x] (passaggio del mouse o trascinamento).
  void _pointAt(double x) {
    // Il puntatore è tornato: l'anteprima non va più tolta.
    _previewTimer?.cancel();
    final index = _segmentAt(x);
    setState(() {
      _previewX = x;
      _previewShown = true;
      if (index != _hoveredSegment) {
        _hoveredSegment = index;
        _emphasis.forward(from: 0);
      }
    });
    _hover.forward();
    _thumb.forward();
  }

  /// Né mouse né trascinamento: la barra torna a riposo.
  void _release() {
    if (_hoverX != null || _dragX != null) return;
    setState(() {
      _previewShown = false;
      _hoveredSegment = null;
    });
    _previewTimer?.cancel();
    _previewTimer = Timer(WfMotion.fast, () {
      if (mounted && !_previewShown) setState(() => _previewX = null);
    });
    _hover.reverse();
    _thumb.reverse();
  }

  void _seekTo(double x) {
    // Senza durata ogni punto varrebbe zero: un salto a 0 sarebbe sbagliato
    // (e in una watch party lo vedrebbe tutto il gruppo).
    if (_duration <= Duration.zero) return;
    _seekToPosition(_positionAt(x));
  }

  void _seekToPosition(Duration target) {
    setState(() => _position = target);
    widget.onSeek(target);
  }

  /// [from] spostato di [delta], tenuto tra l'inizio e la durata.
  Duration _stepped(Duration from, Duration delta) {
    final target = from + delta;
    if (target < Duration.zero) return Duration.zero;
    return target > _duration ? _duration : target;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    return LayoutBuilder(builder: (context, constraints) {
      _width = constraints.maxWidth;
      _segments = seekSegments(widget.chapters, _duration, _track);
      final drag = _dragX;
      final shown = drag == null ? _position : _positionAt(drag);
      final previewX = _previewX;
      // Con la durata ancora ignota non si può avanzare né tornare indietro.
      final canStep = _duration > Duration.zero;
      return Semantics(
        slider: true,
        value: formatClock(shown),
        increasedValue:
            canStep ? formatClock(_stepped(shown, seekStep)) : null,
        decreasedValue:
            canStep ? formatClock(_stepped(shown, -seekStep)) : null,
        onIncrease:
            canStep ? () => _seekToPosition(_stepped(shown, seekStep)) : null,
        onDecrease:
            canStep ? () => _seekToPosition(_stepped(shown, -seekStep)) : null,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (event) {
            _hoverX = event.localPosition.dx;
            _pointAt(event.localPosition.dx);
          },
          onExit: (_) {
            _hoverX = null;
            _release();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Le azioni di tap e scroll del rilevatore cercherebbero un punto
            // senza un puntatore vero: lo slider usa solo increase/decrease.
            excludeFromSemantics: true,
            onTapUp: (details) => _seekTo(details.localPosition.dx),
            onHorizontalDragStart: (details) {
              _dragX = details.localPosition.dx;
              _pointAt(details.localPosition.dx);
            },
            onHorizontalDragUpdate: (details) {
              _dragX = details.localPosition.dx;
              _pointAt(details.localPosition.dx);
            },
            onHorizontalDragEnd: (_) {
              final x = _dragX;
              _dragX = null;
              if (x != null) _seekTo(x);
              _release();
            },
            onHorizontalDragCancel: () {
              _dragX = null;
              _release();
            },
            child: SizedBox(
              height: SeekBar.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_hover, _emphasis, _thumb]),
                        builder: (context, _) {
                          final reveal = _thumb.value;
                          return CustomPaint(
                            key: const Key('seek-bar-paint'),
                            painter: SeekBarPainter(
                              segments: _segments,
                              zones: widget.zones,
                              duration: _duration,
                              position: shown,
                              buffer: _buffer,
                              hover:
                                  WfMotion.emphasized.transform(_hover.value),
                              hoveredSegment: _hoveredSegment,
                              emphasis: WfMotion.emphasized
                                  .transform(_emphasis.value),
                              // Movimento pieno: il cursore cresce con un
                              // rimbalzo. Ridotto: resta a misura intera e
                              // sfuma soltanto (spec D §6.2).
                              thumb: reduced
                                  ? (reveal > 0 ? 1 : 0)
                                  : WfMotion.bounce.transform(reveal),
                              thumbOpacity: reduced ? reveal : 1,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (previewX != null && _duration > Duration.zero)
                    Positioned(
                      left: (previewX - SeekBar.previewWidth / 2).clamp(
                          0.0, math.max(_width - SeekBar.previewWidth, 0.0)),
                      bottom: SeekBar.height + SeekBar.previewGap,
                      width: SeekBar.previewWidth,
                      child: IgnorePointer(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: _previewShown ? 1 : 0),
                          duration: WfMotion.fast,
                          // Entra con l'enfatizzata, esce accelerando.
                          curve: _previewShown
                              ? WfMotion.emphasized
                              : WfMotion.accelerate,
                          builder: (context, t, child) => Opacity(
                            opacity: t.clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale: reduced
                                  ? 1
                                  : lerpDouble(SeekBar.previewFromScale, 1, t)!,
                              alignment: Alignment.bottomCenter,
                              child: child,
                            ),
                          ),
                          child: _SeekPreview(
                            position: _positionAt(previewX),
                            chapter:
                                chapterAt(widget.chapters, _positionAt(previewX)),
                            zone: zoneAt(widget.zones, _positionAt(previewX)),
                            image: widget.preview?.call(_positionAt(previewX)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _SeekPreview extends StatelessWidget {
  const _SeekPreview(
      {required this.position, this.chapter, this.zone, this.image});

  final Duration position;
  final ChapterMark? chapter;
  final SeekZone? zone;
  final Widget? image;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = chapter?.name;
    final picture = image;
    final kind = zone?.kind;
    final radius = BorderRadius.circular(6);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (picture != null)
          Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                    color: WfColors.bg.withValues(alpha: 0.8),
                    blurRadius: 20,
                    offset: const Offset(0, 8)),
              ],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                  color: WfColors.cream.withValues(alpha: 0.85), width: 1.5),
            ),
            child: ClipRRect(borderRadius: radius, child: picture),
          ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: WfColors.bg.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name == null
                      ? formatClock(position)
                      : '${formatClock(position)} · $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: WfColors.cream),
                ),
              ),
              if (kind != null) ...[
                const SizedBox(width: 6),
                Container(
                  key: const Key('seek-zone-tag'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: WfColors.gold,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    seekZoneLabel(l, kind),
                    style: const TextStyle(
                        color: WfColors.bg,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
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
