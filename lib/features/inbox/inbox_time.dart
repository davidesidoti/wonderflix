import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';

/// Fino a quanti giorni fa l'ora si dice in giorni; dopo, la data.
const inboxDaysShown = 6;

/// Ora relativa di una voce della cassetta (spec G §7.6): "adesso" (meno di
/// un minuto, anche nel futuro se l'orologio del server è avanti), "5 min
/// fa", "2 h fa" (stesso giorno), "ieri", "3 giorni fa" (fino a
/// [inboxDaysShown]), poi la data breve nella lingua dell'app.
String inboxTimeLabel(DateTime createdAt, DateTime now, AppLocalizations l) {
  final elapsed = now.difference(createdAt);
  if (elapsed < const Duration(minutes: 1)) return l.inboxNow;
  if (elapsed < const Duration(hours: 1)) {
    return l.inboxMinutesAgo(elapsed.inMinutes);
  }
  final local = createdAt.toLocal();
  final days = _calendarDays(local, now.toLocal());
  if (days <= 0) return l.inboxHoursAgo(elapsed.inHours);
  if (days == 1) return l.inboxYesterday;
  if (days <= inboxDaysShown) return l.inboxDaysAgo(days);
  return DateFormat.MMMd(l.localeName).format(local);
}

/// Giorni di calendario tra le due date (locali), senza l'effetto dell'ora
/// legale.
int _calendarDays(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;
