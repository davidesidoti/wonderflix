import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/config/app_config.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

final testAppConfig = AppConfig(
  serverUrl: Uri.parse('https://media.example.com'),
  githubRepo: 'owner/repo',
  discordAppId: '1',
  supportUrl: Uri.parse('https://discord.gg/abc'),
);

/// Monta [child] con tema, localizzazione italiana e provider di test.
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size surfaceSize = const Size(1440, 900),
  MotionLevel motion = MotionLevel.reduced,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(testAppConfig),
      // Nessun WebSocket reale nei widget test.
      serverEventsBindingProvider.overrideWithValue(null),
      // Nessuna immagine di rete nei widget test.
      imageBuilderProvider.overrideWithValue(
          (image, fit) => const ColoredBox(color: Color(0xFF333333))),
      ...overrides,
    ],
    retry: (_, _) => null,
    child: MaterialApp(
      theme: buildWonderflixTheme(),
      locale: const Locale('it'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          WfMotionScope(motion: WfMotion(motion), child: child!),
      home: child,
    ),
  ));
  await tester.pump();
}
