import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/features/account/account_providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/language_preferences.dart';
import 'package:wonderflix/features/settings/settings_nav.dart';
import 'package:wonderflix/features/settings/settings_screen.dart';
import 'package:wonderflix/features/settings/subtitle_preview.dart';
import 'package:wonderflix/features/settings/tv_settings_body.dart';
import 'package:wonderflix/features/update/update_controller.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/settings_fakes.dart';
import '../../support/test_data.dart';
import '../../support/update_fakes.dart';

late FakeUserConfigApi _api;
late FakeUpdateController _update;

Future<void> _pump(
  WidgetTester tester, {
  UpdateState update = const UpdateState(),
  bool tv = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  _update = FakeUpdateController(update);
  await pumpApp(
    tester,
    const Scaffold(body: SettingsScreen()),
    tv: tv,
    surfaceSize: const Size(960, 540),
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      accountAvailableProvider.overrideWithValue(false),
      clientInfoProvider.overrideWithValue(testClientInfo),
      sessionControllerProvider.overrideWith(
        () => FakeSessionController(const SessionSignedIn(testUser)),
      ),
      userConfigApiProvider.overrideWithValue(_api),
      ...homeSettingsOverrides(),
      updateControllerProvider.overrideWith(() => _update),
    ],
  );
  await tester.pumpAndSettle();
}

Finder _row(String id) => find.byKey(ValueKey('tv-settings-$id'));

/// La riga [id] ha il focus.
bool _focused(WidgetTester tester, String id) => Focus.of(
  tester.element(
    find.descendant(of: _row(id), matching: find.byType(Container)).first,
  ),
).hasPrimaryFocus;

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _focus(WidgetTester tester, String id) async {
  Focus.of(
    tester.element(
      find.descendant(of: _row(id), matching: find.byType(Container)).first,
    ),
  ).requestFocus();
  await tester.pumpAndSettle();
}

/// Il valore mostrato a destra nella riga [id].
bool _shows(String id, String text) => find
    .descendant(of: _row(id), matching: find.text(text))
    .evaluate()
    .isNotEmpty;

/// Indietro del telecomando: il pop di sistema (il `goBack` lo ignoriamo).
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _api = FakeUserConfigApi());

  testWidgets('solo il corpo della TV; Su e Giù restano nell\'elenco', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(TvSettingsBody), findsOneWidget);
    expect(find.byType(SettingsRail), findsNothing);
    // Niente decodifica hardware, niente sezioni del PC.
    expect(find.text('Decodifica hardware'), findsNothing);
    expect(find.text('Animazioni'), findsNothing);
    expect(find.text('Account'), findsNothing);
    // Il focus parte dalla prima riga.
    expect(_focused(tester, 'app-language'), isTrue);
    await _key(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(tester, 'app-language'), isTrue);

    const order = [
      'quality',
      'autoplay-next',
      'auto-skip-intro',
      'audio-language',
      'subtitle-language',
      'subtitle-mode',
      'subtitle-size',
      'version',
    ];
    for (final id in order) {
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(_focused(tester, id), isTrue, reason: id);
    }
    // In fondo resta sulla versione, visibile.
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(tester, 'version'), isTrue);
    expect(_shows('version', '0.0.1'), isTrue);
    expect(tester.getRect(_row('version')).bottom, lessThanOrEqualTo(540));
    // A destra il nome, la spiegazione e il dove si salva della riga.
    expect(
      find.text('La versione di WonderFlix installata su questa TV.'),
      findsOneWidget,
    );
  });

  testWidgets('a destra spiegazione e dove si salva', (tester) async {
    await _pump(tester);
    await _focus(tester, 'quality');
    expect(find.text('Qualità dello streaming'), findsNWidgets(2));
    expect(find.textContaining('Massima manda il file'), findsOneWidget);
    expect(find.text('Vale solo su questa TV'), findsOneWidget);
    await _focus(tester, 'audio-language');
    expect(
      find.text('Salvate sul tuo account: valgono in tutti i client Jellyfin'),
      findsOneWidget,
    );
    expect(find.byType(SubtitlePreview), findsNothing);
    await _focus(tester, 'subtitle-size');
    expect(find.text('Vale solo su questa TV'), findsOneWidget);
    expect(find.byType(SubtitlePreview), findsOneWidget);
  });

  testWidgets('OK cambia un interruttore', (tester) async {
    await _pump(tester);
    await _focus(tester, 'autoplay-next');
    final before = tester
        .widget<Switch>(
          find.descendant(
            of: _row('autoplay-next'),
            matching: find.byType(Switch),
          ),
        )
        .value;
    await _key(tester, LogicalKeyboardKey.select);
    final after = tester
        .widget<Switch>(
          find.descendant(
            of: _row('autoplay-next'),
            matching: find.byType(Switch),
          ),
        )
        .value;
    expect(after, !before);
    expect(_focused(tester, 'autoplay-next'), isTrue);
  });

  testWidgets('pannello: Giù e OK cambia e chiude, il focus torna alla riga', (
    tester,
  ) async {
    await _pump(tester);
    await _focus(tester, 'quality');
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.text('Indietro per chiudere'), findsOneWidget);
    // Il focus parte dalla scelta attuale, col pallino.
    expect(
      Focus.of(
        tester.element(find.byKey(const Key('tv-choice-current'))),
      ).hasPrimaryFocus,
      isTrue,
    );
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.text('Indietro per chiudere'), findsNothing);
    expect(_shows('quality', 'Alta (20 Mbps)'), isTrue);
    expect(_focused(tester, 'quality'), isTrue);
  });

  testWidgets('pannello: Indietro chiude senza cambiare', (tester) async {
    await _pump(tester);
    await _focus(tester, 'quality');
    await _key(tester, LogicalKeyboardKey.select);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _back(tester);
    expect(find.text('Indietro per chiudere'), findsNothing);
    expect(_shows('quality', 'Massima (originale)'), isTrue);
    expect(_focused(tester, 'quality'), isTrue);
  });

  testWidgets('lingua dei sottotitoli: si salva sul server', (tester) async {
    await _pump(tester);
    await _focus(tester, 'subtitle-language');
    expect(_shows('subtitle-language', 'Qualsiasi'), isTrue);
    await _key(tester, LogicalKeyboardKey.select);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.select);
    expect(_api.saved.single.$2['SubtitleLanguagePreference'], 'ita');
    expect(_shows('subtitle-language', 'Italiano'), isTrue);
  });

  testWidgets('dimensione: l\'anteprima riempie lo schermo e segue il focus', (
    tester,
  ) async {
    await _pump(tester);
    await _focus(tester, 'subtitle-size');
    expect(_shows('subtitle-size', 'Normali'), isTrue);
    await _key(tester, LogicalKeyboardKey.select);
    final preview = find.byType(SubtitlePreview).last;
    expect(tester.getSize(preview).width, 960 - 300);
    final scale = tester.widget<SubtitlePreview>(preview).scale;
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(
      tester.widget<SubtitlePreview>(find.byType(SubtitlePreview).last).scale,
      greaterThan(scale),
    );
    // Indietro: la dimensione non cambia.
    await _back(tester);
    expect(_shows('subtitle-size', 'Normali'), isTrue);
    expect(_focused(tester, 'subtitle-size'), isTrue);
  });

  testWidgets('aggiornamento pronto: prima riga in oro, OK installa', (
    tester,
  ) async {
    await _pump(
      tester,
      update: UpdateState(
        release: testRelease(),
        installer: File('WonderFlix-TV-0.2.0.apk'),
      ),
    );
    expect(_focused(tester, 'update'), isTrue);
    expect(_shows('update', 'Aggiorna'), isTrue);
    await _key(tester, LogicalKeyboardKey.select);
    expect(_update.installs, 1);
  });

  testWidgets('aggiornamento in download: la percentuale; permesso a destra', (
    tester,
  ) async {
    await _pump(
      tester,
      update: UpdateState(
        release: testRelease(),
        progress: 0.4,
        installPermissionNeeded: true,
      ),
    );
    expect(_shows('update', '40%'), isTrue);
    expect(find.textContaining('Si sta scaricando'), findsOneWidget);
    expect(find.textContaining('Premi OK'), findsNothing);
    expect(find.textContaining('Installa app sconosciute'), findsOneWidget);
    await _key(tester, LogicalKeyboardKey.select);
    expect(_update.installs, 0);
  });

  testWidgets('lingue non caricate: una riga che con OK rilegge', (
    tester,
  ) async {
    _api.loadError = Exception('giù');
    await _pump(tester);
    expect(find.text('Non caricate, riprova'), findsOneWidget);
    expect(find.text('Lingua dell\'audio'), findsNothing);
    _api.loadError = null;
    await _focus(tester, 'audio-language');
    await _key(tester, LogicalKeyboardKey.select);
    expect(find.text('Non caricate, riprova'), findsNothing);
    expect(_shows('audio-language', 'Italiano'), isTrue);
    expect(_focused(tester, 'audio-language'), isTrue);
  });

  testWidgets('fuori dalla TV niente corpo della TV', (tester) async {
    await _pump(tester, tv: false);
    expect(find.byType(TvSettingsBody), findsNothing);
    // A 960 la pagina del PC è nello stretto: la fila delle sezioni.
    expect(find.byType(SettingsSectionStrip), findsOneWidget);
  });
}
