import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/features/account/account_providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/language_preferences.dart';
import 'package:wonderflix/features/settings/settings_nav.dart';
import 'package:wonderflix/features/settings/settings_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/settings_fakes.dart';
import '../../support/test_data.dart';

Key _section(String id) => ValueKey('settings-section-$id');
Key _nav(String id) => ValueKey('settings-nav-$id');

const _onPrefix = 'settings-nav-on-';

/// Gli id delle voci accese (deve essere una sola).
List<String> _on(WidgetTester tester) => [
  for (final e
      in find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith(_onPrefix),
          )
          .evaluate())
    (e.widget.key! as ValueKey<String>).value.substring(_onPrefix.length),
];

ScrollableState _pageScroll(WidgetTester tester) => tester.state(
  find
      .descendant(
        of: find.byWidgetPredicate(
          (w) => w is SingleChildScrollView && w.controller != null,
        ),
        matching: find.byType(Scrollable),
      )
      .first,
);

/// Porta il titolo di una sezione in cima, di colpo.
Future<void> _jumpTo(WidgetTester tester, String id) async {
  await Scrollable.ensureVisible(tester.element(find.byKey(_section(id))));
  await tester.pump();
}

Future<void> _jumpToBottom(WidgetTester tester) async {
  final position = _pageScroll(tester).position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 700),
  String? section,
  bool tv = false,
  FakeDisplayPreferencesApi? displayPrefs,
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await pumpApp(
    tester,
    Scaffold(body: SettingsScreen(section: section)),
    surfaceSize: size,
    tv: tv,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      accountAvailableProvider.overrideWithValue(false),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
        () => FakeSessionController(const SessionSignedIn(testUser)),
      ),
      userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
      ...homeSettingsOverrides(prefs: displayPrefs),
    ],
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

void main() {
  testWidgets('largo: la colonna ha le voci visibili e la versione, niente '
      'fila e niente titolo grande nella pagina', (tester) async {
    await _pump(tester);
    expect(find.byType(SettingsRail), findsOneWidget);
    expect(find.byType(SettingsSectionStrip), findsNothing);
    expect(tester.getSize(find.byType(SettingsRail)).width, 208);
    // Notifiche senza push nel plugin non c'è, né nella colonna né nella pagina.
    for (final id in [
      'account',
      'home',
      'playback',
      'subtitles',
      'app',
      'discord',
      'support',
    ]) {
      expect(find.byKey(_nav(id)), findsOneWidget, reason: id);
    }
    expect(find.byKey(_nav('notifications')), findsNothing);
    expect(find.text('WonderFlix 0.0.1'), findsOneWidget);
    expect(find.text('Versione 0.0.1'), findsNothing);
    expect(
      find.text('IMPOSTAZIONI'),
      findsOneWidget,
      reason: 'solo il titolo della colonna',
    );
    expect(_on(tester), ['account']);
  });

  testWidgets('largo: un clic scorre alla sezione e la voce resta accesa '
      'mentre scorre', (tester) async {
    await _pump(tester);
    expect(_pageScroll(tester).position.pixels, 0);

    await tester.tap(find.byKey(_nav('app')));
    // Lo scorrimento passa davanti a Riproduzione e Sottotitoli: la voce
    // scelta non deve cambiare strada facendo.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      expect(_on(tester), ['app']);
    }
    await tester.pumpAndSettle();
    expect(_on(tester), ['app']);
    expect(_pageScroll(tester).position.pixels, greaterThan(0));
    expect(
      tester.getTopLeft(find.byKey(_section('app'))).dy,
      lessThan(700 / 3),
    );
  });

  testWidgets("scorrendo cambia la voce accesa; in fondo è l'ultima sezione", (
    tester,
  ) async {
    await _pump(tester);
    for (final id in ['home', 'subtitles', 'app']) {
      await _jumpTo(tester, id);
      expect(_on(tester), [id]);
    }
    await _jumpToBottom(tester);
    expect(_on(tester), ['support']);
    _pageScroll(tester).position.jumpTo(0);
    await tester.pump();
    expect(_on(tester), ['account']);
  });

  testWidgets('section=playback apre la pagina lì, con la voce accesa', (
    tester,
  ) async {
    await _pump(tester, section: 'playback');
    debugPrint(
      'DBG px=${_pageScroll(tester).position.pixels} max=${_pageScroll(tester).position.maxScrollExtent} top=${tester.getTopLeft(find.byKey(_section('playback'))).dy} acc=${tester.getTopLeft(find.byKey(_section('account'))).dy} home=${tester.getTopLeft(find.byKey(_section('home'))).dy}',
    );
    expect(_on(tester), ['playback']);
    expect(_pageScroll(tester).position.pixels, greaterThan(0));
    expect(
      tester.getTopLeft(find.byKey(_section('playback'))).dy,
      lessThan(700 / 3),
    );
  });

  testWidgets('section non visibile: pagina in cima', (tester) async {
    await _pump(tester, section: 'notifications');
    expect(_pageScroll(tester).position.pixels, 0);
    expect(_on(tester), ['account']);
  });

  testWidgets('stretto: la fila è fissa sopra la pagina, col titolo grande, '
      'e segue lo scorrimento', (tester) async {
    await _pump(tester, size: const Size(500, 800));
    expect(find.byType(SettingsSectionStrip), findsOneWidget);
    expect(find.byType(SettingsRail), findsNothing);
    expect(find.text('IMPOSTAZIONI'), findsOneWidget);
    expect(find.text('Versione 0.0.1'), findsOneWidget);
    final top = tester.getTopLeft(find.byType(SettingsSectionStrip));
    expect(_on(tester), ['account']);

    await tester.ensureVisible(find.byKey(_nav('subtitles')));
    await tester.tap(find.byKey(_nav('subtitles')));
    await tester.pumpAndSettle();
    expect(_on(tester), ['subtitles']);
    expect(_pageScroll(tester).position.pixels, greaterThan(0));
    expect(
      tester.getTopLeft(find.byType(SettingsSectionStrip)),
      top,
      reason: 'la fila non scorre con la pagina',
    );

    // In fondo: la voce accesa è l'ultima e la fila la porta in vista.
    await _jumpToBottom(tester);
    expect(_on(tester), ['support']);
    final chip = tester.getRect(find.byKey(_nav('support')));
    expect(chip.left, greaterThanOrEqualTo(0));
    expect(chip.right, lessThanOrEqualTo(500));
  });

  testWidgets('il cambio di larghezza non ricrea la pagina', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(_nav('app')));
    await tester.pumpAndSettle();
    expect(_pageScroll(tester).position.pixels, greaterThan(0));
    tester.view.physicalSize =
        const Size(900, 700) * tester.view.devicePixelRatio;
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSectionStrip), findsOneWidget);
    expect(_pageScroll(tester).position.pixels, greaterThan(0));
  });

  testWidgets('la versione sta in fondo alla colonna, e con poca altezza '
      'la colonna scorre', (tester) async {
    await _pump(tester);
    expect(
      tester.getBottomLeft(find.text('WonderFlix 0.0.1')).dy,
      closeTo(700 - 16, 8),
    );
    await _pump(tester, size: const Size(1440, 300));
    final rail = find.descendant(
      of: find.byType(SettingsRail),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(rail).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(
      tester.getBottomLeft(find.text('WonderFlix 0.0.1')).dy,
      lessThanOrEqualTo(300),
    );
  });

  testWidgets('section=: il titolo resta in cima mentre le sezioni sopra '
      'si caricano', (tester) async {
    final prefs = FakeDisplayPreferencesApi()..readGate = Completer<void>();
    await _pump(
      tester,
      section: 'playback',
      displayPrefs: prefs,
      settle: false,
    );
    final top = tester.getTopLeft(find.byKey(_section('playback'))).dy;
    expect(top, lessThan(700 / 3));
    prefs.readGate!.complete();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(_section('playback'))).dy,
      lessThan(700 / 3),
    );
    expect(_on(tester), ['playback']);
  });

  testWidgets('section=: uno scorrimento non da trascinamento libera il pin', (
    tester,
  ) async {
    await _pump(tester, section: 'playback');
    final position = _pageScroll(tester).position;
    // Come Tab, PageDown o il D-pad: nessuna UserScrollNotification.
    position.jumpTo(position.pixels + 400);
    await tester.pump();
    final moved = position.pixels;
    expect(_on(tester), isNot(['playback']), reason: 'la spia riparte');
    // Un cambio di altezza non riporta la pagina al titolo.
    tester.view.physicalSize =
        const Size(1440, 650) * tester.view.devicePixelRatio;
    await tester.pumpAndSettle();
    expect(position.pixels, moved);
  });

  testWidgets('TV: né colonna né fila', (tester) async {
    await _pump(tester, tv: true, size: const Size(1280, 720));
    expect(find.byType(SettingsRail), findsNothing);
    expect(find.byType(SettingsSectionStrip), findsNothing);
    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.text('0.0.1'), findsOneWidget);
  });
}
