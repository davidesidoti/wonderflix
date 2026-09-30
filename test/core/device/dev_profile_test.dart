import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/device/dev_profile.dart';

void main() {
  test('devProfile legge e valida la variabile', () {
    expect(devProfile({}), isNull);
    expect(devProfile({'WONDERFLIX_PROFILE': ''}), isNull);
    expect(devProfile({'WONDERFLIX_PROFILE': '  '}), isNull);
    expect(devProfile({'WONDERFLIX_PROFILE': ' B '}), 'b');
    expect(devProfile({'WONDERFLIX_PROFILE': 'luigi2'}), 'luigi2');
    expect(devProfile({'WONDERFLIX_PROFILE': '../x'}), isNull);
    expect(devProfile({'WONDERFLIX_PROFILE': 'a' * 17}), isNull);
  });

  test('nomi per profilo', () {
    expect(prefsPrefixFor(null), 'flutter.');
    expect(prefsPrefixFor('b'), 'flutter.b.');
    expect(sessionKeyFor(null), 'wonderflix.session');
    expect(sessionKeyFor('b'), 'wonderflix.session.b');
    expect(logsFolderFor(null), 'logs');
    expect(logsFolderFor('b'), 'logs-b');
  });
}
