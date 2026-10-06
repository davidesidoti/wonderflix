import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';

/// Ora di una voce della pagina Amministrazione (spec J §9.5): "adesso"
/// (meno di un minuto, anche nel futuro se l'orologio del server è avanti),
/// "5 min fa" (meno di un'ora), "2 h fa" (stesso giorno); prima, data e ora
/// nella lingua dell'app ("5 ott, 22:53").
String adminTimeLabel(DateTime at, DateTime now, AppLocalizations l) {
  final elapsed = now.difference(at);
  if (elapsed < const Duration(minutes: 1)) return l.inboxNow;
  if (elapsed < const Duration(hours: 1)) {
    return l.inboxMinutesAgo(elapsed.inMinutes);
  }
  final local = at.toLocal();
  final today = now.toLocal();
  if (local.year == today.year &&
      local.month == today.month &&
      local.day == today.day) {
    return l.inboxHoursAgo(elapsed.inHours);
  }
  return '${DateFormat.MMMd(l.localeName).format(local)}, '
      '${DateFormat.Hm(l.localeName).format(local)}';
}

/// "12:03": l'ora dell'ultimo aggiornamento riuscito.
String adminClockLabel(DateTime at, AppLocalizations l) =>
    DateFormat.Hm(l.localeName).format(at.toLocal());

/// "45 s", "3 min", "1 h 5 min": quanto è durata un'attività. Una durata
/// negativa (l'orologio del server era indietro) vale zero.
String adminDurationLabel(AppLocalizations l, Duration duration) {
  final value = duration.isNegative ? Duration.zero : duration;
  if (value < const Duration(minutes: 1)) {
    return l.adminDurationSeconds(value.inSeconds);
  }
  if (value < const Duration(hours: 1)) {
    return l.adminDurationMinutes(value.inMinutes);
  }
  return l.adminDurationHours(value.inHours, value.inMinutes.remainder(60));
}

/// "6 ott 2026, 08:10:03": data e ora complete, al passaggio del mouse nel
/// Registro (spec J §9.5).
String adminFullDateTime(DateTime at, AppLocalizations l) {
  final local = at.toLocal();
  return '${DateFormat.yMMMd(l.localeName).format(local)}, '
      '${DateFormat.Hms(l.localeName).format(local)}';
}
