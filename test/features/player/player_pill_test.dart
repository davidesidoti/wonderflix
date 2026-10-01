import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/features/player/player_chrome.dart';
import 'package:wonderflix/features/player/player_pill.dart';
import 'package:wonderflix/features/watch_party/party_notices.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/pump_app.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('testi e icone dei riscontri', () {
    String text(PlayerFeedback feedback) => playerFeedbackText(l, feedback);
    expect(text(const PlayFeedback(playing: true)), 'Riproduzione');
    expect(text(const PlayFeedback(playing: false)), 'In pausa');
    expect(
        text(const SeekFeedback(
            offset: Duration(seconds: 20),
            target: Duration(minutes: 18, seconds: 2))),
        '+20 s · 18:02');
    expect(
        text(const SeekFeedback(
            offset: Duration(seconds: -10),
            target: Duration(hours: 1, minutes: 2, seconds: 3))),
        '-10 s · 1:02:03');
    expect(text(const VolumeFeedback(volume: 70, muted: false)), 'Volume 70%');
    expect(text(const VolumeFeedback(volume: 70, muted: true)),
        'Audio disattivato');
    expect(text(const SubtitleDelayFeedback(Duration(milliseconds: 300))),
        'Sottotitoli +0,3 s');

    expect(playerFeedbackIcon(const PlayFeedback(playing: true)),
        LucideIcons.play);
    expect(playerFeedbackIcon(const PlayFeedback(playing: false)),
        LucideIcons.pause);
    expect(
        playerFeedbackIcon(const SeekFeedback(
            offset: Duration(seconds: -10), target: Duration.zero)),
        LucideIcons.rewind);
    expect(
        playerFeedbackIcon(const SeekFeedback(
            offset: Duration(seconds: 10), target: Duration.zero)),
        LucideIcons.fastForward);
    expect(playerFeedbackIcon(const VolumeFeedback(volume: 0, muted: false)),
        LucideIcons.volumeX);
    expect(playerFeedbackIcon(const VolumeFeedback(volume: 40, muted: true)),
        LucideIcons.volumeX);
    expect(playerFeedbackIcon(const VolumeFeedback(volume: 40, muted: false)),
        LucideIcons.volume2);
    expect(playerFeedbackIcon(const SubtitleDelayFeedback(Duration.zero)),
        LucideIcons.captions);
  });

  Future<ValueNotifier<(PlayerFeedback?, PartyNotice?)>> pumpPill(
      WidgetTester tester,
      {MotionLevel motion = MotionLevel.reduced}) async {
    final state = ValueNotifier<(PlayerFeedback?, PartyNotice?)>((null, null));
    addTearDown(state.dispose);
    await pumpApp(
      tester,
      Center(
        child: ValueListenableBuilder<(PlayerFeedback?, PartyNotice?)>(
          valueListenable: state,
          builder: (context, value, _) =>
              PlayerPill(feedback: value.$1, notice: value.$2),
        ),
      ),
      motion: motion,
    );
    return state;
  }

  testWidgets('avviso del party; il tasto lo copre; poi l\'avviso torna',
      (tester) async {
    final state = await pumpPill(tester);
    expect(find.byType(Text), findsNothing);

    const notice = PartyNotice(PartyNoticeKind.joined, name: 'Luigi');
    state.value = (null, notice);
    await tester.pumpAndSettle();
    expect(find.text('Luigi è nel watch party'), findsOneWidget);
    expect(find.byIcon(LucideIcons.userPlus), findsOneWidget);

    state.value = (const VolumeFeedback(volume: 70, muted: false), notice);
    await tester.pumpAndSettle();
    expect(find.text('Volume 70%'), findsOneWidget);
    expect(find.text('Luigi è nel watch party'), findsNothing);

    state.value = (null, notice);
    await tester.pumpAndSettle();
    expect(find.text('Luigi è nel watch party'), findsOneWidget);
  });

  testWidgets('senza contenuto sfuma, poi esce dall\'albero', (tester) async {
    final state = await pumpPill(tester);
    state.value = (const PlayFeedback(playing: false), null);
    await tester.pumpAndSettle();
    double opacity() => tester
        .widget<AnimatedOpacity>(find.byKey(const Key('player-pill')))
        .opacity;
    expect(opacity(), 1);

    state.value = (null, null);
    await tester.pump();
    expect(opacity(), 0);
    expect(find.text('In pausa'), findsOneWidget, reason: 'resta mentre sfuma');
    await tester.pumpAndSettle();
    expect(find.text('In pausa'), findsNothing);
  });

  testWidgets('tasto tenuto: la pillola cambia sul posto, senza sfumare',
      (tester) async {
    final state = await pumpPill(tester);
    state.value = (const VolumeFeedback(volume: 50, muted: false), null);
    await tester.pumpAndSettle();

    // Ripetizione del tasto: un nuovo valore ogni ~33 ms.
    for (var i = 1; i <= 10; i++) {
      state.value = (VolumeFeedback(volume: 50 + i * 5, muted: false), null);
      await tester.pump(const Duration(milliseconds: 33));
    }

    final pill = find.byKey(const Key('player-pill'));
    expect(find.descendant(of: pill, matching: find.byType(Text)),
        findsOneWidget);
    final newest = find.text('Volume 100%');
    expect(newest, findsOneWidget);
    final fades = find.ancestor(
        of: newest,
        matching: find.descendant(
            of: pill, matching: find.byType(FadeTransition)));
    expect(fades, findsWidgets);
    for (final fade in tester.widgetList<FadeTransition>(fades)) {
      expect(fade.opacity.value, 1);
    }

    // Un'altra specie di riscontro invece sfuma.
    state.value = (const PlayFeedback(playing: true), null);
    await tester.pump(const Duration(milliseconds: 33));
    expect(find.descendant(of: pill, matching: find.byType(Text)),
        findsNWidgets(2));
    await tester.pumpAndSettle();
  });

  testWidgets('animazioni complete: entra scendendo dall\'alto',
      (tester) async {
    final state = await pumpPill(tester, motion: MotionLevel.full);
    double shift() => tester
        .widget<AnimatedContainer>(find
            .descendant(
                of: find.byKey(const Key('player-pill')),
                matching: find.byType(AnimatedContainer))
            .first)
        .transform!
        .getTranslation()
        .y;
    expect(shift(), -PlayerPill.hiddenShift);
    state.value = (const PlayFeedback(playing: true), null);
    await tester.pump();
    expect(shift(), 0);
    await tester.pumpAndSettle();
  });
}
