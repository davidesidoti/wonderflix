import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../features/auth/session_controller.dart';
import '../features/settings/appearance_settings.dart';
import '../features/settings/locale_controller.dart';
import '../features/update/update_gate.dart';
import '../features/watch_party/watch_party_routing.dart';
import '../l10n/gen/app_localizations.dart';
import 'motion.dart';
import 'router.dart';
import 'theme.dart';

class WonderflixApp extends ConsumerStatefulWidget {
  const WonderflixApp({super.key});

  @override
  ConsumerState<WonderflixApp> createState() => _WonderflixAppState();
}

class _WonderflixAppState extends ConsumerState<WonderflixApp> {
  late final _AnimationPreferenceRefresher _refresher;

  @override
  void initState() {
    super.initState();
    // Una sola volta all'avvio: riparte dai profili salvati (nessuno →
    // accesso, uno → lo apre, più di uno → "Chi guarda?").
    unawaited(ref.read(sessionControllerProvider.notifier).restore());
    _refresher = _AnimationPreferenceRefresher(
        () => ref.read(systemAnimationsProvider.notifier).refresh());
    windowManager.addListener(_refresher);
  }

  @override
  void dispose() {
    windowManager.removeListener(_refresher);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Il watch party apre il player quando il gruppo sceglie cosa guardare.
    ref.watch(watchPartyRoutingProvider);
    final motion = WfMotion(ref.watch(motionLevelProvider));
    return MaterialApp.router(
      title: 'WonderFlix',
      debugShowCheckedModeBanner: false,
      theme: buildWonderflixTheme(),
      locale: ref.watch(localeProvider),
      routerConfig: ref.watch(routerProvider),
      // Avvisi di aggiornamento sopra tutte le schermate.
      builder: (context, child) => WfMotionScope(
        motion: motion,
        child: UpdateGate(child: child ?? const SizedBox.shrink()),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // Italiano per primo: è la lingua di ripiego se Windows usa altre lingue.
      supportedLocales: const [Locale('it'), Locale('en')],
    );
  }
}

/// Rilegge "Effetti di animazione" quando la finestra torna in primo piano:
/// un cambio nelle impostazioni di Windows vale senza riavviare l'app.
class _AnimationPreferenceRefresher with WindowListener {
  _AnimationPreferenceRefresher(this._refresh);

  final VoidCallback _refresh;

  @override
  void onWindowFocus() => _refresh();
}
