import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/admin/admin_navigation.dart';

void main() {
  test('scheda dall\'indirizzo: senza o sconosciuta, Sessioni', () {
    expect(AdminTab.parse('sessions'), AdminTab.sessions);
    expect(AdminTab.parse('maintenance'), AdminTab.maintenance);
    expect(AdminTab.parse('activity'), AdminTab.activity);
    expect(AdminTab.parse('wonderflix'), AdminTab.wonderflix);
    expect(AdminTab.parse(null), AdminTab.sessions);
    expect(AdminTab.parse('boh'), AdminTab.sessions);
  });

  test('WonderFlix solo con la cassetta del plugin', () {
    expect(adminTabs(inbox: true), AdminTab.values);
    expect(adminTabs(inbox: false),
        [AdminTab.sessions, AdminTab.maintenance, AdminTab.activity]);
  });
}
