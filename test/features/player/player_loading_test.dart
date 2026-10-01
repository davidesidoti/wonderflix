import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/player/player_loading.dart';
import 'package:wonderflix/ui/backdrop_image.dart';

import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  group('caricamento', () {
    Future<ValueNotifier<(JellyfinItem?, bool)>> pumpLoading(
        WidgetTester tester, {VoidCallback? onBack}) async {
      final state = ValueNotifier<(JellyfinItem?, bool)>((null, true));
      addTearDown(state.dispose);
      // `Scaffold`: la freccia (`IconButton`) vuole un `Material` sopra.
      await pumpApp(
        tester,
        Scaffold(
          body: ValueListenableBuilder<(JellyfinItem?, bool)>(
            valueListenable: state,
            builder: (context, value, _) => PlayerLoadingLayer(
              item: value.$1,
              visible: value.$2,
              onBack: onBack ?? () {},
            ),
          ),
        ),
      );
      return state;
    }

    testWidgets('prima dell\'elemento: solo la linea e la freccia',
        (tester) async {
      var back = 0;
      await pumpLoading(tester, onBack: () => back++);
      expect(find.byType(LoadingLine), findsOneWidget);
      expect(find.byType(BackdropImage), findsNothing);
      await tester.tap(find.byTooltip('Indietro'));
      expect(back, 1);
    });

    testWidgets('con l\'elemento: sfondo e titolo (senza logo)',
        (tester) async {
      final state = await pumpLoading(tester);
      state.value = (testItem(name: 'Dune'), true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(BackdropImage), findsOneWidget);
      expect(find.text('DUNE'), findsOneWidget);
      expect(find.byType(LoadingLine), findsOneWidget);
    });

    testWidgets('con il logo non c\'è il titolo', (tester) async {
      final state = await pumpLoading(tester);
      state.value = (
        JellyfinItem.fromJson({
          'Id': 'm1',
          'Name': 'Dune',
          'Type': 'Movie',
          'ImageTags': {'Primary': 'p', 'Logo': 'l'},
          'BackdropImageTags': ['b'],
        }),
        true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('DUNE'), findsNothing);
    });

    testWidgets('nascosto: sfuma e poi esce dall\'albero', (tester) async {
      final state = await pumpLoading(tester);
      state.value = (testItem(name: 'Dune'), false);
      await tester.pump();
      expect(find.byType(LoadingLine), findsOneWidget,
          reason: 'resta mentre sfuma');
      await tester.pump(const Duration(milliseconds: 200));
      // `onEnd` arriva a dissolvenza finita, poi serve una build.
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('player-loading')), findsNothing);
      expect(find.byType(LoadingLine), findsNothing);

      // Di nuovo in caricamento ("Riprova"): torna.
      state.value = (testItem(name: 'Dune'), true);
      await tester.pump();
      expect(find.byType(LoadingLine), findsOneWidget);
    });

    // Opacità dello strato in questo istante (la prima `Opacity` sotto la
    // chiave).
    double layerOpacity(WidgetTester tester) => tester
        .widget<Opacity>(find
            .descendant(
                of: find.byKey(const Key('player-loading')),
                matching: find.byType(Opacity))
            .first)
        .opacity;

    testWidgets('rientra con una dissolvenza; la prima volta è subito intero',
        (tester) async {
      final state = await pumpLoading(tester);
      expect(layerOpacity(tester), 1, reason: 'primo ingresso: nessuna entrata');

      state.value = (testItem(name: 'Dune'), false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('player-loading')), findsNothing);

      // Di nuovo in caricamento ("Riprova"): sfuma in entrata.
      state.value = (testItem(name: 'Dune'), true);
      await tester.pump();
      expect(layerOpacity(tester), lessThan(1));
      await tester.pump(WfMotion.fast);
      await tester.pump();
      expect(layerOpacity(tester), 1);
    });

    testWidgets('la linea non si sposta quando arriva l\'elemento',
        (tester) async {
      final state = await pumpLoading(tester);
      final before = tester.getTopLeft(find.byType(LoadingLine));

      // Prima il titolo (senza logo)...
      state.value = (testItem(name: 'Dune'), true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('DUNE'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(LoadingLine)), before);

      // ...poi un altro elemento, con il logo.
      state.value = (
        JellyfinItem.fromJson({
          'Id': 'm2',
          'Name': 'Arrival',
          'Type': 'Movie',
          'ImageTags': {'Primary': 'p', 'Logo': 'l'},
          'BackdropImageTags': ['b'],
        }),
        true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getTopLeft(find.byType(LoadingLine)), before);
    });

    testWidgets('la linea ha un suo strato di disegno', (tester) async {
      await pumpLoading(tester);
      expect(
          find.descendant(
              of: find.byType(LoadingLine),
              matching: find.byType(RepaintBoundary)),
          findsOneWidget);
    });

    testWidgets('montato già nascosto: non entra nell\'albero', (tester) async {
      // Come dopo "Riprova" con il primo fotogramma già arrivato: senza
      // dissolvenza non c'è `onEnd`, e la linea girerebbe per sempre.
      final visible = ValueNotifier(false);
      addTearDown(visible.dispose);
      await pumpApp(
        tester,
        Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, value, _) => PlayerLoadingLayer(
                item: testItem(name: 'Dune'), visible: value, onBack: () {}),
          ),
        ),
      );
      expect(find.byType(LoadingLine), findsNothing);
      expect(find.byKey(const Key('player-loading')), findsNothing);

      visible.value = true;
      await tester.pump();
      expect(find.byType(LoadingLine), findsOneWidget);
    });
  });

  group('spinner del buffering', () {
    testWidgets('solo oltre 300 ms; sfuma via', (tester) async {
      final buffering = ValueNotifier(false);
      addTearDown(buffering.dispose);
      await pumpApp(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: buffering,
          builder: (context, value, _) => BufferingSpinner(buffering: value),
        ),
      );
      buffering.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      buffering.value = false;
      await tester.pump();
      await tester.pump(bufferingSpinnerDelay);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'attesa breve: niente spinner');

      buffering.value = true;
      await tester.pump();
      await tester.pump(bufferingSpinnerDelay);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      buffering.value = false;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('errore', () {
    testWidgets('sullo sfondo del titolo: testi e pulsanti', (tester) async {
      var retry = 0;
      var back = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: PlayerErrorLayer(
            item: testItem(name: 'Dune'),
            error: null,
            onRetry: () => retry++,
            onBack: () => back++,
            backLabel: 'Torna indietro',
          ),
        ),
      );
      expect(find.byType(BackdropImage), findsOneWidget);
      expect(find.text('Impossibile riprodurre il video'), findsOneWidget);
      await tester.tap(find.text('Riprova'));
      await tester.tap(find.text('Torna indietro'));
      expect((retry, back), (1, 1));
    });

    testWidgets('senza elemento: niente sfondo', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: PlayerErrorLayer(
            item: null,
            error: null,
            onRetry: () {},
            onBack: () {},
            backLabel: 'Torna indietro',
          ),
        ),
      );
      expect(find.byType(BackdropImage), findsNothing);
      expect(find.text('Riprova'), findsOneWidget);
    });
  });
}
