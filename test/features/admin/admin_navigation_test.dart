import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/admin/admin_navigation.dart';

void main() {
  test('scheda dall\'indirizzo: senza o sconosciuta, Sessioni', () {
    expect(AdminTab.parse('sessions'), AdminTab.sessions);
    expect(AdminTab.parse(null), AdminTab.sessions);
    expect(AdminTab.parse('boh'), AdminTab.sessions);
  });
}
