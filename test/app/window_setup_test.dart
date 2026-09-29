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
}
