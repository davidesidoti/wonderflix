import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/rating_models.dart';
import 'package:wonderflix/features/admin/admin_time.dart';
import 'package:wonderflix/features/admin/rating_comments_card.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  late FakePluginAdminApi plugin;

  AdminComment comment(String userId, String name, String itemId, String title,
          int score, String text) =>
      AdminComment(
        userId: userId,
        userName: name,
        itemId: itemId,
        title: title,
        score: score,
        comment: text,
        updatedAt: clock.now().toUtc().subtract(const Duration(hours: 2)),
      );

  final luigi = comment('u2', 'Luigi', 'm1', 'Il Padrino (1972)', 9,
      'Un film che si rivede volentieri, anche la terza volta.');
  final anna = comment('u3', 'Anna', 'm2', 'Dune (2021)', 7, 'Bello ma lungo');

  setUp(() => plugin = FakePluginAdminApi());

  Future<void> pumpCard(WidgetTester tester,
      {SocialFeatures features =
          const SocialFeatures(ratings: true, known: true)}) async {
    await pumpApp(
        tester,
        const Scaffold(body: SingleChildScrollView(child: RatingCommentsCard())),
        overrides:
            adminTestOverrides(FakeAdminApi(), plugin: plugin, features: features),
        surfaceSize: const Size(1440, 1400));
    await tester.pumpAndSettle();
  }

  testWidgets('elenco: nome, titolo, voto, commento, data', (tester) async {
    plugin.commentPages = [
      AdminCommentsPage(items: [luigi, anna])
    ];
    await pumpCard(tester);
    expect(find.text(it.adminCommentsTitle), findsOneWidget);
    expect(find.text('Luigi'), findsOneWidget);
    expect(find.text('Il Padrino (1972)'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text(luigi.comment), findsOneWidget);
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text(adminTimeLabel(luigi.updatedAt, clock.now(), it)),
        findsNWidgets(2));
    expect(find.text(it.adminCommentsMore), findsNothing);
  });

  testWidgets('Altri finché c\'è Next', (tester) async {
    plugin.commentPages = [
      AdminCommentsPage(items: [luigi], next: 'cursore'),
      AdminCommentsPage(items: [anna]),
    ];
    await pumpCard(tester);
    expect(find.text('Anna'), findsNothing);
    await tester.tap(find.text(it.adminCommentsMore));
    await tester.pumpAndSettle();
    expect(plugin.calls, ['comments:-', 'comments:cursore']);
    expect(find.text('Luigi'), findsOneWidget);
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text(it.adminCommentsMore), findsNothing);
  });

  testWidgets('cancellare con conferma', (tester) async {
    plugin.commentPages = [
      AdminCommentsPage(items: [luigi, anna])
    ];
    await pumpCard(tester);
    await tester.tap(find.text(it.adminCommentDelete).first);
    await tester.pumpAndSettle();
    expect(find.text(it.adminCommentDeleteTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, it.adminCommentDelete));
    await tester.pumpAndSettle();
    expect(plugin.calls, contains('deleteComment:u2:m1'));
    expect(find.text('Luigi'), findsNothing);
    expect(find.text('Anna'), findsOneWidget);
  });

  testWidgets('Annulla: nessuna chiamata', (tester) async {
    plugin.commentPages = [
      AdminCommentsPage(items: [luigi])
    ];
    await pumpCard(tester);
    await tester.tap(find.text(it.adminCommentDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(it.adminCancel));
    await tester.pumpAndSettle();
    expect(plugin.calls.where((c) => c.startsWith('deleteComment')), isEmpty);
    expect(find.text('Luigi'), findsOneWidget);
  });

  testWidgets('cancellazione non riuscita: la voce resta e c\'è l\'errore',
      (tester) async {
    plugin.commentPages = [
      AdminCommentsPage(items: [luigi])
    ];
    plugin.actionError = const ServerErrorException(500);
    await pumpCard(tester);
    await tester.tap(find.text(it.adminCommentDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, it.adminCommentDelete));
    await tester.pumpAndSettle();
    expect(find.text('Luigi'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('senza la funzione: Serve il plugin 1.11.0 e nessuna chiamata',
      (tester) async {
    await pumpCard(tester, features: const SocialFeatures(known: true));
    expect(find.text(it.adminCommentsNeedPlugin), findsOneWidget);
    expect(plugin.calls, isEmpty);
  });

  testWidgets('nessun commento', (tester) async {
    await pumpCard(tester);
    expect(find.text(it.adminCommentsEmpty), findsOneWidget);
  });
}
