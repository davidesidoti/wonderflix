import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/media_info_models.dart';
import 'package:wonderflix/core/subtitles/subtitle_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/settings/language_preferences.dart';
import 'package:wonderflix/features/subtitles/subtitle_file_picker.dart';
import 'package:wonderflix/features/subtitles/subtitles_controller.dart';
import 'package:wonderflix/features/subtitles/subtitles_dialog.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/report_fakes.dart';
import '../../support/settings_fakes.dart';
import '../../support/test_data.dart';

class _RecordingSubtitlesApi extends FakeSubtitlesApi {
  SubtitleUpload? lastUpload;

  @override
  Future<void> upload(String itemId, SubtitleUpload upload) {
    lastUpload = upload;
    return super.upload(itemId, upload);
  }
}

const _externalTrack = SubtitleTrack(
  index: 3,
  language: 'ita',
  codec: 'srt',
  isExternal: true,
);
const _embeddedTrack = SubtitleTrack(index: 2, language: 'eng', codec: 'ass');

void main() {
  late _RecordingSubtitlesApi api;
  late FakeLibraryApi library;
  late int added;

  setUp(() {
    api = _RecordingSubtitlesApi();
    library = FakeLibraryApi()
      ..mediaInfoById['e1'] = testMediaInfo(
        subtitles: [_externalTrack, _embeddedTrack],
      );
    added = 0;
  });

  Future<void> open(
    WidgetTester tester, {
    JellyfinUser user = testUser,
    PickedSubtitleFile? picked,
    Size surfaceSize = const Size(1440, 900),
  }) async {
    await pumpApp(
      tester,
      surfaceSize: surfaceSize,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showSubtitlesDialog(
                context,
                itemId: 'e1',
                title: 'Dark',
                onTrackAdded: () => added++,
              ),
            ),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: [
        ...reportTestOverrides(subtitles: api),
        libraryApiProvider.overrideWithValue(library),
        userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(SessionSignedIn(user)),
        ),
        subtitleFilePickerProvider.overrideWithValue((_) async => picked),
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester) async {
    await tester.tap(find.text('Cerca'));
    await tester.pumpAndSettle();
  }

  Finder row(String id) => find.byKey(ValueKey('subtitle-$id'));

  testWidgets('etichette e ordine dei risultati', (tester) async {
    api.results.addAll([
      testSubtitle(
        id: 'a',
        name: 'Zeta',
        providerName: 'Podnapisi',
        format: 'ass',
        communityRating: 7.5,
        downloadCount: 3,
        forced: true,
        machineTranslated: true,
      ),
      testSubtitle(
        id: 'b',
        name: 'Alfa',
        providerName: 'OpenSubtitles',
        downloadCount: 1200,
        isHashMatch: true,
        hearingImpaired: true,
      ),
      testSubtitle(id: 'c', name: 'Beta', providerName: '', format: ''),
    ]);
    await open(tester);
    expect(find.text('Zeta'), findsNothing, reason: 'prima di cercare');

    await search(tester);

    expect(
      tester.getTopLeft(find.text('Alfa')).dy,
      lessThan(tester.getTopLeft(find.text('Zeta')).dy),
    );
    expect(
      find.descendant(
        of: row('b'),
        matching: find.text('OpenSubtitles · srt · 1200 download'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row('a'),
        matching: find.text('Podnapisi · ass · ★ 7.5 · 3 download'),
      ),
      findsOneWidget,
    );
    // Una riga senza niente da dire non ha la riga dei dettagli.
    expect(
      find.descendant(of: row('c'), matching: find.byType(Text)),
      findsNWidgets(2),
      reason: 'nome e bottone',
    );

    final hash = find.descendant(
      of: row('b'),
      matching: find.text('Sincronizzato col file'),
    );
    expect(tester.widget<Text>(hash).style?.color, WfColors.online);
    expect(
      find.descendant(of: row('b'), matching: find.text('Per non udenti')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('a'), matching: find.text('Forzati')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row('a'),
        matching: find.text('Tradotto automaticamente'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row('a'),
        matching: find.text('Sincronizzato col file'),
      ),
      findsNothing,
    );

    // Primario per i sincronizzati col file, secondario per gli altri.
    expect(
      find.descendant(of: row('b'), matching: find.bySubtype<FilledButton>()),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row('a'), matching: find.bySubtype<OutlinedButton>()),
      findsOneWidget,
    );
  });

  testWidgets('lista vuota: nessun sottotitolo trovato', (tester) async {
    await open(tester);
    expect(find.text('Nessun sottotitolo trovato'), findsNothing);

    await search(tester);

    expect(find.text('Nessun sottotitolo trovato'), findsOneWidget);
  });

  testWidgets('Elimina solo per l\'admin e solo sulle esterne', (tester) async {
    // Chi ha solo la spunta dei sottotitoli.
    await open(
      tester,
      user: const JellyfinUser(
        id: 'u1',
        name: 'Mario',
        enableSubtitleManagement: true,
      ),
    );
    expect(find.text('Tracce presenti'), findsOneWidget);
    expect(find.textContaining('esterno'), findsOneWidget);
    expect(find.textContaining('nel file'), findsOneWidget);
    expect(find.text('Elimina'), findsNothing);
  });

  testWidgets('l\'admin elimina solo una traccia esterna', (tester) async {
    await open(tester, user: testAdmin);
    expect(find.text('Elimina'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('track-3')),
        matching: find.text('Elimina'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('l\'admin non elimina una traccia nel file', (tester) async {
    library.mediaInfoById['e1'] = testMediaInfo(subtitles: [_embeddedTrack]);
    await open(tester, user: testAdmin);
    expect(find.textContaining('nel file'), findsOneWidget);
    expect(find.text('Elimina'), findsNothing);
  });

  testWidgets('nessuna traccia: Nessuna traccia', (tester) async {
    library.mediaInfoById['e1'] = testMediaInfo();
    await open(tester, user: testAdmin);
    expect(find.text('Nessuna traccia'), findsOneWidget);
  });

  testWidgets('Elimina chiede conferma e chiama delete', (tester) async {
    await open(tester, user: testAdmin);
    final readsBefore = library.mediaInfoCalls.length;

    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminare il sottotitolo?'), findsOneWidget);

    // Annulla: niente.
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);

    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    // La finestra di conferma sta sopra: il suo "Elimina" è l'ultimo.
    await tester.tap(find.text('Elimina').last);
    await tester.pumpAndSettle();

    expect(api.calls, ['delete e1 3']);
    expect(
      library.mediaInfoCalls.length,
      greaterThan(readsBefore),
      reason: 'le tracce si rileggono',
    );
  });

  testWidgets('il caricamento manda il file e chiama onTrackAdded', (
    tester,
  ) async {
    await open(
      tester,
      user: testUser,
      picked: PickedSubtitleFile(
        name: 'Dark.it.SRT',
        length: 4,
        read: () async => Uint8List.fromList([1, 2, 3, 4]),
      ),
    );

    await tester.tap(find.text('Forzati'));
    await tester.pump();
    await tester.tap(find.text('Carica file…'));
    await tester.pump();
    await tester.pump();
    expect(api.calls, ['upload e1 ita srt']);
    expect(api.lastUpload!.isForced, isTrue);
    expect(api.lastUpload!.isHearingImpaired, isFalse);
    expect(api.lastUpload!.bytes, hasLength(4));
    expect(
      find.text('Aspetto che Jellyfin aggiunga la traccia…'),
      findsOneWidget,
    );

    library.mediaInfoById['e1'] = testMediaInfo(
      subtitles: [
        _externalTrack,
        _embeddedTrack,
        const SubtitleTrack(index: 9, isExternal: true),
      ],
    );
    await tester.pump(subtitlePollInterval);
    await tester.pump();

    expect(added, 1);
    expect(find.text('Sottotitolo aggiunto'), findsOneWidget);
  });

  testWidgets('la rotella compare durante la ricerca', (tester) async {
    final gate = api.gate = Completer<void>();
    await open(tester);
    const progress = ValueKey('subtitles-progress');

    await tester.tap(find.text('Cerca'));
    await tester.pump();
    expect(find.byKey(progress), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(progress), findsNothing);
  });

  testWidgets('la rotella compare durante il caricamento', (tester) async {
    final gate = api.gate = Completer<void>();
    await open(
      tester,
      picked: PickedSubtitleFile(
        name: 'Dark.srt',
        length: 1,
        read: () async => Uint8List.fromList([1]),
      ),
    );
    const progress = ValueKey('subtitles-progress');

    await tester.tap(find.text('Carica file…'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(progress), findsOneWidget);
    expect(
      find.text('Aspetto che Jellyfin aggiunga la traccia…'),
      findsNothing,
    );

    gate.complete();
    await tester.pump();
    await tester.pump();
    // Ora c'è l'avviso con la sua rotella: quella dei risultati non serve.
    expect(find.byKey(progress), findsNothing);
    expect(
      find.text('Aspetto che Jellyfin aggiunga la traccia…'),
      findsOneWidget,
    );
  });

  testWidgets('il menu della lingua ha la sua etichetta e Chiudi chiude', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Lingua'), findsOneWidget);

    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();

    expect(find.text('Lingua'), findsNothing);
  });

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets(
      'con i risultati ${size.width.toInt()}x${size.height.toInt()}: nessun overflow',
      (tester) async {
        api.results.addAll([
          testSubtitle(
            id: 'a',
            name:
                'Dark.S01E02.2160p.WEB-DL.DDP5.1.Atmos.HDR10.H265-GRUPPO.ita.forced',
            providerName: 'OpenSubtitles',
            format: 'ass',
            communityRating: 7.5,
            downloadCount: 1200,
            forced: true,
            machineTranslated: true,
            hearingImpaired: true,
            isHashMatch: true,
          ),
          testSubtitle(id: 'b', name: 'Beta', providerName: 'Podnapisi'),
        ]);
        await open(tester, user: testAdmin, surfaceSize: size);
        await search(tester);
        expect(row('a'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
