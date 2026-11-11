import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/navigation.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/trailers/trailers_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/playback/play_launcher.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;

  setUp(() => library = FakeLibraryApi());

  /// Pulsante "trailer" che chiama [playTrailer]; player e schermata del
  /// trailer mostrano l'indirizzo ricevuto.
  Future<void> pumpTrailer(WidgetTester tester, JellyfinItem item) async {
    await pumpAppRouter(
      tester,
      GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => playTrailer(context, ref, item),
                  child: const Text('trailer'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/play/:id',
            builder: (context, state) => Text('player ${state.uri}'),
          ),
          GoRoute(
            path: '/trailer/item/:id',
            builder: (context, state) => Text('schermata ${state.uri}'),
          ),
        ],
      ),
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(const SessionSignedIn(testUser)),
        ),
      ],
    );
    await tester.tap(find.text('trailer'));
    await tester.pumpAndSettle();
  }

  test('id YouTube come nel plugin', () {
    const id = '25WcssMq1VM';
    for (final url in [
      'https://www.youtube.com/watch?v=$id',
      'http://m.youtube.com/watch?feature=x&v=$id',
      'https://youtu.be/$id',
      'https://www.youtube-nocookie.com/embed/$id',
    ]) {
      expect(youTubeIdOf(url), id, reason: url);
    }
    for (final url in [
      'https://youtube.com/watch?v=x',
      'javascript:alert(1)',
      'https://vimeo.com/$id',
      'https://www.youtube.com/channel/$id',
    ]) {
      expect(youTubeIdOf(url), isNull, reason: url);
    }
  });

  testWidgets('localTrailerStillOpensThePlayer', (tester) async {
    library.localTrailerItems['m1'] = [
      testItem(id: 't1', kind: ItemKind.other),
    ];
    await pumpTrailer(
      tester,
      testItem(id: 'm1', localTrailers: 1, positionTicks: 23 * 60 * 10000000),
    );
    expect(find.text('player ${playerRoute('t1')}'), findsOneWidget);
  });

  testWidgets('remoteTrailerOpensTheTrailerScreen', (tester) async {
    await pumpTrailer(
      tester,
      testItem(
        id: 'm1',
        name: 'Dune',
        trailers: [
          {'Url': 'https://www.youtube.com/watch?v=25WcssMq1VM'},
        ],
      ),
    );
    expect(
      find.text(
        'schermata '
        '${trailerRoute(const LibraryTrailer('m1'), title: 'Dune', backdropItemId: 'm1')}',
      ),
      findsOneWidget,
    );
  });
}
