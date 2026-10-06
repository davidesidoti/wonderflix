import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/admin_models.dart';
import 'package:wonderflix/features/admin/session_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));

  group('metodo mostrato', () {
    SessionEntry session(PlayMethod method, [TranscodeInfo? transcode]) =>
        testSession('s', 'mario',
            playing: testMovie, playMethod: method, transcode: transcode);

    test('regole della spec J §9.3 (decisione 7 del piano)', () {
      const both = TranscodeInfo(isVideoDirect: true, isAudioDirect: true);
      const audio = TranscodeInfo(isVideoDirect: true);
      const video = TranscodeInfo(isAudioDirect: true);

      expect(displayMethod(session(PlayMethod.directPlay)), DisplayMethod.direct);
      expect(displayMethod(session(PlayMethod.directPlay, video)),
          DisplayMethod.direct);
      expect(displayMethod(session(PlayMethod.transcode, both)),
          DisplayMethod.remux, reason: 'remux dichiarato Transcode');
      expect(displayMethod(session(PlayMethod.directStream, audio)),
          DisplayMethod.transcode, reason: 'l\'audio si transcodifica');
      expect(displayMethod(session(PlayMethod.transcode, video)),
          DisplayMethod.transcode);
      expect(displayMethod(session(PlayMethod.directStream)), DisplayMethod.remux);
      expect(displayMethod(session(PlayMethod.transcode)),
          DisplayMethod.transcode);
      expect(displayMethod(session(PlayMethod.unknown)), DisplayMethod.unknown);

      expect(displayMethodLabel(it, DisplayMethod.direct), 'Diretta');
      expect(displayMethodLabel(it, DisplayMethod.remux), 'Remux');
      expect(displayMethodLabel(it, DisplayMethod.transcode), 'Transcodifica');
      expect(displayMethodLabel(it, DisplayMethod.unknown), isNull);
    });
  });

  test('titolo di quel che si guarda', () {
    expect(nowPlayingTitle(it, testMovie), 'Dune (2021)');
    expect(
        nowPlayingTitle(
            it, const NowPlaying(itemId: 'm', name: 'Senza anno', kind: NowPlayingKind.movie)),
        'Senza anno');
    const episode = NowPlaying(
      itemId: 'e1',
      name: 'Pilota',
      kind: NowPlayingKind.episode,
      seriesName: 'Lost',
      seasonNumber: 1,
      episodeNumber: 3,
    );
    expect(nowPlayingTitle(it, episode), 'Lost · S1:E3 · Pilota');
    expect(
        nowPlayingTitle(
            it,
            const NowPlaying(
                itemId: 'e2',
                name: 'Speciale',
                kind: NowPlayingKind.episode,
                seriesName: 'Lost',
                episodeNumber: 2)),
        'Lost · E2 · Speciale');
    expect(
        nowPlayingTitle(
            it,
            const NowPlaying(
                itemId: 'e3',
                name: 'Extra',
                kind: NowPlayingKind.episode,
                seriesName: 'Lost')),
        'Lost · Extra');
    expect(
        nowPlayingTitle(it, const NowPlaying(itemId: 'x', name: 'Un video')),
        'Un video');
  });

  test('client e dispositivo', () {
    final sessions = testSessions();
    expect(sessionDevice(sessions[0]), 'Jellyfin Android TV · FireTV Soggiorno');
    expect(
        sessionDevice(const SessionEntry(
            id: 's', userId: 'u', userName: 'x', deviceName: 'PC')),
        'PC');
  });

  test('riga della transcodifica e motivi', () {
    final transcode = testSessions()[0].transcode!;
    expect(transcodeLine(it, transcode), '→ H264 1080p · AAC · 8,2 Mbps · Software');
    expect(transcodeReasons(it, transcode.reasons),
        'codec video non supportato, codec audio non supportato');

    // Solo l'audio: niente video né accelerazione.
    expect(
        transcodeLine(
            it,
            const TranscodeInfo(
                isVideoDirect: true, audioCodec: 'aac', bitrate: 640000)),
        '→ AAC · 0,6 Mbps');
    expect(
        transcodeLine(
            it,
            const TranscodeInfo(
                videoCodec: 'hevc', hardwareAcceleration: 'vaapi')),
        '→ HEVC · VA-API');

    // Niente da dire (video diretto, audio non letto, nessun bitrate): la
    // riga non c'è.
    expect(transcodeLine(it, const TranscodeInfo(isVideoDirect: true)), isNull);
    expect(
        transcodeLine(
            it, const TranscodeInfo(isVideoDirect: true, isAudioDirect: true)),
        isNull);

    // Due motivi di bitrate diventano uno; uno sconosciuto resta com'è.
    expect(
        transcodeReasons(it, [
          'ContainerBitrateExceedsLimit',
          'VideoBitrateNotSupported',
          'SomethingNew',
        ]),
        'bitrate oltre il limite, SomethingNew');
  });

  test('accelerazione hardware', () {
    expect(hardwareLabel(it, null), 'Software');
    expect(hardwareLabel(it, 'none'), 'Software');
    expect(hardwareLabel(it, 'nvenc'), 'NVIDIA NVENC');
    expect(hardwareLabel(it, 'qsv'), 'Intel QSV');
    expect(hardwareLabel(it, 'boh'), 'boh');
  });

  test('stato dei watch party', () {
    expect(partyStateLabel(it, PartyState.playing), 'In riproduzione');
    expect(partyStateLabel(it, PartyState.paused), 'In pausa');
    expect(partyStateLabel(it, PartyState.waiting), 'In attesa');
    expect(partyStateLabel(it, PartyState.idle), 'Fermo');
    expect(partyStateLabel(it, PartyState.unknown), isNull);
  });
}
