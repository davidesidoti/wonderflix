import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/jellyfin/media_info_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/detail/media_info_dialog.dart';
import 'package:wonderflix/features/library/library_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/report_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi api;

  setUp(() => api = FakeLibraryApi());

  Future<void> openDialog(
    WidgetTester tester, {
    JellyfinUser user = testUser,
    Size surfaceSize = const Size(1440, 900),
    bool tv = false,
  }) async {
    final item = testItem(id: 'e1', name: 'Pilot', kind: ItemKind.episode);
    await pumpApp(
      tester,
      tv: tv,
      surfaceSize: surfaceSize,
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showMediaInfoDialog(context, item),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        sessionControllerProvider.overrideWith(
          () => FakeSessionController(SessionSignedIn(user)),
        ),
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('due versioni: una pastiglia per versione', (tester) async {
    final base = testMediaInfo();
    api.mediaInfoById['e1'] = ItemMediaInfo(
      versions: [
        ...base.versions,
        const MediaVersion(id: 'v2', name: 'Dark 4K', container: 'mp4'),
      ],
    );
    await openDialog(tester);

    expect(find.text('Info tecniche'), findsOneWidget);
    expect(find.textContaining('Pilot'), findsOneWidget);
    expect(find.text('Dark 1080p'), findsOneWidget);
    expect(find.text('Dark 4K'), findsOneWidget);
    expect(find.text('MKV'), findsOneWidget);
    expect(find.text('MP4'), findsNothing);

    await tester.tap(find.text('Dark 4K'));
    await tester.pump();

    expect(find.text('MP4'), findsOneWidget);
    expect(find.text('MKV'), findsNothing);
  });

  testWidgets('quattro gruppi con i valori leggibili', (tester) async {
    final base = testMediaInfo(
      subtitles: const [
        SubtitleTrack(
          index: 2,
          language: 'ita',
          codec: 'subrip',
          isExternal: true,
        ),
        SubtitleTrack(index: 3, language: 'eng', codec: 'ass', isForced: true),
      ],
    );
    final version = base.versions.first;
    api.mediaInfoById['e1'] = ItemMediaInfo(
      versions: [
        MediaVersion(
          id: 'v1',
          container: 'mkv',
          size: 2400000000,
          bitrate: 6200000,
          duration: version.duration,
          video: const VideoTrack(
            codec: 'hevc',
            range: 'HDR10',
            width: 3840,
            height: 2160,
            fps: 23.976,
          ),
          audio: const [
            AudioTrack(
              index: 1,
              language: 'ita',
              codec: 'eac3',
              channels: 6,
              isDefault: true,
            ),
          ],
          subtitles: version.subtitles,
        ),
      ],
    );
    await openDialog(tester);

    expect(find.text('Info tecniche'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Audio · 1'), findsOneWidget);
    expect(find.text('Sottotitoli · 2'), findsOneWidget);
    expect(find.text('MKV'), findsOneWidget);
    expect(find.text('2,4 GB'), findsOneWidget);
    expect(find.text('6,2 Mbps'), findsOneWidget);
    expect(
      find.text('HEVC · 4K (3840×2160) · HDR10 · 23,976 fps'),
      findsOneWidget,
    );
    expect(find.text('Italiano · E-AC-3 5.1'), findsOneWidget);
    expect(find.text('Predefinita'), findsOneWidget);
    expect(find.text('Italiano · SRT'), findsOneWidget);
    expect(find.text('File esterno'), findsOneWidget);
    expect(find.text('Inglese · ASS'), findsOneWidget);
    expect(find.text('Dentro il video'), findsOneWidget);
    expect(find.text('Forzati'), findsOneWidget);
  });

  testWidgets('TV: Info tecniche è una finestra, non una pagina', (
    tester,
  ) async {
    await openDialog(tester, surfaceSize: const Size(960, 540), tv: true);
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('TV: niente nome del file, focus su Chiudi, Giù scorre', (
    tester,
  ) async {
    final version = testMediaInfo().versions.first;
    api.mediaInfoById['e1'] = ItemMediaInfo(
      versions: [
        MediaVersion(
          id: 'v1',
          container: 'mkv',
          fileName: 'Dark.S01E02.mkv',
          video: version.video,
          audio: [
            for (var i = 0; i < 30; i++)
              AudioTrack(index: i, language: 'ita', codec: 'ac3', channels: 6),
          ],
        ),
      ],
    );
    await openDialog(
      tester,
      user: testAdmin,
      surfaceSize: const Size(960, 540),
      tv: true,
    );

    expect(find.text('Dark.S01E02.mkv'), findsNothing);
    expect(find.text('Copia'), findsNothing);
    expect(Focus.of(tester.element(find.text('Chiudi'))).hasFocus, isTrue);

    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.pixels, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(scrollable.position.pixels, 80);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(scrollable.position.pixels, 0);
  });

  testWidgets('una sola versione: niente pastiglie', (tester) async {
    api.mediaInfoById['e1'] = testMediaInfo();
    await openDialog(tester);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('MKV'), findsOneWidget);
  });

  testWidgets('il nome del file solo per l\'admin', (tester) async {
    api.mediaInfoById['e1'] = testMediaInfo();
    await openDialog(tester);
    expect(find.text('Dark.S01E02.mkv'), findsNothing);
    expect(find.text('Copia'), findsNothing);
  });

  testWidgets('il nome del file per l\'admin', (tester) async {
    api.mediaInfoById['e1'] = testMediaInfo();
    await openDialog(tester, user: testAdmin);
    expect(find.text('Copia'), findsOneWidget);
    expect(find.text('Dark.S01E02.mkv'), findsOneWidget);
  });

  testWidgets('Copia mette il nome del file negli appunti', (tester) async {
    api.mediaInfoById['e1'] = testMediaInfo();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await openDialog(tester, user: testAdmin);

    await tester.tap(find.text('Copia'));
    await tester.pump();

    expect(copied, 'Dark.S01E02.mkv');
    expect(find.text('Nome del file copiato'), findsOneWidget);
  });

  testWidgets('errore: frase e Riprova che rilegge', (tester) async {
    await openDialog(tester);
    expect(find.text('Non riesco a leggere le info del file'), findsOneWidget);
    expect(api.mediaInfoCalls, ['e1']);

    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(api.mediaInfoCalls, ['e1', 'e1']);
  });

  testWidgets('nessuna versione: informazioni non disponibili', (tester) async {
    api.mediaInfoById['e1'] = const ItemMediaInfo();
    await openDialog(tester);
    expect(find.text('Informazioni non disponibili'), findsOneWidget);
  });

  testWidgets('Chiudi chiude la finestra', (tester) async {
    api.mediaInfoById['e1'] = testMediaInfo();
    await openDialog(tester);
    expect(find.text('Info tecniche'), findsOneWidget);

    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();

    expect(find.text('Info tecniche'), findsNothing);
  });

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets(
      'telefono ${size.width.toInt()}x${size.height.toInt()}: nessun overflow',
      (tester) async {
        final base = testMediaInfo();
        api.mediaInfoById['e1'] = ItemMediaInfo(
          versions: [
            MediaVersion(
              id: 'v1',
              name: 'Dark 4K',
              container: 'mkv',
              fileName:
                  'Dark.S01E02.2160p.WEB-DL.DDP5.1.Atmos.HDR10.H265-GRUPPO.mkv',
              video: base.versions.first.video,
              audio: base.versions.first.audio,
            ),
          ],
        );
        // L'amministratore vede anche il nome del file, il valore più lungo.
        await openDialog(tester, user: testAdmin, surfaceSize: size);
        expect(find.textContaining('GRUPPO'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
