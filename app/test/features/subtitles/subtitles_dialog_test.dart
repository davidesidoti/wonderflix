import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/media_info_models.dart';
import 'package:wonderflix/core/subtitles/subtitle_models.dart';
import 'package:wonderflix/core/subtitles/subtitles_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/settings/language_preferences.dart';
import 'package:wonderflix/features/subtitles/subtitle_file_picker.dart';
import 'package:wonderflix/features/subtitles/subtitles_controller.dart';
import 'package:wonderflix/features/subtitles/subtitles_dialog.dart';
import 'package:wonderflix/ui/dialog_item_poster.dart';
import 'package:wonderflix/ui/wf_dialog_parts.dart';

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

/// La lettura delle preferenze arriva dopo [delay].
class _SlowUserConfigApi extends FakeUserConfigApi {
  _SlowUserConfigApi(this.delay);

  final Duration delay;

  @override
  Future<Map<String, dynamic>> configuration() async {
    await Future<void>.delayed(delay);
    return super.configuration();
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

  /// Con [settle] falso pompa solo due frame: una ricerca ferma su un
  /// cancello lascia la rotella, che non si assesta mai.
  Future<void> open(
    WidgetTester tester, {
    JellyfinUser user = testUser,
    PickedSubtitleFile? picked,
    Size surfaceSize = const Size(1440, 900),
    FakeUserConfigApi? config,
    bool settle = true,
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
        userConfigApiProvider.overrideWithValue(config ?? FakeUserConfigApi()),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(SessionSignedIn(user)),
        ),
        subtitleFilePickerProvider.overrideWithValue((_) async => picked),
      ],
    );
    await tester.tap(find.text('apri'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
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

    expect(
      tester.getTopLeft(find.text('Alfa')).dy,
      lessThan(tester.getTopLeft(find.text('Zeta')).dy),
    );
    expect(
      find.descendant(
        of: row('b'),
        matching: find.text('OpenSubtitles · SRT · 1200 download'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row('a'),
        matching: find.text('Podnapisi · ASS · ★ 7,5 · 3 download'),
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

    expect(find.text('Nessun sottotitolo trovato'), findsOneWidget);
  });

  testWidgets('la ricerca parte all\'apertura e riparte se cambi lingua', (
    tester,
  ) async {
    await open(tester);
    expect(api.calls, ['search e1 ita -']);
    // "Cerca" è il titolo della sezione, non un bottone.
    expect(
      find.ancestor(
        of: find.text('Cerca'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
      findsNothing,
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(api.calls, ['search e1 ita -', 'search e1 eng -']);
  });

  testWidgets('la preferenza che arriva dopo vale per la prima ricerca', (
    tester,
  ) async {
    final config = _SlowUserConfigApi(const Duration(milliseconds: 300))
      ..config['SubtitleLanguagePreference'] = 'eng';
    await open(tester, config: config, settle: false);
    expect(api.calls, isEmpty, reason: 'aspetta la preferenza');
    expect(
      find.byKey(const ValueKey('subtitles-progress')),
      findsOneWidget,
      reason: "anche durante l'attesa la rotella",
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(api.calls, ['search e1 eng -']);
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
    expect(find.text('SRT · file esterno'), findsOneWidget);
    expect(find.text('ASS · dentro il video'), findsOneWidget);
    expect(find.text('Elimina…'), findsNothing);
    expect(find.text('Non si può eliminare'), findsNothing);
  });

  testWidgets('l\'admin elimina solo una traccia esterna', (tester) async {
    await open(tester, user: testAdmin);
    expect(find.text('Elimina…'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('track-3')),
        matching: find.text('Elimina…'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('l\'admin non elimina una traccia nel file', (tester) async {
    library.mediaInfoById['e1'] = testMediaInfo(subtitles: [_embeddedTrack]);
    await open(tester, user: testAdmin);
    expect(find.text('ASS · dentro il video'), findsOneWidget);
    expect(find.text('Elimina…'), findsNothing);
    expect(find.text('Non si può eliminare'), findsOneWidget);
  });

  testWidgets('le tracce si leggono e la conferma nomina la traccia', (
    tester,
  ) async {
    library.mediaInfoById['e1'] = testMediaInfo(
      subtitles: const [
        SubtitleTrack(
          index: 3,
          language: 'ita',
          codec: 'subrip',
          isExternal: true,
        ),
        SubtitleTrack(index: 2, language: 'eng', codec: 'pgssub'),
      ],
    );
    await open(tester, user: testAdmin);
    final external = find.byKey(const ValueKey('track-3'));
    final embedded = find.byKey(const ValueKey('track-2'));

    expect(
      find.descendant(of: external, matching: find.text('Italiano')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: external, matching: find.text('SRT · file esterno')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: embedded,
        matching: find.text('PGS · dentro il video'),
      ),
      findsOneWidget,
    );
    final cannot = find.descendant(
      of: embedded,
      matching: find.text('Non si può eliminare'),
    );
    expect(tester.widget<Text>(cannot).style?.color, WfColors.creamMuted);

    await tester.tap(find.text('Elimina…'));
    await tester.pumpAndSettle();
    expect(
      find.text('Eliminare i sottotitoli Italiano (SRT, file esterno)?'),
      findsOneWidget,
    );
  });

  testWidgets('nessuna traccia: Nessuna traccia', (tester) async {
    library.mediaInfoById['e1'] = testMediaInfo();
    await open(tester, user: testAdmin);
    expect(find.text('Nessuna traccia'), findsOneWidget);
  });

  testWidgets('Elimina chiede conferma e chiama delete', (tester) async {
    await open(tester, user: testAdmin);
    final readsBefore = library.mediaInfoCalls.length;

    await tester.tap(find.text('Elimina…'));
    await tester.pumpAndSettle();
    expect(
      find.text('Eliminare i sottotitoli Italiano (SRT, file esterno)?'),
      findsOneWidget,
    );

    // Annulla: niente.
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(api.calls, ['search e1 ita -']);

    await tester.tap(find.text('Elimina…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();

    expect(api.calls, ['search e1 ita -', 'delete e1 3']);
    expect(
      library.mediaInfoCalls.length,
      greaterThan(readsBefore),
      reason: 'le tracce si rileggono',
    );
  });

  testWidgets('Forzati e Per non udenti stanno nel riquadro del caricamento', (
    tester,
  ) async {
    await open(tester);
    final panel = find.byKey(const ValueKey('subtitles-upload'));

    for (final text in [
      'Carica un file',
      'Hai già un .srt o un .ass? Lo aggiungo in italiano.',
      'Forzati',
      'Solo cartelli e battute in altre lingue',
      'Per non udenti',
      'Con rumori e nomi di chi parla',
      'Scegli il file…',
    ]) {
      expect(
        find.descendant(of: panel, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
  });

  testWidgets('la testa ha la locandina e la riga del titolo', (tester) async {
    await open(tester);
    expect(find.byType(DialogItemPoster), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
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
    await tester.tap(find.text('Scegli il file…'));
    await tester.pump();
    await tester.pump();
    expect(api.calls, ['search e1 ita -', 'upload e1 ita srt']);
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
    await open(tester, settle: false);
    const progress = ValueKey('subtitles-progress');

    expect(api.calls, ['search e1 ita -']);
    expect(find.byKey(progress), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(progress), findsNothing);
  });

  testWidgets("Esc durante la ricerca dell'apertura chiude la finestra", (
    tester,
  ) async {
    final gate = api.gate = Completer<void>();
    await open(tester, settle: false);
    expect(api.calls, ['search e1 ita -']);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Tracce presenti'), findsNothing);

    // La risposta arriva a finestra chiusa: nessuna scrittura, nessun errore.
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('mentre carica la finestra non si chiude', (tester) async {
    await open(
      tester,
      picked: PickedSubtitleFile(
        name: 'Dark.srt',
        length: 1,
        read: () async => Uint8List.fromList([1]),
      ),
    );
    final gate = api.gate = Completer<void>();
    await tester.tap(find.text('Scegli il file…'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Chiudi'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Tracce presenti'), findsOneWidget);

    gate.complete();
    await tester.pump(subtitlePollTimeout);
    await tester.pumpAndSettle();
  });

  testWidgets('un caricamento non riuscito lo dice il piede', (tester) async {
    await open(
      tester,
      picked: PickedSubtitleFile(
        name: 'Dark.srt',
        length: 1,
        read: () async => Uint8List.fromList([1]),
      ),
    );
    api.nextFailure = SubtitlesFailure.failed;
    await tester.tap(find.text('Scegli il file…'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(WfDialogFooter),
        matching: find.text('Caricamento non riuscito'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('una ricerca non riuscita ha Riprova', (tester) async {
    api.nextFailure = SubtitlesFailure.unavailable;
    api.results.add(testSubtitle(id: 'a', name: 'Alfa'));
    await open(tester);
    expect(row('a'), findsNothing);

    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(api.calls, ['search e1 ita -', 'search e1 ita -']);
    expect(row('a'), findsOneWidget);
    expect(find.text('Riprova'), findsNothing);
  });

  testWidgets('una traccia esterna senza codec', (tester) async {
    library.mediaInfoById['e1'] = testMediaInfo(
      subtitles: const [
        SubtitleTrack(index: 3, language: 'ita', isExternal: true),
      ],
    );
    await open(tester, user: testAdmin);
    expect(find.text('file esterno'), findsOneWidget);

    await tester.tap(find.text('Elimina…'));
    await tester.pumpAndSettle();
    expect(
      find.text('Eliminare i sottotitoli Italiano (file esterno)?'),
      findsOneWidget,
    );
  });

  testWidgets('la rotella compare durante il caricamento', (tester) async {
    await open(
      tester,
      picked: PickedSubtitleFile(
        name: 'Dark.srt',
        length: 1,
        read: () async => Uint8List.fromList([1]),
      ),
    );
    final gate = api.gate = Completer<void>();
    const progress = ValueKey('subtitles-progress');

    await tester.tap(find.text('Scegli il file…'));
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
        expect(row('a'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
