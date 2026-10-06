import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/wonderflix_tab.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

/// Come [FakePluginAdminApi], ma le azioni aspettano un [Completer] del
/// test: restano in corso finché non lo si completa.
class _GatedPluginAdminApi extends FakePluginAdminApi {
  Completer<void>? testGate;
  Completer<void>? sendGate;
  Completer<void>? writeGate;
  Completer<void>? announceGate;

  @override
  Future<int> announce(String text) async {
    final gate = announceGate;
    if (gate != null) await gate.future;
    return super.announce(text);
  }

  @override
  Future<void> setNotifyNewTitles(bool enabled) async {
    final gate = writeGate;
    if (gate != null) await gate.future;
    return super.setNotifyNewTitles(enabled);
  }

  @override
  Future<NewTitlesSent> sendNewTitles() async {
    final gate = sendGate;
    if (gate != null) await gate.future;
    return super.sendNewTitles();
  }

  @override
  Future<SeerrTestResult> testSeerr() async {
    final gate = testGate;
    if (gate != null) await gate.future;
    return super.testSeerr();
  }
}

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  late FakePluginAdminApi plugin;

  setUp(() => plugin = FakePluginAdminApi());

  Future<void> pumpTab(WidgetTester tester) async {
    await pumpApp(tester, const Scaffold(body: WonderflixTab()),
        overrides: adminTestOverrides(FakeAdminApi(), plugin: plugin),
        surfaceSize: const Size(1440, 1400));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String label) => tester
      .widget<OutlinedButton>(find.ancestor(
          of: find.text(label), matching: find.bySubtype<OutlinedButton>()))
      .onPressed != null;

  group('dopo aver lasciato la scheda', () {
    /// La scheda dentro un `Scaffold` che resta: [visible] la toglie, come un
    /// cambio di scheda della pagina.
    Future<void> pumpLeavable(
        WidgetTester tester, ValueNotifier<bool> visible) async {
      await pumpApp(
        tester,
        Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, show, _) =>
                show ? const WonderflixTab() : const SizedBox.shrink(),
          ),
        ),
        overrides: adminTestOverrides(FakeAdminApi(), plugin: plugin),
        surfaceSize: const Size(1440, 1400),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('interruttore: l\'errore non compare più', (tester) async {
      final gated = _GatedPluginAdminApi()
        ..actionError = const ServerUnreachableException();
      plugin = gated;
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await pumpLeavable(tester, visible);
      final gate = gated.writeGate = Completer<void>();

      await tester.tap(find.byKey(const Key('notify-new-titles')));
      await tester.pump();
      visible.value = false;
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();

      expect(gated.calls, contains('notify:false'));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('annuncio rifiutato (400): l\'avviso non compare più',
        (tester) async {
      final gated = _GatedPluginAdminApi()
        ..actionError = const ServerErrorException(400);
      plugin = gated;
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await pumpLeavable(tester, visible);
      final gate = gated.announceGate = Completer<void>();

      await tester.enterText(find.byKey(const Key('announcement-text')), 'Ciao');
      await tester.pump();
      await tester.tap(find.text('Invia a tutti'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Invia'));
      await tester.pumpAndSettle();
      visible.value = false;
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();

      expect(gated.calls, contains('announce:Ciao'));
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('annuncio', () {
    testWidgets('si scrive, si conferma, arriva', (tester) async {
      await pumpTab(tester);

      expect(find.text('Annuncio'), findsOneWidget);
      expect(find.text('0/500'), findsOneWidget);
      expect(enabled(tester, 'Invia a tutti'), isFalse);

      await tester.enterText(
          find.byKey(const Key('announcement-text')), '  Ciao a tutti  ');
      await tester.pump();
      expect(enabled(tester, 'Invia a tutti'), isTrue);

      await tester.tap(find.text('Invia a tutti'));
      await tester.pumpAndSettle();
      expect(find.text(it.adminAnnouncementConfirm), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Invia'));
      await tester.pumpAndSettle();

      expect(plugin.calls, contains('announce:Ciao a tutti'));
      expect(find.text('Annuncio inviato a 12 persone'), findsOneWidget);
      expect(find.text('Ciao a tutti'), findsNothing, reason: 'campo vuoto');
    });

    testWidgets('solo spazi: Invia a tutti resta spento', (tester) async {
      await pumpTab(tester);

      await tester.enterText(find.byKey(const Key('announcement-text')), '    ');
      await tester.pump();

      expect(enabled(tester, 'Invia a tutti'), isFalse);
    });

    testWidgets('la card da sola tiene vivo il suo controller: dopo '
        'l\'annuncio rilegge', (tester) async {
      await pumpApp(
          tester,
          const Scaffold(body: SingleChildScrollView(child: AnnouncementCard())),
          overrides: adminTestOverrides(FakeAdminApi(), plugin: plugin));
      await tester.pumpAndSettle();
      expect(plugin.count('newTitles'), 1, reason: 'letto all\'apertura');

      await tester.enterText(find.byKey(const Key('announcement-text')), 'Ciao');
      await tester.pump();
      await tester.tap(find.text('Invia a tutti'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Invia'));
      await tester.pumpAndSettle();

      expect(plugin.calls, contains('announce:Ciao'));
      expect(plugin.count('newTitles'), 2, reason: 'riletto dopo l\'annuncio');
    });

    testWidgets('Annulla: niente annuncio', (tester) async {
      await pumpTab(tester);
      await tester.enterText(find.byKey(const Key('announcement-text')), 'Ciao');
      await tester.pump();

      await tester.tap(find.text('Invia a tutti'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(plugin.calls.where((c) => c.startsWith('announce')), isEmpty);
    });

    testWidgets('testo rifiutato (400): "Testo non valido"', (tester) async {
      plugin.actionError = const ServerErrorException(400);
      await pumpTab(tester);
      await tester.enterText(find.byKey(const Key('announcement-text')), 'Ciao');
      await tester.pump();

      await tester.tap(find.text('Invia a tutti'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Invia'));
      await tester.pumpAndSettle();

      expect(find.text('Testo non valido'), findsOneWidget);
    });
  });

  group('novità', () {
    testWidgets('stato, interruttore e Invia ora', (tester) async {
      await pumpTab(tester);

      expect(find.text('3 titoli in attesa del prossimo riepilogo'),
          findsOneWidget);
      expect(enabled(tester, 'Invia ora'), isTrue);

      await tester.tap(find.text('Invia ora'));
      await tester.pumpAndSettle();
      expect(find.text('Inviati 3 titoli a 12 persone'), findsOneWidget);

      await tester.tap(find.byKey(const Key('notify-new-titles')));
      await tester.pumpAndSettle();
      expect(plugin.calls, contains('notify:false'));
      expect(find.text('Le novità non vengono raccolte'), findsOneWidget);
      expect(enabled(tester, 'Invia ora'), isFalse);
    });

    testWidgets('scrittura fallita: l\'interruttore torna com\'era',
        (tester) async {
      plugin.actionError = const ServerUnreachableException();
      await pumpTab(tester);

      await tester.tap(find.byKey(const Key('notify-new-titles')));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byKey(const Key('notify-new-titles'))).value,
          isTrue);
      expect(find.text(it.errorServerUnreachable), findsOneWidget);
    });

    testWidgets('"Invia ora" in corso: "Dati non aggiornati" non smonta il '
        'pulsante', (tester) async {
      final gated = _GatedPluginAdminApi();
      plugin = gated;
      await pumpTab(tester);
      final gate = gated.sendGate = Completer<void>();

      await tester.tap(find.text('Invia ora'));
      await tester.pump();
      expect(enabled(tester, 'Invia ora'), isFalse);

      gated.newTitlesError = const ServerUnreachableException();
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(find.textContaining('Dati non aggiornati'), findsOneWidget);
      expect(enabled(tester, 'Invia ora'), isFalse);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Inviati 3 titoli a 12 persone'), findsOneWidget);
    });

    testWidgets('scrittura riuscita e rilettura fallita: l\'interruttore '
        'resta sul valore scritto', (tester) async {
      await pumpTab(tester);

      plugin.newTitlesError = const ServerUnreachableException();
      await tester.tap(find.byKey(const Key('notify-new-titles')));
      await tester.pumpAndSettle();

      expect(plugin.calls, contains('notify:false'));
      expect(tester.widget<Switch>(find.byKey(const Key('notify-new-titles'))).value,
          isFalse);
      expect(find.text('Le novità non vengono raccolte'), findsOneWidget);
      expect(find.textContaining('Dati non aggiornati'), findsOneWidget);
    });

    testWidgets('nessun titolo: Invia ora spento', (tester) async {
      plugin.newTitlesValue = const NewTitlesStatus(enabled: true, pending: 0);
      await pumpTab(tester);

      expect(find.text('Nessun titolo in attesa'), findsOneWidget);
      expect(enabled(tester, 'Invia ora'), isFalse);
    });

    testWidgets('errore delle novità: le altre card funzionano', (tester) async {
      plugin.newTitlesError = const ServerUnreachableException();
      await pumpTab(tester);

      expect(find.text('Riprova'), findsOneWidget);
      expect(find.text('Prova collegamento'), findsOneWidget);
    });
  });

  group('Seerr', () {
    testWidgets('configurato: ultimo evento e prova', (tester) async {
      await pumpTab(tester);

      expect(find.textContaining('Richiesta in attesa'), findsOneWidget);
      await tester.tap(find.text('Prova collegamento'));
      await tester.pumpAndSettle();
      expect(find.text('Collegato a Seerr 3.4.1'), findsOneWidget);

      plugin.testValue = const SeerrTestResult(ok: false, error: 'SeerrAuth');
      await tester.tap(find.text('Prova collegamento'));
      await tester.pumpAndSettle();
      expect(find.text('Seerr ha rifiutato la chiave'), findsOneWidget);
    });

    testWidgets('lettura fallita con i dati di prima: "Dati non aggiornati"',
        (tester) async {
      await pumpTab(tester);
      expect(find.textContaining('Dati non aggiornati'), findsNothing);

      plugin.seerrError = const ServerUnreachableException();
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();

      expect(find.textContaining('Dati non aggiornati'), findsOneWidget);
      expect(find.text('Prova collegamento'), findsOneWidget,
          reason: 'i dati di prima restano');
    });

    testWidgets('prova in corso: "Dati non aggiornati" non smonta la card',
        (tester) async {
      final gated = _GatedPluginAdminApi();
      plugin = gated;
      await pumpTab(tester);
      final gate = gated.testGate = Completer<void>();

      await tester.tap(find.text('Prova collegamento'));
      await tester.pump();
      expect(enabled(tester, 'Prova collegamento'), isFalse,
          reason: 'la prova è in corso');

      gated.seerrError = const ServerUnreachableException();
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(find.textContaining('Dati non aggiornati'), findsOneWidget);
      expect(enabled(tester, 'Prova collegamento'), isFalse,
          reason: 'la riga in più non rifà il contenuto della card');

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Collegato a Seerr 3.4.1'), findsOneWidget,
          reason: 'l\'esito arriva alla card di prima');
    });

    testWidgets('nessun evento', (tester) async {
      plugin.seerrValue = const SeerrAdminStatus(configured: true);
      await pumpTab(tester);

      expect(find.text('Nessun evento ricevuto'), findsOneWidget);
    });

    testWidgets('non configurato', (tester) async {
      plugin.seerrValue = const SeerrAdminStatus(configured: false);
      await pumpTab(tester);

      expect(find.text(it.adminSeerrNotConfigured), findsOneWidget);
      expect(find.text('Prova collegamento'), findsNothing);
    });

    testWidgets('plugin più vecchio della 1.4.0: niente card', (tester) async {
      plugin.seerrValue = null;
      await pumpTab(tester);

      expect(find.text('Seerr'), findsNothing);
      expect(find.text('Annuncio'), findsOneWidget);
    });
  });
}
