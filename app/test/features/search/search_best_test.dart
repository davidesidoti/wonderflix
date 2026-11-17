import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/search/search_best.dart';
import 'package:wonderflix/features/search/search_controller.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/l10n/gen/app_localizations_it.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  final AppLocalizations it = AppLocalizationsIt();
  final istituto = testItem(
    id: 's1',
    name: "L'Istituto",
    kind: ItemKind.series,
    year: 2025,
    childCount: 2,
    genres: ['Thriller'],
    rating: 7.5,
    overview:
        'Un ragazzo prodigio viene rapito e portato in un istituto '
            'segreto dove altri bambini come lui vengono studiati. ' *
        4,
  );
  final nolan = testItem(
    id: 'p2',
    name: 'Christopher Nolan',
    kind: ItemKind.person,
  );
  final nolanFacts = PersonFacts(
    knownFor: testItem(id: 'm9', name: 'Il cavaliere oscuro'),
    titles: 10,
    roleType: 'Director',
  );

  RichText richNamed(WidgetTester tester, String name) =>
      tester.widget<RichText>(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == name,
        ),
      );

  testWidgets(
    'la carta: etichetta, nome sottolineato, dati, trama, due pulsanti',
    (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: SearchBestCard(item: istituto, term: 'ist', onOpened: () {}),
        ),
      );

      expect(find.text('Miglior risultato'), findsOneWidget);
      final rich = richNamed(tester, "L'Istituto");
      final underlined = <String>[];
      rich.text.visitChildren((span) {
        if (span is TextSpan &&
            span.style?.decoration == TextDecoration.underline &&
            span.style?.decorationColor == WfColors.gold) {
          underlined.add(span.text!);
        }
        return true;
      });
      expect(underlined, ['Ist']);
      expect(
        find.textContaining('Serie · 2025 · 2 stagioni · Thriller'),
        findsOneWidget,
      );
      expect(find.textContaining('7,5'), findsOneWidget);
      final overview = tester.widget<Text>(find.textContaining('prodigio'));
      expect(overview.maxLines, 2);
      expect(find.text('Riproduci'), findsOneWidget);
      expect(find.text('Scheda'), findsOneWidget);
    },
  );

  testWidgets('una persona: solo Scheda, coi dati', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: SearchBestCard(
          item: nolan,
          term: 'nol',
          facts: nolanFacts,
          onOpened: () {},
        ),
      ),
    );

    expect(find.text('Miglior risultato'), findsOneWidget);
    expect(
      find.text('Regia · Il cavaliere oscuro · 10 titoli'),
      findsOneWidget,
    );
    expect(find.text('Scheda'), findsOneWidget);
    expect(find.text('Riproduci'), findsNothing);
  });

  testWidgets(
    'le persone: ruolo, titolo noto, numero; Vedi tutte se sono di più',
    (tester) async {
      final people = [
        for (var i = 1; i <= 6; i++)
          i == 2
              ? nolan
              : testItem(id: 'p$i', name: 'Persona $i', kind: ItemKind.person),
      ];
      await pumpApp(
        tester,
        Scaffold(
          body: SearchPeopleList(
            people: people,
            facts: {'p2': nolanFacts},
            term: 'nol',
            total: 459,
            onSeeAll: () {},
            onOpened: () {},
          ),
        ),
      );

      expect(find.text('Persone'), findsOneWidget);
      expect(find.text('459'), findsOneWidget);
      expect(find.text('10 titoli'), findsOneWidget);
      expect(find.textContaining('Regia'), findsOneWidget);
      expect(find.textContaining('Il cavaliere oscuro'), findsOneWidget);
      expect(find.text('Vedi tutte'), findsOneWidget);
    },
  );

  testWidgets('senza onSeeAll niente Vedi tutte; righe alla stessa altezza', (
    tester,
  ) async {
    final people = [
      nolan,
      testItem(id: 'p3', name: 'Nolan North', kind: ItemKind.person),
    ];
    await pumpApp(
      tester,
      Scaffold(
        body: SearchPeopleList(
          people: people,
          facts: {'p2': nolanFacts},
          term: 'nol',
          total: 2,
          onOpened: () {},
        ),
      ),
    );

    expect(find.text('Vedi tutte'), findsNothing);
    final withFacts = tester.getSize(find.byKey(const ValueKey('person-p2')));
    final without = tester.getSize(find.byKey(const ValueKey('person-p3')));
    expect(without.height, withFacts.height);
  });

  testWidgets('la tessera della persona: nome e titoli', (tester) async {
    var opened = 0;
    await pumpApp(
      tester,
      Scaffold(
        body: SearchPersonTile(
          person: nolan,
          facts: nolanFacts,
          term: 'nol',
          onOpened: () => opened++,
        ),
      ),
    );
    expect(richNamed(tester, 'Christopher Nolan'), isNotNull);
    expect(find.text('10 titoli'), findsOneWidget);
  });

  testWidgets('aprire dalla carta chiama onOpened', (tester) async {
    var opened = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SearchBestCard(
              item: istituto,
              term: 'ist',
              onOpened: () => opened++,
            ),
          ),
        ),
        GoRoute(
          path: '/item/:id',
          builder: (context, state) =>
              Scaffold(body: Text('scheda ${state.pathParameters['id']}')),
        ),
      ],
    );
    await pumpAppRouter(tester, router);
    await tester.pump();
    await tester.tap(find.text('Scheda'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('scheda s1'), findsOneWidget);
  });

  test('ruoli senza genere', () {
    expect(personRoleLabel(it, 'Actor'), 'Interprete');
    expect(personRoleLabel(it, 'GuestStar'), 'Interprete');
    expect(personRoleLabel(it, 'Director'), 'Regia');
    expect(personRoleLabel(it, 'Writer'), 'Sceneggiatura');
    expect(personRoleLabel(it, 'Producer'), 'Produzione');
    expect(personRoleLabel(it, 'Composer'), 'Musica');
    expect(personRoleLabel(it, 'Lighting'), isNull);
    expect(personRoleLabel(it, null), isNull);
  });
}
