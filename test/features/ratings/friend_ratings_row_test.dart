import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/ratings/rate_panel.dart';
import 'package:wonderflix/core/social/rating_models.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/detail/detail_header.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/library/user_data.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/ratings/friend_ratings_row.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

FriendRating friend(String id, String name, int score, {String? comment}) =>
    FriendRating(
        userId: id,
        name: name,
        score: score,
        comment: comment,
        updatedAt: DateTime.utc(2026, 10, 1));

void main() {
  late FakeSocialApi api;
  late FakeLibraryApi library;
  const on = SocialFeatures(friends: true, ratings: true);

  setUp(() {
    api = FakeSocialApi()..install(features: const {});
    library = FakeLibraryApi();
  });

  Future<ItemRatings?> pumpRow(WidgetTester tester,
      {SocialFeatures features = on, JellyfinItem? item}) async {
    ItemRatings? rated;
    await pumpApp(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: FriendRatingsRow(
                    item: item ?? testItem(id: 'm1'),
                    onRate: (r) => rated = r))),
        overrides: socialTestOverrides(api, features: features));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    return rated;
  }

  testWidgets('senza la funzione nessuna riga e nessuna chiamata',
      (tester) async {
    api.itemRatingsById['m1'] =
        ItemRatings(canRate: true, count: 1, friends: [friend('u2', 'Luigi', 8)]);
    await pumpRow(tester, features: const SocialFeatures(friends: true));
    expect(find.byKey(const Key('friend-ratings-average')), findsNothing);
    expect(find.text('Voti degli amici'), findsNothing);
    expect(api.calls, isNot(contains('ratings m1')));
  });

  testWidgets('media, numero e card degli amici', (tester) async {
    final long = 'x' * 300;
    api.itemRatingsById['m1'] = ItemRatings(
      canRate: true,
      average: 7.7,
      count: 3,
      friends: [
        friend('u2', 'Luigi', 8, comment: long),
        friend('u3', 'Peach', 9),
        friend('u4', 'Toad', 6),
      ],
    );
    await pumpRow(tester);
    expect(find.text('Voti degli amici'), findsOneWidget);
    expect(find.text('7,7'), findsOneWidget);
    expect(find.text('3 amici'), findsOneWidget);
    for (final id in ['u2', 'u3', 'u4']) {
      expect(find.byKey(Key('friend-rating-$id')), findsOneWidget);
    }
    expect(find.text('Luigi'), findsOneWidget);
    expect(find.text('Toad'), findsOneWidget);
    final comment = tester.widget<Text>(find.text(long));
    expect(comment.maxLines, 3);
    expect(comment.overflow, TextOverflow.ellipsis);
    expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == long),
        findsOneWidget);
  });

  testWidgets('nessun voto ma si può votare', (tester) async {
    api.itemRatingsById['m1'] =
        const ItemRatings(canRate: true, count: 0, friends: []);
    ItemRatings? rated;
    await pumpApp(
        tester,
        Scaffold(
            body: FriendRatingsRow(
                item: testItem(id: 'm1'), onRate: (r) => rated = r)),
        overrides: socialTestOverrides(api, features: on));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(find.text('Ancora nessun voto degli amici'), findsOneWidget);
    expect(find.text('Vota'), findsOneWidget);
    await tester.tap(find.byKey(const Key('friend-ratings-action')));
    expect(rated, isNotNull);
    expect(rated!.canRate, isTrue);
  });

  testWidgets('il mio voto a destra', (tester) async {
    api.itemRatingsById['m1'] = ItemRatings(
        canRate: true,
        mine: const MyRating(score: 8),
        count: 1,
        average: 8,
        friends: [friend('u2', 'Luigi', 8)]);
    await pumpRow(tester);
    expect(find.text('Il tuo voto: 8'), findsOneWidget);
    expect(find.byIcon(LucideIcons.pencil), findsOneWidget);
  });

  testWidgets('senza canRate né mine niente azione', (tester) async {
    api.itemRatingsById['m1'] = ItemRatings(
        canRate: false,
        count: 1,
        average: 8,
        friends: [friend('u2', 'Luigi', 8)]);
    await pumpRow(tester);
    expect(find.byKey(const Key('friend-rating-u2')), findsOneWidget);
    expect(find.byKey(const Key('friend-ratings-action')), findsNothing);
  });

  testWidgets('niente amici e niente voto possibile: nessuna riga',
      (tester) async {
    api.itemRatingsById['m1'] =
        const ItemRatings(canRate: false, count: 0, friends: []);
    await pumpRow(tester);
    expect(find.text('Voti degli amici'), findsNothing);
    expect(api.calls, contains('ratings m1'));
  });

  testWidgets('errore: nessuna riga', (tester) async {
    api.nextFailure = SocialFailure.forbidden;
    await pumpRow(tester);
    expect(find.text('Voti degli amici'), findsNothing);
  });

  testWidgets('si rilegge quando cambia Visto', (tester) async {
    api.itemRatingsById['m1'] =
        const ItemRatings(canRate: true, count: 0, friends: []);
    await pumpRow(tester);
    expect(api.calls.where((c) => c == 'ratings m1'), hasLength(1));
    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('friend-ratings-action'))));
    container
        .read(userDataOverridesProvider.notifier)
        .apply('m1', const UserItemData(played: true));
    await tester.pump();
    await tester.pump();
    expect(api.calls.where((c) => c == 'ratings m1'), hasLength(2));
  });

  group('nella scheda', () {
    Future<void> pumpDetail(WidgetTester tester, String id) async {
      await pumpApp(
          tester, Scaffold(body: ItemDetailScreen(itemId: id)),
          overrides: [
            libraryApiProvider.overrideWithValue(library),
            ...socialTestOverrides(api, features: on),
          ]);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    final withFriend = ItemRatings(
        canRate: true, count: 1, average: 8, friends: [friend('u2', 'Luigi', 8)]);

    testWidgets('film: la riga sta tra la testata e il Cast', (tester) async {
      library.itemsById['m1'] = testItem(id: 'm1', people: [
        {'Id': 'p9', 'Name': 'Zendaya', 'Role': 'Chani', 'Type': 'Actor'},
      ]);
      api.itemRatingsById['m1'] = withFriend;
      await pumpDetail(tester, 'm1');
      final row = tester.getTopLeft(find.text('Voti degli amici')).dy;
      expect(row, greaterThan(tester.getTopLeft(find.byType(DetailHeader)).dy));
      expect(row, lessThan(tester.getTopLeft(find.text('Cast')).dy));
    });

    testWidgets('episodio aperto da solo: nessuna riga', (tester) async {
      library.itemsById['e1'] =
          testItem(id: 'e1', kind: ItemKind.episode, seriesId: 's1');
      api.itemRatingsById['e1'] = withFriend;
      await pumpDetail(tester, 'e1');
      expect(find.text('Voti degli amici'), findsNothing);
      expect(api.calls, isNot(contains('ratings e1')));
    });

    testWidgets('serie: la riga della stagione scelta, prima delle schede',
        (tester) async {
      library.itemsById['s1'] =
          testItem(id: 's1', name: 'The Last of Us', kind: ItemKind.series);
      library.seasonsBySeries['s1'] = [
        testItem(id: 'season1', name: 'Stagione 1', kind: ItemKind.season, index: 1),
        testItem(id: 'season2', name: 'Stagione 2', kind: ItemKind.season, index: 2),
      ];
      api.itemRatingsById['season1'] = withFriend;
      api.itemRatingsById['season2'] = withFriend;
      await pumpDetail(tester, 's1');
      expect(find.text('Voti degli amici · Stagione 1'), findsOneWidget);
      expect(api.calls, contains('ratings season1'));
      expect(
          tester.getTopLeft(find.text('Voti degli amici · Stagione 1')).dy,
          lessThan(tester.getTopLeft(find.text('Stagione 2')).dy));
      await tester.tap(find.text('Stagione 2'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Voti degli amici · Stagione 2'), findsOneWidget);
      expect(api.calls, contains('ratings season2'));
    });

    testWidgets('film: Vota apre il pannello sul film', (tester) async {
      library.itemsById['m1'] = testItem(id: 'm1', name: 'Dune');
      api.itemRatingsById['m1'] = withFriend;
      await pumpDetail(tester, 'm1');
      final container = ProviderScope.containerOf(
          tester.element(find.byType(ItemDetailScreen)));
      container.listen(shellPanelProvider, (_, _) {});
      await tester.tap(find.byKey(const Key('friend-ratings-action')));
      expect(container.read(shellPanelProvider), ShellPanel.rate);
      final subject = container.read(rateSubjectProvider)!;
      expect(subject.item.id, 'm1');
      expect(subject.title, 'Dune');
    });

    testWidgets('serie: il pannello è sulla stagione scelta', (tester) async {
      library.itemsById['s1'] =
          testItem(id: 's1', name: 'Breaking Bad', kind: ItemKind.series);
      library.seasonsBySeries['s1'] = [
        testItem(id: 'season1', name: 'Stagione 1', kind: ItemKind.season, index: 1),
      ];
      api.itemRatingsById['season1'] = withFriend;
      await pumpDetail(tester, 's1');
      final container = ProviderScope.containerOf(
          tester.element(find.byType(ItemDetailScreen)));
      container.listen(shellPanelProvider, (_, _) {});
      await tester.tap(find.byKey(const Key('friend-ratings-action')));
      final subject = container.read(rateSubjectProvider)!;
      expect(subject.item.id, 'season1');
      expect(subject.title, 'Breaking Bad · Stagione 1');
    });
  });

  test('la scheda ha nove elementi', () {
    expect(detailEntranceCount, 9);
  });
}
