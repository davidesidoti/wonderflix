import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/reports/reports_api.dart';
import 'package:wonderflix/features/admin/admin_time.dart';
import 'package:wonderflix/features/admin/reports_card.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/report_fakes.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  late FakeReportsApi api;

  setUp(() => api = FakeReportsApi());

  List<Override> overrides(SocialFeatures features) => [
        ...adminTestOverrides(FakeAdminApi(), features: features),
        ...reportTestOverrides(reports: api),
      ];

  Future<void> pumpCard(
    WidgetTester tester, {
    SocialFeatures features =
        const SocialFeatures(reports: true, known: true),
  }) async {
    await pumpApp(
      tester,
      const Scaffold(body: SingleChildScrollView(child: ReportsCard())),
      overrides: overrides(features),
      surfaceSize: const Size(1440, 1400),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('elenco con titolo, livello, tipo, chi e quando', (tester) async {
    final report = testReport(
      createdAt: clock.now().toUtc().subtract(const Duration(hours: 2)),
    );
    api.reports.add(report);
    await pumpCard(tester);

    expect(find.text(it.adminReportsTitle), findsOneWidget);
    expect(find.text('Dark · S1 E2 · Sottotitoli'), findsOneWidget);
    expect(
      find.text('Luigi · ${adminTimeLabel(report.createdAt, clock.now(), it)}'),
      findsOneWidget,
    );
  });

  testWidgets('vuota', (tester) async {
    await pumpCard(tester);
    expect(find.text(it.adminReportsEmpty), findsOneWidget);
  });

  testWidgets('serve il plugin', (tester) async {
    api.reports.add(testReport());
    await pumpCard(tester, features: const SocialFeatures(known: true));
    expect(find.text(it.adminReportsNeedPlugin), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('errore: ritenta', (tester) async {
    api.nextFailure = ReportsFailure.network;
    await pumpCard(tester);
    expect(find.text(it.retry), findsOneWidget);
    await tester.tap(find.text(it.retry));
    await tester.pumpAndSettle();
    expect(find.text(it.adminReportsEmpty), findsOneWidget);
  });

  testWidgets('Apri porta al titolo', (tester) async {
    api.reports.add(testReport());
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: ReportsCard()),
      ),
      GoRoute(
        path: '/item/:id',
        builder: (_, state) => Text('scheda ${state.pathParameters['id']}'),
      ),
    ]);
    await pumpAppRouter(tester, router,
        overrides: overrides(const SocialFeatures(reports: true, known: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.text(it.adminReportsOpen));
    await tester.pumpAndSettle();
    // Una segnalazione su un episodio apre la serie.
    expect(find.text('scheda s1'), findsOneWidget);
  });
}
