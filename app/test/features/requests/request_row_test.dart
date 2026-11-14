import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/features/requests/request_row.dart';
import 'package:wonderflix/features/requests/request_track.dart';
import 'package:wonderflix/ui/user_avatar.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 5, 12);
  final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));

  Future<List<String>> pumpRow(WidgetTester tester, MediaRequest request,
      {bool showRequester = false,
      Widget? trailing,
      bool tappable = true,
      Size surfaceSize = const Size(1440, 900)}) async {
    final taps = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: RequestRow(
          request: request,
          now: now,
          showRequester: showRequester,
          trailing: trailing,
          onTap: tappable ? () => taps.add('tap') : null,
        ),
      ),
      surfaceSize: surfaceSize,
    );
    return taps;
  }

  testWidgets("film: titolo, anno, chi l'ha chiesto, quando, percorso", (tester) async {
    final taps = await pumpRow(
      tester,
      testMediaRequest(title: 'Dune', year: 2021, requester: 'Garg', createdAt: fiveMinutesAgo),
      showRequester: true,
    );

    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(find.textContaining('Film · chiesta da ', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Garg · 5 min fa', findRichText: true),
        findsOneWidget);
    // Largo: il percorso in una colonna di 400 px, con le etichette.
    expect(find.byType(RequestTrack), findsOneWidget);
    expect(find.text('Da approvare'), findsOneWidget);
    expect(tester.getSize(find.byType(RequestTrack)).width, 400);

    await tester.tap(find.text('Dune (2021)'));
    expect(taps, ['tap']);
  });

  testWidgets('chi ha chiesto: avatar e nome; "tu" se sono io; niente senza showRequester',
      (tester) async {
    await pumpRow(tester, testMediaRequest(requester: 'Luca'),
        showRequester: true);
    expect(find.textContaining('chiesta da ', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Luca', findRichText: true), findsOneWidget);
    // Senza immagine l'avatar è l'iniziale.
    expect(find.byType(UserAvatar), findsOneWidget);
    expect(find.text('L'), findsOneWidget);

    await pumpRow(tester, testMediaRequest(requester: 'Luca', isMe: true),
        showRequester: true);
    expect(find.textContaining('chiesta da tu', findRichText: true),
        findsOneWidget);
    expect(find.byType(UserAvatar), findsNothing);

    await pumpRow(tester, testMediaRequest(requester: 'Luca'));
    expect(find.textContaining('chiesta da', findRichText: true), findsNothing);
    expect(find.byType(UserAvatar), findsNothing);
  });

  testWidgets('stretto: il percorso va sotto, senza etichette, locandina piccola',
      (tester) async {
    await pumpRow(tester, testMediaRequest(title: 'Dune', year: 2021),
        surfaceSize: const Size(600, 900));

    final track = tester.getRect(find.byType(RequestTrack));
    final title = tester.getRect(find.text('Dune (2021)'));
    expect(track.top, greaterThan(title.bottom));
    expect(track.width, greaterThan(400));
    // Senza etichette: la tappa attuale sta nel dettaglio.
    expect(find.text('Da approvare'), findsNothing);
    expect(find.textContaining('Da approvare', findRichText: true),
        findsOneWidget);
    expect(tester.getSize(find.byType(WfImage)).width,
        RequestRow.compactPosterWidth);
  });

  testWidgets("serie: le stagioni chieste; senza chi l'ha chiesto", (tester) async {
    await pumpRow(
      tester,
      testMediaRequest(
          title: 'Brothers',
          year: 2026,
          type: RequestMediaType.tv,
          seasons: const [2, 1],
          status: RequestStatus.downloading,
          progress: 0.45,
          createdAt: fiveMinutesAgo),
    );

    expect(find.text('Stagioni 1–2 · 5 min fa'), findsOneWidget);
    expect(find.text('45% scaricato'), findsOneWidget);
  });

  testWidgets('arrivata: etichetta verde a destra, niente percorso', (tester) async {
    await pumpRow(tester, testMediaRequest(status: RequestStatus.available));

    expect(find.byType(RequestTrack), findsNothing);
    final label = tester.widget<Text>(find.text('Disponibile'));
    expect(label.style?.color, WfColors.online);
  });

  testWidgets('tolta: etichetta spenta, nessun bordo', (tester) async {
    await pumpRow(tester, testMediaRequest(status: RequestStatus.removed));

    final label = tester.widget<Text>(find.text('Tolta dal server'));
    expect(label.style?.color, WfColors.creamMuted);
    expect(find.byType(RequestTrack), findsNothing);
  });

  testWidgets('senza il clic la riga non si apre (azione in corso)', (tester) async {
    final taps = await pumpRow(tester, testMediaRequest(title: 'Dune', year: 2021),
        tappable: false);

    await tester.tap(find.text('Dune (2021)'));
    await tester.pump();

    expect(taps, isEmpty);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });

  testWidgets('titolo che Seerr non ha dato; azioni al posto dello stato',
      (tester) async {
    await pumpRow(
      tester,
      testMediaRequest(title: '', year: null, createdAt: fiveMinutesAgo),
      trailing: const Text('azioni'),
    );

    expect(find.text('Titolo non disponibile'), findsOneWidget);
    expect(find.text('azioni'), findsOneWidget);
    expect(find.text('In attesa'), findsNothing);
    expect(find.byType(RequestTrack), findsNothing);
  });

  testWidgets('TheDatesLineShowsUnderTheTrack', (tester) async {
    await pumpRow(
      tester,
      testMediaRequest(
          status: RequestStatus.awaitingRelease,
          digitalRelease: DateTime.utc(2026, 11, 12)),
    );
    expect(find.textContaining('In digitale previsto il 12 novembre',
            findRichText: true),
        findsOneWidget);

    await pumpRow(tester, testMediaRequest(status: RequestStatus.approved));
    expect(find.textContaining('digitale', findRichText: true), findsNothing);
  });

  testWidgets('con le azioni: le date di uscita sotto il testo, le future in oro',
      (tester) async {
    await pumpRow(
      tester,
      testMediaRequest(digitalRelease: DateTime.utc(2026, 11, 12)),
      trailing: const Text('azioni'),
    );

    final dates = find.textContaining('In digitale previsto il 12 novembre',
        findRichText: true);
    expect(dates, findsOneWidget);
    expect(find.byType(RequestTrack), findsNothing);
    final span = tester.widget<RichText>(dates).text;
    final colors = <Color?>[];
    span.visitChildren((s) {
      if (s is TextSpan && s.text != null) colors.add(s.style?.color);
      return true;
    });
    expect(colors, contains(WfColors.gold));
  });

  testWidgets('stretto con le azioni: sotto il testo, a destra', (tester) async {
    await pumpRow(tester, testMediaRequest(title: 'Dune', year: 2021),
        trailing: const Text('azioni'), surfaceSize: const Size(600, 900));

    final title = tester.getRect(find.text('Dune (2021)'));
    final actions = tester.getRect(find.text('azioni'));
    expect(actions.top, greaterThan(title.bottom));
    expect(actions.right, greaterThan(500));
  });

  testWidgets('TV: layout largo, percorso con le etichette a 960 px',
      (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: RequestRow(request: testMediaRequest(), now: now, onTap: () {}),
      ),
      tv: true,
      surfaceSize: const Size(960, 540),
    );

    expect(find.text('Da approvare'), findsOneWidget);
    expect(tester.getSize(find.byType(RequestTrack)).width, 400);
    expect(tester.getSize(find.byType(WfImage)).width, RequestRow.posterWidth);
  });
}
