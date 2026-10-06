import '../jellyfin/json_fields.dart';

/// La casella delle novità e quanti titoli aspettano (`Inbox/NewTitles`).
class NewTitlesStatus {
  const NewTitlesStatus({required this.enabled, required this.pending});

  factory NewTitlesStatus.fromJson(Map<String, dynamic> json) =>
      NewTitlesStatus(
        enabled: json['Enabled'] == true,
        pending: jsonInt(json, 'Pending') ?? 0,
      );

  final bool enabled;
  final int pending;
}

/// Esito di "Invia ora" (`Inbox/NewTitles/Send`).
class NewTitlesSent {
  const NewTitlesSent({required this.titles, required this.recipients});

  factory NewTitlesSent.fromJson(Map<String, dynamic> json) => NewTitlesSent(
        titles: jsonInt(json, 'Titles') ?? 0,
        recipients: jsonInt(json, 'Recipients') ?? 0,
      );

  final int titles;
  final int recipients;
}

/// Seerr nel plugin (`Requests/Admin`): configurato e ultimo evento del
/// webhook.
class SeerrAdminStatus {
  const SeerrAdminStatus({
    required this.configured,
    this.lastEventAt,
    this.lastEventType,
  });

  factory SeerrAdminStatus.fromJson(Map<String, dynamic> json) =>
      SeerrAdminStatus(
        configured: json['Configured'] == true,
        lastEventAt: jsonDate(json, 'LastEventAt'),
        lastEventType: jsonString(json, 'LastEventType'),
      );

  final bool configured;
  final DateTime? lastEventAt;

  /// Il `notification_type` di Seerr ("MEDIA_PENDING", "MEDIA_AVAILABLE",
  /// "TEST_NOTIFICATION"…).
  final String? lastEventType;
}

/// Esito di "Prova collegamento" (`Requests/Test`).
class SeerrTestResult {
  const SeerrTestResult({required this.ok, this.version, this.error});

  factory SeerrTestResult.fromJson(Map<String, dynamic> json) =>
      SeerrTestResult(
        ok: json['Ok'] == true,
        version: jsonString(json, 'Version'),
        error: jsonString(json, 'Error'),
      );

  final bool ok;
  final String? version;

  /// "NotConfigured", "SeerrAuth" o "SeerrUnavailable".
  final String? error;
}
