import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/ui/ticket_shape.dart';

void main() {
  const size = Size(200, 100);

  test('verticalClipperCutsNotchesTopAndBottom', () {
    final path = const TicketClipper.vertical(120).getClip(size);

    expect(path.contains(const Offset(120, 3)), isFalse);
    expect(path.contains(const Offset(120, 97)), isFalse);
    expect(path.contains(const Offset(120, 50)), isTrue);
    expect(path.contains(const Offset(3, 50)), isTrue);
  });

  test('horizontalClipperCutsNotchesLeftAndRight', () {
    final path = const TicketClipper.horizontal(60).getClip(size);

    expect(path.contains(const Offset(3, 60)), isFalse);
    expect(path.contains(const Offset(197, 60)), isFalse);
    expect(path.contains(const Offset(100, 60)), isTrue);
    expect(path.contains(const Offset(3, 20)), isTrue);
  });
}
