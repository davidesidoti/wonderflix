import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Il tipo dell'ultimo evento del webhook di Seerr (spec J §9.6); uno
/// sconosciuto resta com'è.
String seerrEventLabel(AppLocalizations l, String type) => switch (type) {
      'MEDIA_PENDING' => l.adminSeerrEventPending,
      'MEDIA_AVAILABLE' => l.adminSeerrEventAvailable,
      'TEST_NOTIFICATION' => l.adminSeerrEventTest,
      _ => type,
    };

/// L'esito di "Prova collegamento".
String seerrTestLabel(AppLocalizations l, SeerrTestResult result) {
  if (result.ok) {
    final version = result.version;
    return version == null
        ? l.adminSeerrConnectedPlain
        : l.adminSeerrConnected(version);
  }
  return switch (result.error) {
    'NotConfigured' => l.adminSeerrNotConfiguredError,
    'SeerrAuth' => l.adminSeerrAuthError,
    _ => l.adminSeerrUnavailable,
  };
}

/// "3 titoli in attesa del prossimo riepilogo", "Nessun titolo in attesa",
/// oppure, con la raccolta spenta, "Le novità non vengono raccolte".
String newTitlesStatusLabel(AppLocalizations l, NewTitlesStatus status) =>
    !status.enabled
        ? l.adminNewTitlesOff
        : status.pending == 0
            ? l.adminNewTitlesNone
            : l.adminNewTitlesPending(status.pending);

/// "Inviati 3 titoli a 12 persone" (decisione 8 del piano 16b).
String newTitlesSentLabel(AppLocalizations l, NewTitlesSent sent) =>
    '${l.adminNewTitlesSentTitles(sent.titles)} '
    '${l.adminNewTitlesSentTo(sent.recipients)}';
