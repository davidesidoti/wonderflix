import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/admin_models.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';

import '../../support/admin_json.dart';

void main() {
  group('sessioni', () {
    test('legge le sessioni e scarta quelle senza utente', () {
      final sessions = parseSessions(sessionsJson);

      expect(sessions.map((s) => s.id), ['s1', 's2', 's3']);

      final episode = sessions[0];
      expect(episode.userName, 'viviroby');
      expect(episode.client, 'Jellyfin Android TV');
      expect(episode.deviceName, 'FireTV Soggiorno');
      expect(episode.lastActivity, DateTime.parse('2026-10-06T07:53:20.858066Z'));
      expect(episode.position, const Duration(minutes: 12, seconds: 34));
      expect(episode.isPaused, isFalse);
      expect(episode.playMethod, PlayMethod.transcode);
      final playing = episode.nowPlaying!;
      expect(playing.kind, NowPlayingKind.episode);
      expect(playing.name, 'Pilota');
      expect(playing.seriesName, 'Lost');
      expect(playing.seasonNumber, 1);
      expect(playing.episodeNumber, 3);
      expect(playing.runtime, const Duration(minutes: 42, seconds: 36));
      expect(playing.imageItemId, 'ser1', reason: 'la locandina della serie');
      final transcode = episode.transcode!;
      expect(transcode.videoCodec, 'h264');
      expect(transcode.audioCodec, 'aac');
      expect(transcode.isVideoDirect, isFalse);
      expect(transcode.isAudioDirect, isFalse);
      expect(transcode.bitrate, 8200000);
      expect(transcode.height, 1080);
      expect(transcode.hardwareAcceleration, 'none');
      expect(transcode.reasons,
          ['VideoCodecNotSupported', 'AudioCodecNotSupported']);

      final movie = sessions[1];
      expect(movie.isPaused, isTrue);
      expect(movie.nowPlaying!.kind, NowPlayingKind.movie);
      expect(movie.nowPlaying!.year, 2021);
      expect(movie.nowPlaying!.imageItemId, 'm1');
      expect(movie.transcode!.isVideoDirect, isTrue);
      expect(movie.transcode!.isAudioDirect, isTrue);

      final idle = sessions[2];
      expect(idle.nowPlaying, isNull);
      expect(idle.transcode, isNull);
      expect(idle.position, Duration.zero);
      expect(idle.playMethod, PlayMethod.unknown);
    });

    test('voci strane: si saltano o restano senza i campi', () {
      final sessions = parseSessions([
        {'UserId': 'u1', 'UserName': 'senza id'},
        {'Id': 'x1', 'UserName': 'senza utente'},
        {'Id': 'x2', 'UserId': '00000000-0000-0000-0000-000000000000'},
        'non è un oggetto',
        {
          'Id': 'x3',
          'UserId': 'u3',
          'UserName': 'ok',
          'PlayState': 'strano',
          'NowPlayingItem': {'Id': 'i1'},
          'TranscodingInfo': {
            'TranscodeReasons': 'ContainerNotSupported, AudioIsExternal',
          },
          'LastActivityDate': 'ieri',
        },
      ]);

      expect(sessions.map((s) => s.id), ['x3']);
      final session = sessions.single;
      expect(session.nowPlaying, isNull, reason: 'senza nome non si mostra');
      expect(session.lastActivity, isNull);
      expect(session.transcode!.reasons,
          ['ContainerNotSupported', 'AudioIsExternal']);
    });

    test('un corpo che non è un elenco è un errore del server', () {
      expect(() => parseSessions({'Items': <Object>[]}),
          throwsA(isA<ServerErrorException>()));
    });

    test('id vuoti di Jellyfin', () {
      expect(isEmptyJellyfinId('00000000000000000000000000000000'), isTrue);
      expect(isEmptyJellyfinId('00000000-0000-0000-0000-000000000000'), isTrue);
      expect(isEmptyJellyfinId('ab8240c5fc1649e186f662fa00ca0fb0'), isFalse);
    });
  });

  test('watch party', () {
    final groups = parsePartyGroups([
      ...partyGroupsJson,
      {'GroupName': 'senza id'},
      {'GroupId': 'g2', 'State': 'Boh', 'Participants': 42},
    ]);

    expect(groups.map((g) => g.id), ['g1', 'g2']);
    expect(groups[0].name, 'Serata Lost');
    expect(groups[0].state, PartyState.playing);
    expect(groups[0].participants, ['viviroby', 'Mario']);
    expect(groups[1].name, '');
    expect(groups[1].state, PartyState.unknown);
    expect(groups[1].participants, isEmpty);
  });

  test('informazioni sul server', () {
    final info = ServerInfo.fromJson(serverInfoJson);
    expect(info.name, 'WonderFlix');
    expect(info.version, '10.11.9');
    expect(info.operatingSystem, isNull, reason: 'sul server è vuoto');
    expect(info.hasPendingRestart, isFalse);

    final pending = ServerInfo.fromJson({
      ...serverInfoJson,
      'OperatingSystemDisplayName': 'Linux',
      'HasPendingRestart': true,
    });
    expect(pending.operatingSystem, 'Linux');
    expect(pending.hasPendingRestart, isTrue);

    expect(() => ServerInfo.fromJson({'ServerName': 'x'}),
        throwsA(isA<ServerErrorException>()));
  });
}
