import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/session_controller.dart';
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
    return MaterialApp.router(
      title: 'WonderFlix',
      debugShowCheckedModeBanner: false,
      theme: buildWonderflixTheme(),
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // Italiano per primo: è la lingua di ripiego se Windows usa altre lingue.
      supportedLocales: const [Locale('it'), Locale('en')],
    );
  }
}
