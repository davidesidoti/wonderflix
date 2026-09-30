import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/ui/staggered_entrance.dart';

void main() {
  test('staggerInterval: ritardo, passo e durata in frazioni del totale', () {
    const delay = Duration(milliseconds: 100);
    const step = Duration(milliseconds: 50);
    const item = Duration(milliseconds: 300);
    final total = staggerTotal(count: 3, delay: delay, stagger: step, item: item);
    expect(total, const Duration(milliseconds: 500));
    final first = staggerInterval(index: 0, delay: delay, stagger: step, item: item, total: total);
    expect(first.begin, closeTo(0.2, 1e-9));
    expect(first.end, closeTo(0.8, 1e-9));
    final last = staggerInterval(index: 2, delay: delay, stagger: step, item: item, total: total);
    expect(last.begin, closeTo(0.4, 1e-9));
    expect(last.end, closeTo(1.0, 1e-9));
  });

  Widget group(MotionLevel level, {bool play = true, VoidCallback? onPlayed}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: WfMotionScope(
          motion: WfMotion(level),
          child: StaggerGroup(
            count: 3,
            play: play,
            onPlayed: onPlayed,
            child: Column(children: [
              for (var i = 0; i < 4; i++)
                StaggerItem(index: i, child: Text('riga $i')),
            ]),
          ),
        ),
      );

  double opacityOf(WidgetTester tester, String text) {
    final fades = tester.widgetList<Opacity>(
        find.ancestor(of: find.text(text), matching: find.byType(Opacity)));
    return fades.isEmpty ? 1 : fades.first.opacity;
  }

  testWidgets('completa: entrano uno dopo l\'altro, poi tutti visibili',
      (tester) async {
    var played = 0;
    await tester.pumpWidget(group(MotionLevel.full, onPlayed: () => played++));
    expect(opacityOf(tester, 'riga 0'), 0);
    await tester.pump(WfMotion.stagger + const Duration(milliseconds: 100));
    expect(opacityOf(tester, 'riga 0'), greaterThan(opacityOf(tester, 'riga 2')));
    // Oltre `count`: nessuna entrata.
    expect(opacityOf(tester, 'riga 3'), 1);
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      expect(opacityOf(tester, 'riga $i'), 1);
    }
    expect(played, 1);
  });

  testWidgets('ridotta o play spento: subito visibili', (tester) async {
    await tester.pumpWidget(group(MotionLevel.reduced));
    expect(opacityOf(tester, 'riga 0'), 1);
    await tester.pumpWidget(group(MotionLevel.full, play: false));
    expect(opacityOf(tester, 'riga 0'), 1);
  });

  testWidgets('si decide alla prima costruzione: poi completa non riparte',
      (tester) async {
    await tester.pumpWidget(group(MotionLevel.reduced));
    await tester.pumpWidget(group(MotionLevel.full));
    expect(opacityOf(tester, 'riga 0'), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('StaggerItem senza gruppo: il solo figlio', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: StaggerItem(index: 0, child: Text('solo')),
    ));
    expect(opacityOf(tester, 'solo'), 1);
  });

  /// Gruppo esterno di due righe; nella riga 1, se [inner], un gruppo
  /// annidato con una card.
  Widget nestedPage({bool inner = true, bool outerPlay = true}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: WfMotionScope(
          motion: const WfMotion(MotionLevel.full),
          child: StaggerGroup(
            count: 2,
            play: outerPlay,
            child: Column(children: [
              const StaggerItem(index: 0, child: Text('riga 0')),
              StaggerItem(
                index: 1,
                child: inner
                    ? const StaggerGroup(
                        count: 1,
                        nested: true,
                        child: StaggerItem(
                            index: 0,
                            effect: EntranceEffect.fly,
                            child: Text('card')),
                      )
                    : const SizedBox(),
              ),
            ]),
          ),
        ),
      );

  double flyX(WidgetTester tester) => tester
      .widget<Transform>(find
          .ancestor(of: find.text('card'), matching: find.byType(Transform))
          .first)
      .transform
      .getTranslation()
      .x;

  testWidgets('annidato: parte quando parte il suo elemento', (tester) async {
    await tester.pumpWidget(nestedPage());
    // La riga 1 parte dopo un passo: fino ad allora la card è ferma a destra.
    await tester.pump(WfMotion.stagger - const Duration(milliseconds: 10));
    expect(flyX(tester), 40);
    await tester.pump(const Duration(milliseconds: 60));
    expect(flyX(tester), inExclusiveRange(0, 40));
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'card'), 1);
  });

  testWidgets('annidato: elemento già entrato, niente entrata',
      (tester) async {
    final inner = ValueNotifier(false);
    addTearDown(inner.dispose);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
      valueListenable: inner,
      builder: (context, value, _) => nestedPage(inner: value),
    ));
    await tester.pumpAndSettle();
    // La riga si ricostruisce più tardi (scorrendo, dati nuovi).
    inner.value = true;
    await tester.pump();
    expect(find.text('card'), findsOneWidget);
    // Solo l'Opacity della riga (già a 1): la card non ha un'entrata sua.
    expect(find.ancestor(of: find.text('card'), matching: find.byType(Opacity)),
        findsOneWidget);
    expect(opacityOf(tester, 'card'), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('annidato: gruppo esterno spento o assente, niente entrata',
      (tester) async {
    await tester.pumpWidget(nestedPage(outerPlay: false));
    expect(find.ancestor(of: find.text('card'), matching: find.byType(Opacity)),
        findsNothing);
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: WfMotionScope(
        motion: WfMotion(MotionLevel.full),
        child: StaggerGroup(
          count: 1,
          nested: true,
          child: StaggerItem(index: 0, child: Text('card')),
        ),
      ),
    ));
    expect(find.ancestor(of: find.text('card'), matching: find.byType(Opacity)),
        findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('fly: parte da destra e più piccolo', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: WfMotionScope(
        motion: WfMotion(MotionLevel.full),
        child: StaggerGroup(
          count: 1,
          child: StaggerItem(
              index: 0, effect: EntranceEffect.fly, child: Text('card')),
        ),
      ),
    ));
    final transform = tester.widget<Transform>(find
        .ancestor(of: find.text('card'), matching: find.byType(Transform))
        .first);
    expect(transform.transform.getTranslation().x, greaterThan(0));
    await tester.pumpAndSettle();
  });
}
