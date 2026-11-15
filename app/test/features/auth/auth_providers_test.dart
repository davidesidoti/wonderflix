import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/features/auth/auth_providers.dart';

class _MockAuthApi extends Mock implements AuthApi {}

void main() {
  Future<bool> enabled(Future<bool> Function() answer) {
    final api = _MockAuthApi();
    when(api.quickConnectEnabled).thenAnswer((_) => answer());
    final container =
        ProviderContainer(overrides: [authApiProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    return container.read(quickConnectEnabledProvider.future);
  }

  test('spento sul server: niente scheda', () async {
    expect(await enabled(() async => false), isFalse);
  });

  test('controllo fallito: la scheda resta, col suo errore', () async {
    expect(await enabled(() async => throw const ServerUnreachableException()), isTrue);
  });
}
