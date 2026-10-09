import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/admin/admin_navigation.dart';

void main() {
  test('scheda dall\'indirizzo: senza o sconosciuta, Sessioni', () {
    expect(AdminTab.parse('sessions'), AdminTab.sessions);
    expect(AdminTab.parse('users'), AdminTab.users);
    expect(AdminTab.parse('maintenance'), AdminTab.maintenance);
    expect(AdminTab.parse('activity'), AdminTab.activity);
    expect(AdminTab.parse('wonderflix'), AdminTab.wonderflix);
    expect(AdminTab.parse(null), AdminTab.sessions);
    expect(AdminTab.parse('boh'), AdminTab.sessions);
  });

  test('Utenti solo con i contatti del plugin, WonderFlix con la cassetta',
      () {
    expect(adminTabs(inbox: true, account: true), AdminTab.values);
    expect(adminTabs(inbox: true, account: false), [
      AdminTab.sessions,
      AdminTab.maintenance,
      AdminTab.activity,
      AdminTab.wonderflix,
    ]);
    expect(adminTabs(inbox: false, account: false),
        [AdminTab.sessions, AdminTab.maintenance, AdminTab.activity]);
  });
}
