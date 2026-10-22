import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/social/home_models.dart';
import '../home/home_providers.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';
import 'calendar_logic.dart';

final _log = Logger('calendar');

/// Il plugin ha il calendario delle uscite (plugin 1.13.0).
final calendarAvailableProvider = Provider<bool>(
  (ref) => ref.watch(socialAvailabilityProvider.select((f) => f.calendar)),
);

/// Il calendario è sparito: funzioni note e senza `calendar`. Come
/// `requestsGoneProvider`, non vale finché le funzioni non sono note.
final calendarGoneProvider = Provider<bool>(
  (ref) => ref.watch(
    socialAvailabilityProvider.select((f) => f.known && !f.calendar),
  ),
);

/// Le uscite della griglia di un mese. Si rilegge quando la pagina si
/// riapre o cambia mese (`autoDispose`), mai da sola.
final calendarPageProvider = FutureProvider.autoDispose
    .family<CalendarPage, DateTime>((ref, month) async {
      // Prima il cancello, poi l'utente: tutti i watch prima dell'attesa.
      if (!ref.watch(calendarAvailableProvider)) return const CalendarPage();
      ref.watch(currentUserIdProvider);
      final period = calendarPeriod(month);
      final page = await ref
          .watch(homeApiProvider)
          .calendar(period.start, period.end);
      _logError('serie', page.seriesError);
      _logError('film', page.moviesError);
      return page;
    });

void _logError(String what, UpcomingError? error) {
  if (error != null) _log.info('$what del calendario non disponibili: ${error.wire}');
}
