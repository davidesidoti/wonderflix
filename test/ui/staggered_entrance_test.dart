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
