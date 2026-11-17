import '../../l10n/gen/app_localizations.dart';
import '../requests/request_labels.dart';

/// Il titolo di una voce delle richieste, con le stagioni se ci sono:
/// "Brothers (2026), stagioni 1–2". Senza titolo da Seerr, "Titolo non
/// disponibile".
String inboxRequestTitle(AppLocalizations l, String title, List<int> seasons) {
  final name = title.isEmpty ? l.requestsUnknownTitle : title;
  return seasons.isEmpty
      ? name
      : l.inboxRequestTitleSeasons(name, seasons.length, formatSeasonList(seasons));
}

/// "Garg ha chiesto Dune (2021)". Senza il nome di chi ha chiesto (Seerr può
/// mandarlo vuoto) la frase non regge: "Nuova richiesta: Dune (2021)".
String inboxRequestPendingText(AppLocalizations l, String requesterName,
    String title, List<int> seasons) {
  final name = requesterName.trim();
  final shown = inboxRequestTitle(l, title, seasons);
  return name.isEmpty
      ? l.inboxRequestPendingNoName(shown)
      : l.inboxRequestPending(name, shown);
}
