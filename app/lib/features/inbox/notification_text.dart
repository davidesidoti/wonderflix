import 'package:flutter/widgets.dart' show StringCharacters;

import '../../core/social/inbox_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Titolo, testo e rotta di una voce, come la push del plugin (spec V §4.3).
class NotificationText {
  const NotificationText({
    required this.title,
    required this.body,
    required this.route,
  });

  final String title;
  final String body;

  /// Una rotta di GoRouter, senza `#`.
  final String route;
}

/// Come il tetto del plugin (`NotificationCatalog.MaxBodyLength`).
const _maxBodyLength = 200;

/// I testi e le rotte di tutte le voci, identici al catalogo del plugin
/// (`NotificationCatalog.cs`): un campo mancante vale vuoto, il testo oltre
/// 200 caratteri si taglia a 199 più "…".
NotificationText notificationTextOf(InboxEntry entry, AppLocalizations l) {
  final text = _build(entry, l);
  final body = text.body.characters;
  if (body.length <= _maxBodyLength) return text;
  return NotificationText(
      title: text.title,
      body: '${body.take(_maxBodyLength - 1)}…',
      route: text.route);
}

NotificationText _build(InboxEntry entry, AppLocalizations l) {
  NotificationText text(String title, String body, String route) =>
      NotificationText(title: title, body: body, route: route);
  const admin = '/admin?tab=';
  return switch (entry) {
    InviteEntry() => text(l.notifInviteTitle(entry.fromName), entry.title,
        '/inbox'),
    AnnouncementEntry() =>
      text(l.notifAnnouncementTitle, entry.text, '/inbox'),
    NewTitlesEntry() => text(
        l.notifNewTitlesTitle,
        // I primi 3 nomi, prima i film poi le serie.
        [...entry.movies.map((m) => m.name), ...entry.series.map((s) => s.name)]
            .take(3)
            .join(', '),
        '/home'),
    RequestAvailableEntry() => text(
        l.notifRequestAvailableTitle,
        entry.title,
        _itemRoute(entry.itemId, '/requests')),
    RequestApprovedEntry() =>
      text(l.notifRequestApprovedTitle, entry.title, '/requests'),
    RequestDeclinedEntry() =>
      text(l.notifRequestDeclinedTitle, entry.title, '/requests'),
    ContactReminderEntry() => text(l.notifContactReminderTitle,
        l.notifContactReminderBody, '/settings'),
    RecommendationEntry() => text(
        l.notifRecommendationTitle(entry.fromName),
        entry.title,
        _itemRoute(entry.itemId, '/inbox')),
    MatchInviteEntry() => text(
        l.notifMatchInviteTitle(entry.fromName),
        l.notifMatchInviteBody,
        entry.roomId.isEmpty ? '/inbox' : '/match/${entry.roomId}'),
    ReportResolvedEntry() =>
      text(l.notifReportResolvedTitle, entry.title, '/inbox'),
    RequestPendingEntry() => text(
        l.notifRequestPendingTitle,
        l.notifRequestPendingBody(entry.title, entry.requesterName),
        '/requests'),
    ReportPendingEntry() => text(
        l.notifReportPendingTitle,
        l.notifReportPendingBody(entry.title, entry.fromName),
        '${admin}wonderflix'),
    DownloadNeedsYouEntry() => text(
        l.notifDownloadNeedsYouTitle,
        l.notifDownloadNeedsYouBody(entry.title, _downloadReason(entry, l)),
        '${admin}downloads'),
    DownloadStalledEntry() => text(l.notifDownloadStalledTitle,
        l.notifDownloadStalledBody(entry.title), '${admin}downloads'),
    LightenBlockedEntry() => text(l.notifLightenBlockedTitle,
        l.notifLightenBlockedBody(entry.title), '${admin}space'),
    SpaceOperationFailedEntry() => text(
        l.notifSpaceFailedTitle, l.notifSpaceFailedBody, '${admin}space'),
    DiskAlmostFullEntry() => text(l.notifDiskFullTitle,
        l.notifDiskFullBody(entry.percent?.toString() ?? ''), '${admin}space'),
    RecoveryStartedEntry() => text(l.notifRecoveryStartedTitle,
        entry.userName ?? '', '${admin}users'),
    RecoveryBlockedEntry() => text(
        l.notifRecoveryBlockedTitle,
        entry.everyone
            ? l.notifRecoveryBlockedEveryone
            : l.notifRecoveryBlockedUser(entry.userName ?? ''),
        '${admin}users'),
    RestartPendingEntry() =>
      text(l.notifRestartPendingTitle, l.notifRestartPendingBody, '/admin'),
  };
}

/// La pagina del titolo, o [fallback] se la voce non ne ha una.
String _itemRoute(String? itemId, String fallback) =>
    itemId == null || itemId.isEmpty ? fallback : '/item/$itemId';

/// Un motivo che l'app non conosce esce com'è.
String _downloadReason(DownloadNeedsYouEntry entry, AppLocalizations l) =>
    switch (entry.reason) {
      'NothingFound' => l.notifReasonNothingFound,
      'BelowMinScore' => l.notifReasonBelowMinScore,
      'GrabRefused' => l.notifReasonGrabRefused,
      'SearchFailed' => l.notifReasonSearchFailed,
      'ImportBlocked' => l.notifReasonImportBlocked,
      final String other => other,
      null => '',
    };
