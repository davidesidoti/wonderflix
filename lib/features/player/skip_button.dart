import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/playback_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import 'segments.dart';

/// "Salta intro" / "Salta riassunto" (spec D §13): entra da destra con un
/// piccolo rimbalzo, esce in fretta; una linea oro alla base si accorcia con
/// il tempo che manca alla fine del segmento.
class SkipSegmentButton extends StatefulWidget {
  const SkipSegmentButton({
    super.key,
    required this.engine,
    required this.segments,
    required this.onSkip,
  });

  final VideoEngine engine;
  final List<MediaSegment> segments;
  final VoidCallback onSkip;

  /// Di quanto arriva da destra entrando.
  static const enterShift = 40.0;

  /// Spessore della linea alla base.
  static const lineHeight = 3.0;

  /// Sotto questo cambio la linea non si ridisegna (meno ricostruzioni).
  static const lineEpsilon = 0.005;

  @override
  State<SkipSegmentButton> createState() => _SkipSegmentButtonState();
}

class _SkipSegmentButtonState extends State<SkipSegmentButton> {
  SkipTarget? _target;

  /// Parte del segmento che manca, 1 → 0.
  double _left = 0;
  StreamSubscription<Duration>? _subscription;

  @override
  void initState() {
    super.initState();
    _update(widget.engine.position, rebuild: false);
    _subscription = widget.engine.positionStream.listen(_update);
  }

  @override
  void didUpdateWidget(SkipSegmentButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // I segmenti arrivano dopo l'avvio.
    if (!identical(oldWidget.segments, widget.segments)) {
      _update(widget.engine.position, rebuild: false);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _update(Duration position, {bool rebuild = true}) {
    final target = skipTargetAt(widget.segments, position);
    var left = 0.0;
    if (target != null) {
      final length = target.end - target.segment.start;
      left = length <= Duration.zero
          ? 0
          : ((target.end - position).inMicroseconds / length.inMicroseconds)
              .clamp(0.0, 1.0);
    }
    final sameSegment = target?.segment.start == _target?.segment.start &&
        target?.kind == _target?.kind;
    if (sameSegment &&
        (left - _left).abs() < SkipSegmentButton.lineEpsilon) {
      return;
    }
    if (!rebuild) {
      _target = target;
      _left = left;
      return;
    }
    setState(() {
      _target = target;
      _left = left;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final target = _target;
    return AnimatedSwitcher(
      duration: motion.duration(WfMotion.medium),
      reverseDuration: WfMotion.fast,
      transitionBuilder: (child, animation) {
        // Il segnaposto vuoto (senza chiave) non si sposta: solo il pulsante.
        if (motion.isReduced || child.key == null) {
          return FadeTransition(opacity: animation, child: child);
        }
        final slide = animation.drive(CurveTween(curve: WfMotion.bounce));
        return FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: slide,
            builder: (context, child) => Transform.translate(
              key: const Key('skip-enter'),
              offset:
                  Offset((1 - slide.value) * SkipSegmentButton.enterShift, 0),
              child: child,
            ),
            child: child,
          ),
        );
      },
      child: target == null
          ? const SizedBox.shrink()
          : Stack(
              key: ValueKey(target.segment.start),
              children: [
                WfButton.secondary(
                  label: target.kind == SkipKind.intro
                      ? l.playerSkipIntro
                      : l.playerSkipRecap,
                  icon: LucideIcons.skipForward,
                  onPressed: widget.onSkip,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: SkipSegmentButton.lineHeight,
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(bottom: Radius.circular(6)),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          key: const Key('skip-line'),
                          widthFactor: _left,
                          heightFactor: 1,
                          child: const ColoredBox(color: WfColors.gold),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
