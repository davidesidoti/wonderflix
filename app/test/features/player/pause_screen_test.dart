import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/pause_screen.dart';
import 'package:wonderflix/features/player/player_keys.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  test('anno, durata e al massimo due generi; si omette ciò che manca', () {
    expect(
        pauseScreenMeta(testItem(
            year: 2024,
            runtimeMinutes: 166,
            genres: ['Fantascienza', 'Avventura', 'Dramma'])),
        '2024 · 2h 46m · Fantascienza · Avventura');
    expect(pauseScreenMeta(testItem(year: null, runtimeMinutes: null)), '');
  });

  test('generi tradotti, senza doppioni, al massimo due', () {
    expect(
        pauseScreenMeta(testItem(
            year: null,
            runtimeMinutes: null,
            genres: ['Drama', 'Dramma', 'Crime', 'Thriller'])),
        'Dramma · Poliziesco');
  });

  Future<ValueNotifier<bool>> pumpPause(WidgetTester tester, JellyfinItem item,
      {bool visible = false,
      MotionLevel motion = MotionLevel.reduced,
      FakeVideoEngine? engine,
      VoidCallback? onResume,
      Size size = const Size(1440, 900),
      bool touch = false,
      bool tv = false}) async {
    final shown = ValueNotifier(visible);
    addTearDown(shown.dispose);
    final video = engine ?? FakeVideoEngine();
    await pumpApp(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, value, _) => PauseScreen(
            item: item,
            visible: value,
            engine: video,
            onResume: onResume ?? () {}),
      ),
      motion: motion,
      surfaceSize: size,
      touch: touch,
      tv: tv,
    );
    return shown;
  }

  testWidgets('nascosta non è nell\'albero; mostrata, tutti i dati',
      (tester) async {
    final shown = await pumpPause(
        tester,
        testItem(
          id: 'e4',
          name: 'Pilot',
          kind: ItemKind.episode,
          seriesName: 'Breaking Bad',
          index: 4,
          seasonIndex: 1,
          year: 2008,
          runtimeMinutes: 58,
          genres: ['Dramma'],
          overview: 'Un professore scopre di essere malato.',
        ));
    expect(find.byKey(const Key('pause-screen')), findsNothing);

    shown.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Stai guardando'), findsOneWidget);
    expect(find.text('BREAKING BAD'), findsOneWidget);
    expect(find.text('S1:E4 · Pilot'), findsOneWidget);
    expect(find.text('2008 · 58m · Dramma'), findsOneWidget);
    expect(find.text('Un professore scopre di essere malato.'), findsOneWidget);
    expect(find.text('In pausa'), findsNothing);

    shown.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pause-screen')), findsNothing);
  });

  testWidgets('titolo lungo: puntini, nessun overflow', (tester) async {
    await pumpPause(tester, testItem(name: 'Lorem ipsum ' * 17),
        visible: true);
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.textContaining('LOREM IPSUM'));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('animazioni complete: il testo sale entrando', (tester) async {
    final shown = await pumpPause(tester, testItem(name: 'Dune'),
        motion: MotionLevel.full);
    shown.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    double rise() => tester
        .widget<Transform>(find
            .ancestor(
                of: find.text('Stai guardando'),
                matching: find.byType(Transform))
            .first)
        .transform
        .getTranslation()
        .y;
    expect(rise(), greaterThan(0));
    await tester.pumpAndSettle();
    expect(rise(), 0);
  });

  JellyfinItem episode({List<String> genres = const []}) => testItem(
        id: 'e4',
        name: 'La scatola',
        kind: ItemKind.episode,
        seriesName: "L'Istituto",
        index: 4,
        seasonIndex: 1,
        year: 2025,
        runtimeMinutes: 52,
        genres: genres,
      );

  FakeVideoEngine pausedAt(Duration position, Duration duration) =>
      FakeVideoEngine()
        ..emitDuration(duration)
        ..emitPosition(position);

  testWidgets('pausa: frase normale, Riprendi con Spazio, tempo che resta',
      (tester) async {
    await pumpPause(tester, episode(genres: ['Crime', 'Drama']),
        visible: true,
        engine: pausedAt(const Duration(minutes: 23, seconds: 12),
            const Duration(minutes: 52)));
    await tester.pumpAndSettle();
    expect(find.text('Stai guardando'), findsOneWidget);
    expect(find.widgetWithText(WfButton, 'Riprendi'), findsOneWidget);
    expect(find.text('oppure'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('pause-resume')),
            matching: find.text('Spazio')),
        findsOneWidget);
    expect(find.text('23:12'), findsOneWidget);
    expect(find.text('resta 28:48'), findsOneWidget);
    expect(find.text('In pausa'), findsNothing);
    expect(find.text('2025 · 52m · Poliziesco · Dramma'), findsOneWidget);
    expect(find.byType(PlayerKeysCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pausa: Riprendi chiama onResume', (tester) async {
    var resumed = 0;
    await pumpPause(tester, episode(),
        visible: true, onResume: () => resumed++);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(WfButton, 'Riprendi'));
    expect(resumed, 1);
  });

  testWidgets('pausa sul telefono e in TV: niente scheda né tasto',
      (tester) async {
    await pumpPause(tester, episode(),
        visible: true, touch: true, size: const Size(390, 780));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(WfButton, 'Riprendi'), findsOneWidget);
    expect(find.byType(PlayerKeysCard), findsNothing);
    expect(find.text('Spazio'), findsNothing);
    expect(tester.takeException(), isNull);

    await pumpPause(tester, episode(),
        visible: true, tv: true, size: const Size(960, 540));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerKeysCard), findsNothing);
    expect(find.text('Spazio'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finestra stretta: Riprendi con Spazio, senza la scheda',
      (tester) async {
    await pumpPause(tester, episode(),
        visible: true, size: const Size(800, 600));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerKeysCard), findsNothing);
    expect(find.text('Spazio'), findsOneWidget);
  });

  testWidgets('finestra bassa (1280×640): la scheda resta sopra il tempo',
      (tester) async {
    await pumpPause(tester, episode(),
        visible: true,
        size: const Size(1280, 640),
        engine: pausedAt(const Duration(minutes: 23, seconds: 12),
            const Duration(minutes: 52)));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(PlayerKeysCard)).bottom,
        lessThan(tester.getRect(find.text('resta 28:48')).top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('durata ignota: niente resto', (tester) async {
    await pumpPause(tester, episode(),
        visible: true, engine: pausedAt(Duration.zero, Duration.zero));
    await tester.pumpAndSettle();
    expect(find.textContaining('resta'), findsNothing);
  });
}
