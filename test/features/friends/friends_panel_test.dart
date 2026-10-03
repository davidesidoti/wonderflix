import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/friends/friend_search.dart';
import 'package:wonderflix/features/friends/friends_panel.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeSocialApi api;

  setUp(() => api = FakeSocialApi());

  Future<void> pumpPanel(WidgetTester tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: FriendsPanel.width, child: FriendsPanel()),
        ),
      ),
      overrides: socialTestOverrides(api),
    );
    // Il primo caricamento parte da un microtask.
    await tester.pump();
  }

  testWidgets('amici: prima gli online, poi in ordine; pallino verde',
      (tester) async {
    api.snapshot = FriendsSnapshot(friends: [
      testFriend('u5', 'Zelda'),
      testFriend('u2', 'Luigi', online: true),
      testFriend('u4', 'daisy'),
    ]);
    await pumpPanel(tester);

    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(y('Luigi'), lessThan(y('daisy')));
    expect(y('daisy'), lessThan(y('Zelda')));
    expect(find.byKey(const Key('online-dot')), findsOneWidget);
    expect(find.text('AMICI'), findsOneWidget);
    expect(find.textContaining('RICHIESTE'), findsNothing);
  });

  testWidgets('nessun amico: invito a cercare', (tester) async {
    await pumpPanel(tester);
    expect(find.text('Nessun amico ancora. Cerca qualcuno per nome qui sopra.'),
        findsOneWidget);
  });

  testWidgets('richieste: accetta, rifiuta, annulla', (tester) async {
    api.snapshot = FriendsSnapshot(
      incoming: [testPerson('u3', 'Peach')],
      outgoing: [testPerson('u4', 'Daisy')],
    );
    await pumpPanel(tester);
    expect(find.text('RICHIESTE (2)'), findsOneWidget);
    expect(find.text('In attesa'), findsOneWidget);

    await tester.tap(find.text('Accetta'));
    await tester.pump();
    await tester.tap(find.text('Rifiuta'));
    await tester.pump();
    await tester.tap(find.text('Annulla'));
    await tester.pump();

    expect(api.calls.where((call) => call != 'friends'),
        ['accept u3', 'decline u3', 'cancel u4']);
  });

  testWidgets('ricerca: l\'azione giusta per ogni risultato, poi rilegge',
      (tester) async {
    api.searchResults['lu'] = [
      testSearchResult('u2', 'Luigi'),
      testSearchResult('u6', 'Lucia', FriendRelation.outgoing),
      testSearchResult('u7', 'Ludovico', FriendRelation.incoming),
      testSearchResult('u8', 'Lucky', FriendRelation.friend),
    ];
    await pumpPanel(tester);

    await tester.enterText(find.byKey(const Key('friends-search')), 'lu');
    await tester.pump(FriendSearch.debounce);
    await tester.pump();

    Finder inRow(String userId, String text) => find.descendant(
        of: find.byKey(ValueKey('search-$userId')), matching: find.text(text));
    expect(inRow('u2', 'Aggiungi'), findsOneWidget);
    expect(inRow('u6', 'Inviata'), findsOneWidget);
    expect(inRow('u6', 'Annulla'), findsOneWidget);
    expect(inRow('u7', 'Accetta'), findsOneWidget);
    expect(inRow('u8', 'Amici'), findsOneWidget);
    expect(find.text('AMICI'), findsNothing, reason: 'liste nascoste');

    await tester.tap(inRow('u2', 'Aggiungi'));
    await tester.pump();
    await tester.pump();
    expect(api.calls, containsAllInOrder(['search lu', 'request u2', 'search lu']));
  });

  testWidgets('ricerca senza risultati', (tester) async {
    await pumpPanel(tester);
    await tester.enterText(find.byKey(const Key('friends-search')), 'zz');
    await tester.pump(FriendSearch.debounce);
    await tester.pump();
    expect(find.text('Nessun utente trovato'), findsOneWidget);
  });

  testWidgets('rimozione: conferma per 4 s', (tester) async {
    api.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    await pumpPanel(tester);

    Future<void> askRemoval() async {
      await tester.tap(find.byTooltip('Altre azioni'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rimuovi dagli amici'));
      await tester.pumpAndSettle();
    }

    await askRemoval();
    expect(find.byKey(const Key('friend-remove-confirm')), findsOneWidget);
    await tester.pump(FriendsPanel.removeConfirmFor);
    expect(find.byKey(const Key('friend-remove-confirm')), findsNothing);
    expect(api.calls, isNot(contains('remove u2')));

    await askRemoval();
    await tester.tap(find.byKey(const Key('friend-remove-confirm')));
    await tester.pump();
    expect(api.calls, contains('remove u2'));
  });

  testWidgets('caricamento fallito: Riprova', (tester) async {
    api.nextFailure = SocialFailure.network;
    await pumpPanel(tester);
    await tester.pump();
    expect(find.text('Amici non disponibili'), findsOneWidget);

    api.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Luigi'), findsOneWidget);
  });

  testWidgets('azione rifiutata: lo dice', (tester) async {
    api.snapshot = FriendsSnapshot(incoming: [testPerson('u3', 'Peach')]);
    await pumpPanel(tester);
    api.nextFailure = SocialFailure.rateLimited;
    await tester.tap(find.text('Accetta'));
    await tester.pumpAndSettle();
    expect(find.text('Troppe richieste, riprova più tardi'), findsOneWidget);
  });
}
