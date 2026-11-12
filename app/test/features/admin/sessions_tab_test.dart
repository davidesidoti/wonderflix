import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/admin_models.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/features/admin/admin_kit.dart';
import 'package:wonderflix/features/admin/sessions_tab.dart';

import '../../support/admin_fakes.dart';
import '../../support/avatar_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAdminApi api;

  setUp(() => api = FakeAdminApi());

  Future<void> pumpTab(WidgetTester tester,
      {Size surfaceSize = const Size(1440, 900),
      List<Override> overrides = const []}) async {
    await pumpApp(tester, const Scaffold(body: SessionsTab()),
        overrides: [...adminTestOverrides(api), ...overrides],
        surfaceSize: surfaceSize);
    await tester.pumpAndSettle();
  }

  testWidgets('chi guarda, chi è collegato e i party', (tester) async {
    api
      ..sessionsValue = testSessions()
      ..partiesValue = testParties();
    await pumpTab(tester);

    // Episodio transcodificato su FireTV.
    expect(find.text('viviroby'), findsOneWidget);
    expect(find.text('Jellyfin Android TV · FireTV Soggiorno'), findsOneWidget);
    expect(find.text('Lost · S1:E3 · Pilota'), findsOneWidget);
    expect(find.text('12:34 / 42:36'), findsOneWidget);
    expect(find.text('Transcodifica'), findsOneWidget);
    expect(find.text('→ H264 1080p · AAC · 8,2 Mbps · Software'), findsOneWidget);
    expect(find.text('codec video non supportato, codec audio non supportato'),
        findsOneWidget);

    // Film in remux, in pausa: niente riga della transcodifica.
    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(find.text('Remux'), findsOneWidget);
    expect(find.byKey(const Key('session-paused-s2')), findsOneWidget);
    expect(find.byKey(const Key('session-paused-s1')), findsNothing);
    expect(find.textContaining('→ HEVC'), findsNothing);

    // Collegato senza riprodurre.
    expect(find.text('davide.sidoti'), findsOneWidget);
    expect(find.text('WonderFlix · nocturne'), findsOneWidget);
    expect(find.textContaining('attivo '), findsOneWidget);

    // Il party.
    expect(find.text('Serata Lost'), findsOneWidget);
    expect(find.text('viviroby, Mario'), findsOneWidget);

    // La chiave API di Seerr non c'è.
    expect(find.text('Seerr'), findsNothing);
  });

  testWidgets(
      'stringhe lunghe, metodo sconosciuto, durata zero: nessun overflow',
      (tester) async {
    final long = List.filled(14, 'lunghissimo').join(' ');
    SessionEntry playing(
      String id, {
      required NowPlaying item,
      Duration position = Duration.zero,
      PlayMethod method = PlayMethod.unknown,
      TranscodeInfo? transcode,
    }) =>
        SessionEntry(
          id: id,
          userId: 'u-$id',
          userName: long,
          client: long,
          deviceName: long,
          nowPlaying: item,
          position: position,
          playMethod: method,
          transcode: transcode,
        );
    api
      ..sessionsValue = [
        // Metodo sconosciuto: niente riga del metodo.
        playing('a',
            item: NowPlaying(
                itemId: 'm1',
                name: long,
                kind: NowPlayingKind.movie,
                year: 2021,
                runtime: const Duration(minutes: 100)),
            position: const Duration(minutes: 10)),
        // Durata zero: solo la posizione.
        playing('b',
            item: const NowPlaying(
                itemId: 'm2', name: 'Senza durata', runtime: Duration.zero),
            position: const Duration(minutes: 12, seconds: 34),
            method: PlayMethod.directPlay),
        // Transcodifica senza niente da dire: né riga né motivi.
        playing('c',
            item: const NowPlaying(itemId: 'm3', name: 'Muto'),
            method: PlayMethod.transcode,
            transcode: const TranscodeInfo(isVideoDirect: true)),
        // Transcodifica con tutto lungo.
        playing('d',
            item: NowPlaying(itemId: 'm4', name: long),
            method: PlayMethod.transcode,
            transcode: TranscodeInfo(
              videoCodec: 'hevc',
              audioCodec: 'eac3',
              bitrate: 8200000,
              height: 2160,
              hardwareAcceleration: long,
              reasons: const ['VideoCodecNotSupported', 'AudioChannelsNotSupported'],
            )),
        testSession('e', long, lastActivity: DateTime.utc(2026, 10, 6, 8)),
      ]
      ..partiesValue = [
        PartyGroup(
          id: 'p1',
          name: long,
          state: PartyState.playing,
          participants: [long, long],
        ),
      ];
    await pumpTab(tester, surfaceSize: const Size(1024, 768));

    // Un overflow farebbe fallire il test da solo.
    expect(find.text('12:34'), findsOneWidget);
    expect(find.textContaining('/ 00:00'), findsNothing);
    expect(find.text('10:00 / 1:40:00'), findsOneWidget);
    expect(find.text('Diretta'), findsOneWidget);
    expect(find.text('Remux'), findsNothing);
    expect(find.text('Transcodifica'), findsNWidgets(2));
    expect(find.text('→ '), findsNothing);

    // Il party sta in fondo: la lista è pigra, va portato in vista.
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('party-p1')), 300,
        scrollable: find.byType(Scrollable));
    expect(find.byKey(const ValueKey('party-p1')), findsOneWidget);
  });

  testWidgets('le sale: "Sala 1" e "Sala 2" nell\'ordine dello snapshot',
      (tester) async {
    api.sessionsValue = [
      testSession('s1', 'Mario', playing: testMovie),
      testSession('s2', 'Luigi', playing: testMovie),
    ];
    await pumpTab(tester);

    expect(find.text('Sala 1'), findsOneWidget);
    expect(find.text('Sala 2'), findsOneWidget);
    expect(
        tester.getTopLeft(find.text('Sala 1')).dx <
            tester.getTopLeft(find.text('Sala 2')).dx,
        isTrue);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('playing-s1')),
            matching: find.text('Mario')),
        findsOneWidget);
  });

  testWidgets('durata zero: barra vuota, solo il tempo, nessun NaN',
      (tester) async {
    api.sessionsValue = [
      testSession('s1', 'Mario',
          playing: const NowPlaying(
              itemId: 'm2', name: 'Senza durata', runtime: Duration.zero)),
    ];
    await pumpTab(tester);

    expect(find.byType(FilmStripBar), findsOneWidget);
    expect(find.byKey(const ValueKey('film-strip-filled')), findsNothing);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('transcodifica: etichetta, riga e motivi; pausa accanto',
      (tester) async {
    api.sessionsValue = const [
      SessionEntry(
          id: 's1',
          userId: 'u1',
          userName: 'Mario',
          nowPlaying: testMovie,
          isPaused: true,
          playMethod: PlayMethod.transcode,
          transcode: TranscodeInfo(
              videoCodec: 'h264', reasons: ['VideoCodecNotSupported'])),
    ];
    await pumpTab(tester);

    expect(find.text('Transcodifica'), findsOneWidget);
    expect(find.textContaining('→ H264'), findsOneWidget);
    expect(find.text('codec video non supportato'), findsOneWidget);
    expect(find.byKey(const Key('session-paused-s1')), findsOneWidget);
  });

  testWidgets('il titolo della sezione dei collegati è "In sala d\'attesa"',
      (tester) async {
    api.sessionsValue = [testSession('s1', 'Mario')];
    await pumpTab(tester);

    expect(find.text('In sala d\'attesa'), findsOneWidget);
    expect(find.text('Collegati'), findsNothing);
  });

  testWidgets('stretto: una sala per riga', (tester) async {
    api.sessionsValue = [
      testSession('s1', 'Mario', playing: testMovie),
      testSession('s2', 'Luigi', playing: testMovie),
    ];
    await pumpTab(tester, surfaceSize: const Size(500, 900));

    expect(tester.getTopLeft(find.text('Sala 1')).dx,
        tester.getTopLeft(find.text('Sala 2')).dx);
  });

  testWidgets('le righe utente: l\'immagine con il tag della sessione',
      (tester) async {
    final urls = <String>[];
    api.sessionsValue = const [
      SessionEntry(
          id: 's1',
          userId: 'u1',
          userName: 'Mario',
          userImageTag: 't1',
          nowPlaying: testMovie),
      SessionEntry(
          id: 's2', userId: 'u2', userName: 'Luigi', userImageTag: 't2'),
    ];
    await pumpTab(tester, overrides: [captureImageUrls(urls)]);

    expect(
        urls,
        containsAll([
          'https://media.example.com/UserImage?userId=u1&tag=t1',
          'https://media.example.com/UserImage?userId=u2&tag=t2',
        ]));
  });

  testWidgets('nessuno: tre testi vuoti', (tester) async {
    await pumpTab(tester);

    expect(find.text('Nessuno sta guardando'), findsOneWidget);
    expect(find.text('Nessuno collegato'), findsOneWidget);
    expect(find.text('Nessun watch party in corso'), findsOneWidget);
  });

  testWidgets('primo caricamento fallito: errore e Riprova', (tester) async {
    api.sessionsError = const ServerUnreachableException();
    await pumpTab(tester);

    expect(find.text('Riprova'), findsOneWidget);

    api.sessionsError = null;
    api.sessionsValue = testSessions();
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(find.text('viviroby'), findsOneWidget);
  });

  testWidgets('rilettura fallita: restano i dati con "Dati non aggiornati"',
      (tester) async {
    api.sessionsValue = testSessions();
    await pumpTab(tester);
    expect(find.textContaining('Dati non aggiornati'), findsNothing);

    api.sessionsError = const ServerUnreachableException();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.textContaining('Dati non aggiornati'), findsOneWidget);
    expect(find.text('viviroby'), findsOneWidget);
  });
}
