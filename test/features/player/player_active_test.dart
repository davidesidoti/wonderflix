import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/player/player_active.dart';

void main() {
  test('conta le schermate del player aperte', () async {
    final c = ProviderContainer.test();
    final active = c.read(playerActiveProvider.notifier);
    expect(c.read(playerActiveProvider), isFalse);

    active.enter();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playerActiveProvider), isTrue);

    // Episodio successivo: la nuova schermata entra prima che la vecchia esca.
    active.enter();
    active.leave();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playerActiveProvider), isTrue);

    active.leave();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playerActiveProvider), isFalse);
  });
}
