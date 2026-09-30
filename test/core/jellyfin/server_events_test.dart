import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';

class FakeSocket implements EventSocket {
  final controller = StreamController<dynamic>();
  final sent = <String>[];
  bool closed = false;

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  void send(String message) => sent.add(message);

  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }
}

void main() {
  test('parseServerMessage', () {
    final changed = parseServerMessage(jsonEncode({
      'MessageType': 'UserDataChanged',
      'Data': {
        'UserId': 'u1',
        'UserDataList': [
          {'ItemId': 'm1', 'Played': true, 'IsFavorite': false},
        ],
      },
    }));
    expect(changed, isA<UserDataChanged>());
    expect((changed as UserDataChanged).changes['m1']?.played, isTrue);
    expect(changed.userId, 'u1');

    expect(parseServerMessage('{"MessageType":"LibraryChanged","Data":{}}'),
        isA<LibraryChanged>());
    expect(
        (parseServerMessage('{"MessageType":"ForceKeepAlive","Data":60}')
                as ForceKeepAlive)
            .seconds,
        60);
    expect(parseServerMessage('{"MessageType":"Sessions"}'), isNull);
    expect(parseServerMessage('non json'), isNull);
    expect(parseServerMessage(42), isNull);
  });

  test('parseServerMessage: messaggi SyncPlay', () {
    final command = parseServerMessage(jsonEncode({
      'MessageType': 'SyncPlayCommand',
      'Data': {
        'GroupId': 'g1',
        'PlaylistItemId': 'p1',
        'When': '2026-09-30T10:00:01Z',
        'PositionTicks': 0,
        'Command': 'Pause',
        'EmittedAt': '2026-09-30T10:00:00Z',
      },
    }));
    expect(command, isA<SyncPlayCommandReceived>());
    expect((command as SyncPlayCommandReceived).command.type,
        SyncPlayCommandType.pause);

    final update = parseServerMessage(jsonEncode({
      'MessageType': 'SyncPlayGroupUpdate',
      'Data': {'GroupId': 'g1', 'Type': 'UserJoined', 'Data': 'Luigi'},
    }));
    expect(update, isA<SyncPlayGroupUpdated>());
    expect(((update as SyncPlayGroupUpdated).update as UserJoined).userName,
        'Luigi');

    expect(
        parseServerMessage(jsonEncode({
          'MessageType': 'SyncPlayCommand',
          'Data': {'Command': 'Boh'},
        })),
        isNull);
    expect(
        parseServerMessage(jsonEncode({
          'MessageType': 'SyncPlayGroupUpdate',
          'Data': {'GroupId': 'g1', 'Type': 'Boh'},
        })),
        isNull);
  });

  test('socketUri', () {
    expect(socketUri(Uri.parse('https://media.example.com/jf')).toString(),
        'wss://media.example.com/jf/socket');
  });

  test('connessione, eventi, keep-alive e riconnessione', () {
    fakeAsync((async) {
      final sockets = <FakeSocket>[];
      final requests = <(Uri, Map<String, String>)>[];
      final client = ServerEventsClient(
        serverUrl: Uri.parse('https://media.example.com/jf'),
        authorizationHeader: () => 'MediaBrowser Token="tok"',
        connector: (uri, headers) async {
          requests.add((uri, headers));
          final socket = FakeSocket();
          sockets.add(socket);
          return socket;
        },
      );
      final events = <ServerEvent>[];
      client.events.listen(events.add);

      client.start();
      async.flushMicrotasks();
      expect(events.whereType<ServerConnected>().single.isReconnect, isFalse);
      expect(requests.single.$1.toString(), 'wss://media.example.com/jf/socket');
      expect(requests.single.$2['Authorization'], 'MediaBrowser Token="tok"');

      sockets.single.controller
          .add('{"MessageType":"ForceKeepAlive","Data":60}');
      async.flushMicrotasks();
      expect(sockets.single.sent.single, contains('KeepAlive'));
      async.elapse(const Duration(seconds: 30));
      expect(sockets.single.sent.length, 2);

      sockets.single.controller
          .add('{"MessageType":"LibraryChanged","Data":{}}');
      async.flushMicrotasks();
      expect(events.whereType<LibraryChanged>(), hasLength(1));

      // Il server chiude: nuovo tentativo dopo 2 s.
      unawaited(sockets.single.controller.close());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      expect(requests, hasLength(2));
      expect(events.whereType<ServerConnected>().map((e) => e.isReconnect),
          [false, true]);

      unawaited(client.stop());
      async.flushMicrotasks();
      expect(sockets.last.closed, isTrue);
      async.elapse(const Duration(minutes: 5));
      expect(requests, hasLength(2), reason: 'dopo stop niente riconnessioni');
    });
  });

  test('stop e start mentre la prima connessione è in corso: socket scartato',
      () {
    fakeAsync((async) {
      final pending = <Completer<EventSocket>>[];
      final client = ServerEventsClient(
        serverUrl: Uri.parse('https://media.example.com'),
        authorizationHeader: () => 'x',
        connector: (uri, headers) {
          final completer = Completer<EventSocket>();
          pending.add(completer);
          return completer.future;
        },
      );
      final events = <ServerEvent>[];
      client.events.listen(events.add);

      client.start();
      async.flushMicrotasks();
      unawaited(client.stop());
      client.start();
      async.flushMicrotasks();
      expect(pending, hasLength(2));

      final stale = FakeSocket();
      pending[0].complete(stale);
      async.flushMicrotasks();
      expect(stale.closed, isTrue);
      expect(events, isEmpty, reason: 'il socket vecchio non viene usato');

      final fresh = FakeSocket();
      pending[1].complete(fresh);
      async.flushMicrotasks();
      expect(fresh.closed, isFalse);
      fresh.controller.add('{"MessageType":"LibraryChanged","Data":{}}');
      async.flushMicrotasks();
      expect(events.whereType<LibraryChanged>(), hasLength(1));
      expect(events.whereType<ServerConnected>(), hasLength(1));

      unawaited(client.stop());
      async.flushMicrotasks();
    });
  });

  test('connessione fallita: riprova con attese crescenti', () {
    fakeAsync((async) {
      var attempts = 0;
      final client = ServerEventsClient(
        serverUrl: Uri.parse('https://media.example.com'),
        authorizationHeader: () => 'x',
        connector: (uri, headers) async {
          attempts++;
          throw StateError('down');
        },
      );
      client.start();
      async.flushMicrotasks();
      expect(attempts, 1);
      async.elapse(const Duration(seconds: 2));
      expect(attempts, 2);
      async.elapse(const Duration(seconds: 5));
      expect(attempts, 3);
      unawaited(client.stop());
      async.flushMicrotasks();
    });
  });
}
