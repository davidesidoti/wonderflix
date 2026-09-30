import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/ui/card_preview.dart';

void main() {
  const overlay = Size(1440, 900);

  test('previewRect: centrata sulla card, larga 1,8 volte', () {
    const card = Rect.fromLTWH(600, 300, 200, 300);
    final r = previewRect(card: card, overlay: overlay);
    expect(r.width, 360);
    expect(r.height, 360 * 9 / 16 + previewBodyHeight);
    expect(r.center.dx, card.center.dx);
    expect(r.center.dy, card.center.dy);
  });

  test('previewRect: minimo 300 di larghezza', () {
    final r = previewRect(card: const Rect.fromLTWH(600, 300, 100, 150), overlay: overlay);
    expect(r.width, previewMinWidth);
  });

  test('previewRect: vicino ai bordi resta dentro con 16 px di margine', () {
    final left = previewRect(card: const Rect.fromLTWH(0, 300, 160, 240), overlay: overlay);
    expect(left.left, previewMargin);
    final right = previewRect(card: const Rect.fromLTWH(1380, 300, 160, 240), overlay: overlay);
    expect(right.right, overlay.width - previewMargin);
    final top = previewRect(card: const Rect.fromLTWH(600, -100, 160, 240), overlay: overlay);
    expect(top.top, previewMargin);
    final bottom = previewRect(card: const Rect.fromLTWH(600, 850, 160, 240), overlay: overlay);
    expect(bottom.bottom, overlay.height - previewMargin);
  });

  test('controller: una sola aperta, e catena subito dopo la chiusura', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final previews = container.read(cardPreviewProvider.notifier);
      final a = Object();
      final b = Object();
      expect(previews.opensImmediately(), isFalse);
      previews.open(a);
      expect(container.read(cardPreviewProvider).openId, a);
      expect(previews.opensImmediately(), isTrue);
      previews.open(b);
      expect(container.read(cardPreviewProvider).openId, b);
      // Chiudere un'anteprima non aperta non cambia nulla.
      previews.close(a);
      expect(container.read(cardPreviewProvider).openId, b);
      previews.close(b);
      expect(container.read(cardPreviewProvider).openId, isNull);
      expect(previews.opensImmediately(), isTrue);
      async.elapse(previewChainWindow + const Duration(milliseconds: 1));
      expect(previews.opensImmediately(), isFalse);
    }, initialTime: DateTime(2026, 9, 30));
  });
}
