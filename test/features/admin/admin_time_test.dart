import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/features/admin/admin_time.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  test('ore della pagina Amministrazione', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    final now = DateTime(2026, 10, 6, 9, 30);
    String label(DateTime at, [AppLocalizations? l]) =>
        adminTimeLabel(at, now, l ?? it);

    expect(label(now.subtract(const Duration(seconds: 20))), 'adesso');
    expect(label(now.add(const Duration(seconds: 20))), 'adesso',
        reason: 'un orologio un po\' avanti sul server');
    expect(label(now.subtract(const Duration(minutes: 3))), '3 min fa');
    expect(label(DateTime(2026, 10, 6, 7, 10)), '2 h fa');
    expect(label(DateTime(2026, 10, 5, 22, 53)), '5 ott, 22:53');
    expect(label(DateTime(2026, 10, 5, 22, 53), en), 'Oct 5, 22:53');
    // Poco dopo mezzanotte una voce di poco prima resta in minuti.
    expect(adminTimeLabel(DateTime(2026, 10, 5, 23, 50),
            DateTime(2026, 10, 6, 0, 10), it),
        '20 min fa');

    expect(adminClockLabel(DateTime(2026, 10, 6, 12, 3), it), '12:03');

    expect(adminDurationLabel(it, const Duration(seconds: 45)), '45 s');
    expect(adminDurationLabel(it, const Duration(minutes: 3, seconds: 20)),
        '3 min');
    expect(adminDurationLabel(it, const Duration(hours: 1, minutes: 5)),
        '1 h 5 min');
    expect(adminFullDateTime(DateTime(2026, 10, 6, 8, 10, 3), it),
        '6 ott 2026, 08:10:03');
  });
}
