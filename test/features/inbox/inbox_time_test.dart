import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wonderflix/features/inbox/inbox_time.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  test('ora relativa delle voci', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    final now = DateTime(2026, 10, 3, 20, 30);
    String label(DateTime at, [AppLocalizations? l]) =>
        inboxTimeLabel(at, now, l ?? it);

    expect(label(now.subtract(const Duration(seconds: 30))), 'adesso');
    expect(label(now.add(const Duration(seconds: 30))), 'adesso',
        reason: 'un orologio un po\' avanti sul server');
    expect(label(now.subtract(const Duration(minutes: 5))), '5 min fa');
    expect(label(now.subtract(const Duration(hours: 2))), '2 h fa');
    expect(label(DateTime(2026, 10, 2, 23)), 'ieri');
    expect(label(DateTime(2026, 10, 2, 8)), 'ieri');
    expect(label(DateTime(2026, 9, 30, 12)), '3 giorni fa');
    expect(label(DateTime(2026, 9, 27, 12)), '6 giorni fa');
    expect(label(DateTime(2026, 9, 26, 12)), '26 set');
    expect(label(DateTime(2026, 9, 26, 12), en), 'Sep 26');
    expect(label(now.subtract(const Duration(minutes: 5)), en), '5 min ago');
    // Poco dopo mezzanotte una voce di poco prima resta in minuti.
    expect(
        inboxTimeLabel(
            DateTime(2026, 10, 2, 23, 50), DateTime(2026, 10, 3, 0, 10), it),
        '20 min fa');
  });

  test('createdAt in UTC (come lo manda il plugin) e now locale', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final now = DateTime(2026, 10, 3, 20, 30);
    // Gli stessi istanti di sopra, ma in UTC: l'ora relativa e i giorni di
    // calendario (nel fuso locale) non cambiano, qualunque sia il fuso della
    // macchina.
    String label(DateTime local) =>
        inboxTimeLabel(local.toUtc(), now, it);

    expect(label(now.subtract(const Duration(seconds: 30))), 'adesso');
    expect(label(now.subtract(const Duration(minutes: 5))), '5 min fa');
    expect(label(now.subtract(const Duration(hours: 2))), '2 h fa');
    expect(label(DateTime(2026, 10, 2, 23)), 'ieri');
    expect(label(DateTime(2026, 10, 2, 8)), 'ieri');
    expect(label(DateTime(2026, 9, 30, 12)), '3 giorni fa');
    expect(label(DateTime(2026, 9, 26, 12)), '26 set');
    expect(
        inboxTimeLabel(DateTime(2026, 10, 2, 23, 50).toUtc(),
            DateTime(2026, 10, 3, 0, 10), it),
        '20 min fa');
  });
}
