import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/discord/discord_ipc.dart';

import '../../support/discord_fakes.dart';

void main() {
  group('frame', () {
    test('intestazione little-endian con opcode e lunghezza', () {
      final bytes = encodeDiscordFrame(DiscordOpcode.frame, {'a': 1});
      final header = ByteData.sublistView(bytes, 0, 8);
      expect(header.getUint32(0, Endian.little), 1);
      expect(header.getUint32(4, Endian.little), utf8.encode('{"a":1}').length);
      expect(utf8.decode(bytes.sublist(8)), '{"a":1}');
    });

    test('il lettore ricompone frame arrivati a pezzi', () {
      final bytes = [
        ...encodeDiscordFrame(DiscordOpcode.frame, {'evt': 'READY'}),
        ...encodeDiscordFrame(DiscordOpcode.ping, {'n': 2}),
      ];
      final reader = DiscordFrameReader();
      reader.add(bytes.sublist(0, 5));
      expect(reader.takeFrames(), isEmpty);
      reader.add(bytes.sublist(5));
      final frames = reader.takeFrames();
      expect(frames.map((f) => f.opcode),
          [DiscordOpcode.frame, DiscordOpcode.ping]);
      expect(frames.first.json, {'evt': 'READY'});
      expect(reader.takeFrames(), isEmpty);
    });

    test('opcode sconosciuti e JSON non valido vengono saltati', () {
      final bad = Uint8List(8 + 3);
      ByteData.sublistView(bad)
        ..setUint32(0, 1, Endian.little)
        ..setUint32(4, 3, Endian.little);
      bad.setAll(8, utf8.encode('{{{'));
      final unknown = Uint8List.fromList(
          encodeDiscordFrame(DiscordOpcode.frame, {'x': 1}));
      ByteData.sublistView(unknown).setUint32(0, 9, Endian.little);
      final reader = DiscordFrameReader()
        ..add(bad)
        ..add(unknown)
        ..add(encodeDiscordFrame(DiscordOpcode.frame, {'ok': true}));
      expect(reader.takeFrames().single.json, {'ok': true});
    });
  });

  group('client', () {
    late FakeDiscordPipe pipe;
    late DiscordIpcClient client;

    setUp(() {
      pipe = FakeDiscordPipe();
      client = DiscordIpcClient(pipe,
          clientId: '123',
          pollInterval: const Duration(milliseconds: 1),
          readyTimeout: const Duration(milliseconds: 30));
    });

    test('handshake con client_id e attesa di READY', () async {
      expect(await client.connect(), isTrue);
      expect(client.connected, isTrue);
      expect(pipe.handshakes, [
        {'v': 1, 'client_id': '123'},
      ]);
    });

    test('Discord chiuso: nessuna connessione, nessuna scrittura', () async {
      pipe.available = false;
      expect(await client.connect(), isFalse);
      expect(client.connected, isFalse);
      expect(pipe.written, isEmpty);
    });

    test('ID rifiutato da Discord: chiude la pipe', () async {
      pipe.handshakeReply = (
        opcode: DiscordOpcode.close,
        json: {'code': 4000, 'message': 'Invalid Client ID'},
      );
      expect(await client.connect(), isFalse);
      expect(pipe.closed, isTrue);
    });

    test('nessuna risposta: rinuncia dopo readyTimeout', () async {
      pipe.handshakeReply = null;
      expect(await client.connect(), isFalse);
      expect(pipe.closed, isTrue);
    });

    test('SET_ACTIVITY con pid e nonce diversi; null cancella', () async {
      await client.connect();
      expect(client.setActivity({'type': 3}, pid: 42), isTrue);
      expect(client.setActivity(null, pid: 42), isTrue);
      final commands = pipe.commands;
      expect(commands[0]['cmd'], 'SET_ACTIVITY');
      expect(commands[0]['args'], {
        'pid': 42,
        'activity': {'type': 3},
      });
      expect(commands[1]['args'], {'pid': 42});
      expect(commands[0]['nonce'], isNot(commands[1]['nonce']));
    });

    test('risponde ai ping con un pong', () async {
      await client.connect();
      pipe.push(DiscordOpcode.ping, {'n': 7});
      client.setActivity(null, pid: 1);
      final pong = pipe.written
          .firstWhere((frame) => frame.opcode == DiscordOpcode.pong);
      expect(pong.json, {'n': 7});
    });

    test('Discord chiude la connessione: setActivity restituisce false',
        () async {
      await client.connect();
      pipe.push(DiscordOpcode.close, {'code': 1000});
      expect(client.setActivity({'type': 3}, pid: 1), isFalse);
      expect(client.connected, isFalse);
    });

    test('pipe interrotta: setActivity restituisce false', () async {
      await client.connect();
      pipe.broken = true;
      expect(client.setActivity({'type': 3}, pid: 1), isFalse);
      expect(client.connected, isFalse);
      expect(pipe.closed, isTrue);
    });
  });
}
