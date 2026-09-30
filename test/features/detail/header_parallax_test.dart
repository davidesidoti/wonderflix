import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/detail/detail_header.dart';
import 'package:wonderflix/features/detail/header_parallax.dart';

void main() {
  test('in cima: tutto fermo', () {
    final p = headerParallax(0, reduced: false);
    expect(p.backdropShift, 0);
    expect(p.backdropScale, 1);
    expect(p.dim, 0);
    expect(p.textOpacity, 1);
    expect(p.textShift, 0);
    expect(p.visibleHeight, detailHeaderHeight);
  });

  test('a metà: sfondo a metà velocità, zoom e scurimento parziali', () {
    const offset = detailHeaderHeight / 2;
    final p = headerParallax(offset, reduced: false);
    expect(p.backdropShift, -offset / 2);
    expect(p.backdropScale, closeTo(1.04, 1e-9));
    expect(p.dim, closeTo(0.25, 1e-9));
    expect(p.textOpacity, closeTo(0.2, 1e-9));
    expect(p.textShift, closeTo(-offset * 0.15, 1e-9));
    expect(p.visibleHeight, detailHeaderHeight - offset);
  });

  test('oltre la testata: limiti', () {
    final p = headerParallax(2000, reduced: false);
    expect(p.backdropScale, closeTo(1.08, 1e-9));
    expect(p.dim, closeTo(0.5, 1e-9));
    expect(p.textOpacity, 0);
    expect(p.visibleHeight, 0);
  });

  test('ridotte: lo sfondo segue lo scroll, niente effetti', () {
    final p = headerParallax(200, reduced: true);
    expect(p.backdropShift, -200);
    expect(p.backdropScale, 1);
    expect(p.dim, 0);
    expect(p.textOpacity, 1);
    expect(p.textShift, 0);
    expect(p.visibleHeight, detailHeaderHeight - 200);
  });

  test('scroll negativo (rimbalzo): come in cima', () {
    expect(headerParallax(-30, reduced: false).backdropShift, 0);
  });
}
