import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/admin/admin_navigation.dart';

void main() {
  test('scheda dall\'indirizzo: senza o sconosciuta, Sessioni', () {
    expect(AdminTab.parse('sessions'), AdminTab.sessions);
    expect(AdminTab.parse('users'), AdminTab.users);
    expect(AdminTab.parse('maintenance'), AdminTab.maintenance);
    expect(AdminTab.parse('activity'), AdminTab.activity);
    expect(AdminTab.parse('downloads'), AdminTab.downloads);
    expect(AdminTab.parse('space'), AdminTab.space);
    expect(AdminTab.parse('wonderflix'), AdminTab.wonderflix);
    expect(AdminTab.parse(null), AdminTab.sessions);
    expect(AdminTab.parse('boh'), AdminTab.sessions);
  });

  test('Utenti solo con i contatti del plugin, WonderFlix con la cassetta',
      () {
    expect(adminTabs(inbox: true, account: true, downloads: true, space: true),
        AdminTab.values);
    expect(adminTabs(inbox: true, account: false, downloads: false, space: false), [
      AdminTab.sessions,
      AdminTab.maintenance,
      AdminTab.activity,
      AdminTab.wonderflix,
    ]);
    expect(adminTabs(inbox: false, account: false, downloads: false, space: false),
        [AdminTab.sessions, AdminTab.maintenance, AdminTab.activity]);
  });

  test('Download solo con la funzione, dopo Registro', () {
    final without = adminTabs(inbox: true, account: true, downloads: false, space: false);
    expect(without, isNot(contains(AdminTab.downloads)));
    final tabs = adminTabs(inbox: true, account: true, downloads: true, space: true);
    expect(tabs.indexOf(AdminTab.downloads),
        tabs.indexOf(AdminTab.activity) + 1);
  });

  test('Spazio solo con la funzione, subito dopo Download', () {
    final without = adminTabs(
        inbox: true, account: true, downloads: true, space: false);
    expect(without, isNot(contains(AdminTab.space)));
    final tabs =
        adminTabs(inbox: true, account: true, downloads: true, space: true);
    expect(tabs.indexOf(AdminTab.space),
        tabs.indexOf(AdminTab.downloads) + 1);
  });
}
