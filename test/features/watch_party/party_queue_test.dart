import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/watch_party/party_queue.dart';

import '../../support/library_fakes.dart';

void main() {
  late FakeLibraryApi library;

  JellyfinItem episode(String id, {String? seriesId = 's1'}) => testItem(
      id: id, name: 'Ep $id', kind: ItemKind.episode, seriesId: seriesId);

  setUp(() {
    library = FakeLibraryApi()
      ..seriesEpisodes['s1'] = [
        episode('e1'),
        episode('e2'),
        episode('e3'),
      ];
  });

  test('film: solo il film, senza richieste', () async {
    expect(await buildPartyQueue(library, 'u1', testItem(id: 'm1')), ['m1']);
    expect(library.episodesFromCalls, isEmpty);
  });

  test('episodio: lui e i successivi, al massimo 50', () async {
    expect(await buildPartyQueue(library, 'u1', episode('e2')), ['e2', 'e3']);
    final call = library.episodesFromCalls.single;
    expect(call.seriesId, 's1');
    expect(call.startItemId, 'e2');
    expect(call.limit, maxPartyQueue);
    expect(maxPartyQueue, 50);
  });

  test('episodio non restituito dal server: solo lui', () async {
    expect(await buildPartyQueue(library, 'u1', episode('e9')), ['e9']);
  });

  test('episodio senza serie: solo lui', () async {
    expect(
        await buildPartyQueue(library, 'u1', episode('e1', seriesId: null)),
        ['e1']);
    expect(library.episodesFromCalls, isEmpty);
  });

  test('errore del server: si propaga', () async {
    library.error = const ServerUnreachableException();
    expect(buildPartyQueue(library, 'u1', episode('e1')),
        throwsA(isA<ServerUnreachableException>()));
  });
}
