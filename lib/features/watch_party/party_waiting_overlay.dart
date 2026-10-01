import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/wf_buttons.dart';

/// Periodo della clessidra: ferma per il 70%, poi si gira (spec D §15.3).
const hourglassPeriod = Duration(milliseconds: 2400);

/// Periodo dei tre puntini che pulsano.
const waitingDotsPeriod = Duration(milliseconds: 1200);

/// Il gruppo aspetta qualcuno (buffering, ingresso di un membro). Compare
/// dopo [delay], per non lampeggiare nelle attese brevi (spec B §7.1), e
/// sfuma dentro e fuori (spec D §15.3). Sparita, non è nell'albero.
class PartyWaitingOverlay extends StatefulWidget {
  const PartyWaitingOverlay({
    super.key,
    required this.waiting,
    required this.onResume,
  });

  static const delay = Duration(seconds: 1);

  final bool waiting;

  /// "Riprendi senza aspettare".
  final VoidCallback onResume;

  @override
  State<PartyWaitingOverlay> createState() => _PartyWaitingOverlayState();
}

class _PartyWaitingOverlayState extends State<PartyWaitingOverlay> {
  Timer? _timer;
  bool _visible = false;

  /// Nell'albero: mostrata o mentre sfuma via.
  bool _present = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PartyWaitingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waiting != widget.waiting) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    _visible = false;
    if (!widget.waiting) return;
    _timer = Timer(PartyWaitingOverlay.delay, () {
      if (mounted) {
        setState(() {
          _visible = true;
          _present = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_present) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: _visible ? 1 : 0),
      duration: _visible ? motion.duration(WfMotion.medium) : WfMotion.fast,
      curve: WfMotion.standard,
      onEnd: () {
        if (!_visible && mounted) setState(() => _present = false);
      },
      builder: (context, t, child) => Opacity(
        key: const Key('party-waiting'),
        opacity: t.clamp(0.0, 1.0),
        child: child,
      ),
      child: IgnorePointer(
        ignoring: !_visible,
        child: ColoredBox(
          color: WfColors.bg.withValues(alpha: 0.6),
          child: Center(
            child: StaggerGroup(
              count: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const StaggerItem(index: 0, child: _Hourglass()),
                  const SizedBox(height: 16),
                  StaggerItem(
                    index: 1,
                    child: Text(l.watchPartyWaiting, style: WfText.display(28)),
                  ),
                  const SizedBox(height: 12),
                  const StaggerItem(index: 2, child: _WaitingDots()),
                  const SizedBox(height: 20),
                  StaggerItem(
                    index: 3,
                    child: WfButton.secondary(
                      label: l.watchPartyResumeNow,
                      icon: LucideIcons.play,
                      onPressed: widget.onResume,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clessidra oro che si gira ogni [hourglassPeriod] (ferma con le
/// animazioni ridotte).
class _Hourglass extends StatefulWidget {
  const _Hourglass();

  /// Parte del periodo in cui la clessidra sta ferma prima di girarsi.
  static const restFraction = 0.7;

  @override
  State<_Hourglass> createState() => _HourglassState();
}

class _HourglassState extends State<_Hourglass>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: hourglassPeriod);
  late final Animation<double> _turn = CurvedAnimation(
    parent: _controller,
    curve: const Interval(_Hourglass.restFraction, 1,
        curve: WfMotion.standard),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (WfMotion.of(context).isReduced) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _turn,
        builder: (context, child) => Transform.rotate(
          key: const Key('waiting-hourglass'),
          angle: _turn.value * math.pi,
          child: child,
        ),
        child: const Icon(LucideIcons.hourglass,
            size: 40, color: WfColors.gold),
      );
}

/// Tre puntini oro che pulsano uno dopo l'altro (fermi con le animazioni
/// ridotte).
class _WaitingDots extends StatefulWidget {
  const _WaitingDots();

  /// Opacità minima di un puntino.
  static const dimOpacity = 0.3;
  static const size = 8.0;

  @override
  State<_WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<_WaitingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: waitingDotsPeriod);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (WfMotion.of(context).isReduced) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Opacity(
                  opacity: _dotOpacity(i),
                  child: const SizedBox.square(
                    dimension: _WaitingDots.size,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: WfColors.gold, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  /// Ogni puntino è sfasato di un terzo di periodo.
  double _dotOpacity(int index) {
    if (!_controller.isAnimating) return _WaitingDots.dimOpacity;
    final phase = (_controller.value - index / 3) % 1;
    final wave = (math.sin(phase * 2 * math.pi) + 1) / 2;
    return _WaitingDots.dimOpacity + (1 - _WaitingDots.dimOpacity) * wave;
  }
}
