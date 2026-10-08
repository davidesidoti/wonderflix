import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';

/// Entrata del logo dello splash: comparsa e un solo riflesso oro (spec C
/// §11.3). Non allunga l'avvio: se la sessione è pronta prima, si va avanti.
const splashIntroDuration = Duration(milliseconds: 1200);

/// Parti dell'entrata, in frazioni di [splashIntroDuration]: comparsa,
/// crescita da 0,9 a 1, passaggio del riflesso.
const _fadeIn = Interval(0, 0.35, curve: WfMotion.standard);
const _grow = Interval(0, 0.5, curve: WfMotion.emphasized);
const _sheenPass = Interval(0.45, 1, curve: WfMotion.standard);

/// Larghezza della fascia del riflesso, in frazione della larghezza del logo.
const _sheenWidth = 0.35;

/// Visibile mentre `SessionController.restore()` riparte dai profili salvati:
/// nessuno → l'accesso, uno → lo apre (`/Users/Me`), più di uno → "Chi
/// guarda?".
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// `null` con le animazioni ridotte: logo fermo.
  AnimationController? _intro;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Si decide una volta sola, alla prima costruzione.
    if (_decided) return;
    _decided = true;
    if (WfMotion.of(context).isReduced) return;
    final intro =
        AnimationController(vsync: this, duration: splashIntroDuration);
    _intro = intro;
    unawaited(intro.forward());
  }

  @override
  void dispose() {
    _intro?.dispose();
    super.dispose();
  }

  /// Fascia oro che attraversa il logo da sinistra a destra: al centro in
  /// [center] (frazione della larghezza); fuori dalla fascia trasparente.
  static Shader _sheen(double center, Rect bounds) {
    // Da -1 a 1 come `Alignment`.
    double x(double fraction) => fraction * 2 - 1;
    return LinearGradient(
      begin: Alignment(x(center - _sheenWidth / 2), 0),
      end: Alignment(x(center + _sheenWidth / 2), 0),
      colors: [
        WfColors.gold.withValues(alpha: 0),
        WfColors.gold.withValues(alpha: 0.6),
        WfColors.gold.withValues(alpha: 0),
      ],
    ).createShader(bounds);
  }

  @override
  Widget build(BuildContext context) {
    Widget logo = Image.asset('assets/brand/logo.png',
        key: const Key('splash-logo'), width: 220);
    final intro = _intro;
    if (intro != null) {
      logo = AnimatedBuilder(
        animation: intro,
        child: logo,
        builder: (context, child) {
          final t = intro.value;
          // La fascia parte tutta a sinistra del logo ed esce tutta a destra.
          final center = -_sheenWidth / 2 +
              (1 + _sheenWidth) * _sheenPass.transform(t);
          return Opacity(
            opacity: _fadeIn.transform(t),
            child: Transform.scale(
              scale: 0.9 + 0.1 * _grow.transform(t),
              child: ShaderMask(
                key: const Key('splash-sheen'),
                blendMode: BlendMode.srcATop,
                shaderCallback: (bounds) => _sheen(center, bounds),
                child: child,
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            const SizedBox(height: 32),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
