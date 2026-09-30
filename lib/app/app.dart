import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/session_controller.dart';
import '../features/settings/locale_controller.dart';
import '../features/update/update_gate.dart';
import '../features/watch_party/watch_party_routing.dart';
import '../l10n/gen/app_localizations.dart';
import 'router.dart';
import 'theme.dart';

class WonderflixApp extends ConsumerStatefulWidget {
  const WonderflixApp({super.key});

  @override
  ConsumerState<WonderflixApp> createState() => _WonderflixAppState();
}

class _WonderflixAppState extends ConsumerState<WonderflixApp> {
  @override
  void initState() {
    super.initState();
    // Una sola volta all'avvio: verifica il token salvato.
    unawaited(ref.read(sessionControllerProvider.notifier).restore());
  }

  @override
  Widget build(BuildContext context) {
    // Il watch party apre il player quando il gruppo sceglie cosa guardare.
    ref.watch(watchPartyRoutingProvider);
    return MaterialApp.router(
      title: 'WonderFlix',
      debugShowCheckedModeBanner: false,
      theme: buildWonderflixTheme(),
      locale: ref.watch(localeProvider),
      routerConfig: ref.watch(routerProvider),
      // Avvisi di aggiornamento sopra tutte le schermate.
      builder: (context, child) =>
          UpdateGate(child: child ?? const SizedBox.shrink()),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // Italiano per primo: è la lingua di ripiego se Windows usa altre lingue.
      supportedLocales: const [Locale('it'), Locale('en')],
    );
  }
}
