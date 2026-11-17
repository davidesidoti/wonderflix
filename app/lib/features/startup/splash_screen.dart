import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../auth/profiles_state.dart';
import '../auth/session_controller.dart';

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

/// Dopo questo tempo lo splash dice quale profilo apre e lascia cambiarlo
/// (spec §9.3): `/Users/Me` può restare appeso.
const splashSlowAfter = Duration(seconds: 10);

/// Visibile mentre `SessionController.restore()` riparte dai profili salvati:
/// nessuno → l'accesso, uno → lo apre (`/Users/Me`), più di uno → "Chi
/// guarda?".
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// `null` con le animazioni ridotte: logo fermo.
  AnimationController? _intro;
  bool _decided = false;
  bool _slow = false;
  late final Timer _slowTimer;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(splashSlowAfter, () => setState(() => _slow = true));
  }

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
    _slowTimer.cancel();
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
    final book = ref.watch(profilesProvider).book;
    final l = AppLocalizations.of(context);
    final opening = book.byId(book.lastUserId ?? '') ??
        (book.profiles.length == 1 ? book.profiles.single : null);
    final name = opening?.name ?? '';
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
            if (_slow && !book.isEmpty) ...[
              const SizedBox(height: 24),
              Text(
                name.isEmpty ? l.splashOpeningUnnamed : l.splashOpening(name),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: WfColors.creamMuted, fontSize: 14),
              ),
              const SizedBox(height: 16),
              WfButton.secondary(
                label: l.profilesSwitch,
                icon: LucideIcons.users,
                // In TV nient'altro ha il focus.
                autofocus: true,
                onPressed: () => ref
                    .read(sessionControllerProvider.notifier)
                    .backToProfiles(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
