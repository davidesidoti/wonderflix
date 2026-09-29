import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/window_setup.dart';

void main() {
  test('codifica e decodifica i bordi della finestra', () {
    const rect = Rect.fromLTWH(10, 20, 1280, 800);
    expect(parseBounds(encodeBounds(rect)), rect);
  });

  test('valori non validi o troppo piccoli vengono ignorati', () {
    expect(parseBounds(null), isNull);
    expect(parseBounds('a,b,c,d'), isNull);
    expect(parseBounds('0,0,100,100'), isNull);
  });

  group('isVisibleOnAnyDisplay', () {
    const display = Rect.fromLTWH(0, 0, 1920, 1080);

    test('finestra interamente dentro un display', () {
      expect(
        isVisibleOnAnyDisplay(
            const Rect.fromLTWH(100, 100, 800, 600), [display]),
        isTrue,
      );
    });

    test('finestra parzialmente dentro, con almeno 100x100 px visibili', () {
      expect(
        isVisibleOnAnyDisplay(
            const Rect.fromLTWH(1800, 100, 800, 600), [display]),
        isTrue,
      );
    });

    test('finestra completamente fuori da ogni display', () {
      expect(
        isVisibleOnAnyDisplay(
            const Rect.fromLTWH(3000, 3000, 800, 600), [display]),
        isFalse,
      );
    });

    test('solo una sottile fetta visibile: non basta', () {
      expect(
        isVisibleOnAnyDisplay(
            const Rect.fromLTWH(1910, 100, 800, 600), [display]),
        isFalse,
      );
    });
  });
}
