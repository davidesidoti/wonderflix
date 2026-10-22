import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeLibraryApi library;
  late FakeSocialApi api;

  setUp(() {
    library = FakeLibraryApi()
      ..itemsById['m1'] = testItem(id: 'm1', name: 'Dune: Parte Due');
    api = FakeSocialApi()..install(features: const {});
    api.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
  });

  Future<void> pumpDetail(WidgetTester tester, SocialFeatures features) async {
    await pumpApp(
        tester, const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
        overrides: [
          libraryApiProvider.overrideWithValue(library),
          ...socialTestOverrides(api, features: features),
        ]);
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('pulsante Consiglia a… su un film, con la funzione e un amico',
      (tester) async {
    await pumpDetail(
        tester, const SocialFeatures(friends: true, recommendations: true));
    expect(find.text('Consiglia a…'), findsOneWidget);
  });

  testWidgets('niente pulsante senza la funzione o senza amici', (tester) async {
    await pumpDetail(tester, const SocialFeatures(friends: true));
    expect(find.text('Consiglia a…'), findsNothing);
  });

  testWidgets('niente pulsante su un episodio', (tester) async {
    library.itemsById['m1'] =
        testItem(id: 'm1', kind: ItemKind.episode, seriesId: 's1');
    await pumpDetail(
        tester, const SocialFeatures(friends: true, recommendations: true));
    expect(find.text('Consiglia a…'), findsNothing);
  });
}
