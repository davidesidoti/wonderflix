import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/platform_startup.dart';

void main() {
  test('usa il nome scelto dall\'utente nelle impostazioni', () {
    expect(tvDeviceNameFrom('Fire TV Stick di davide', 'AFTMA08C15'),
        'Fire TV Stick di davide');
  });

  test('senza nome ripiega sul modello', () {
    expect(tvDeviceNameFrom(null, 'AFTMA08C15'), 'AFTMA08C15');
    expect(tvDeviceNameFrom('  ', 'X'), 'X');
  });
}
