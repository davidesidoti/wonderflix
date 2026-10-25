import 'package:flutter/material.dart';
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

  Future<void> openDialog(WidgetTester tester,
      {JellyfinUser user = testUser,
      Size surfaceSize = const Size(1440, 900)}) async {
    final item = testItem(id: 'e1', name: 'Pilot', kind: ItemKind.episode);
    await pumpApp(
      tester,
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
            () => FakeSessionController(SessionSignedIn(user))),
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('due versioni, video, audio e sottotitoli', (tester) async {
    final base = testMediaInfo(subtitles: const [
      SubtitleTrack(
          index: 2, language: 'ita', codec: 'subrip', isExternal: true),
      SubtitleTrack(
          index: 3, language: 'eng', codec: 'ass', isForced: true),
    ]);
    api.mediaInfoById['e1'] = ItemMediaInfo(versions: [
      ...base.versions,
      const MediaVersion(id: 'v2', name: 'Dark 4K', container: 'mp4'),
    ]);
    await openDialog(tester);

    expect(find.text('Info tecniche'), findsOneWidget);
    expect(find.text('Pilot'), findsOneWidget);
    expect(find.text('Versione: Dark 1080p'), findsOneWidget);
    expect(find.text('Versione: Dark 4K'), findsOneWidget);
    expect(find.text('mkv'), findsOneWidget);
    expect(find.text('1,5 GB'), findsOneWidget);
    expect(find.text('52m'), findsOneWidget);
    expect(find.text('6,0 Mbps'), findsOneWidget);
    expect(find.textContaining('h264'), findsOneWidget);
    expect(find.textContaining('1920×1080'), findsOneWidget);
    expect(find.textContaining('SDR'), findsOneWidget);
    expect(find.textContaining('ac3'), findsOneWidget);
    expect(find.textContaining('6 canali'), findsOneWidget);
    expect(find.textContaining('predefinita'), findsOneWidget);
    expect(find.textContaining('subrip'), findsOneWidget);
    expect(find.textContaining('esterno'), findsOneWidget);
    expect(find.textContaining('nel file'), findsOneWidget);
    expect(find.textContaining('Forzati'), findsOneWidget);
  });

  testWidgets('una sola versione: niente titolo di versione', (tester) async {
    api.mediaInfoById['e1'] = testMediaInfo();
    await openDialog(tester);
    expect(find.textContaining('Versione:'), findsNothing);
    expect(find.text('mkv'), findsOneWidget);
  });

  testWidgets('il nome del file solo per l\'admin', (tester) async {
    api.mediaInfoById['e1'] = testMediaInfo();
    await openDialog(tester);
    expect(find.text('Dark.S01E02.mkv'), findsNothing);
    expect(find.text('File'), findsNothing);
  });

  testWidgets('il nome del file per l\'admin', (tester) async {
    api.mediaInfoById['e1'] = testMediaInfo();
    await openDialog(tester, user: testAdmin);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Dark.S01E02.mkv'), findsOneWidget);
  });

  testWidgets('errore: informazioni non disponibili', (tester) async {
    await openDialog(tester);
    expect(find.text('Informazioni non disponibili'), findsOneWidget);
  });

  testWidgets('nessuna versione: informazioni non disponibili',
      (tester) async {
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
    testWidgets('telefono ${size.width.toInt()}x${size.height.toInt()}: nessun overflow', (tester) async {
      await openDialog(tester, surfaceSize: size);
      expect(tester.takeException(), isNull);
    });
  }
}
