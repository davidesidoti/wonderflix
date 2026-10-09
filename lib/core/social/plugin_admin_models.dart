import '../jellyfin/api_exception.dart';
import '../jellyfin/json_fields.dart';
import 'account_models.dart';

/// Un campo obbligatorio di una risposta del plugin: senza il valore giusto
/// la risposta non è quella attesa. Meglio un errore che un "0 titoli" o un
/// "spento" inventati.
T _required<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! T) throw const ServerErrorException(null);
  return value;
}

/// La casella delle novità e quanti titoli aspettano (`Inbox/NewTitles`).
class NewTitlesStatus {
  const NewTitlesStatus({required this.enabled, required this.pending});

  /// `Enabled` (booleano) e `Pending` (intero) ci devono essere.
  factory NewTitlesStatus.fromJson(Map<String, dynamic> json) =>
      NewTitlesStatus(
        enabled: _required<bool>(json, 'Enabled'),
        pending: _required<int>(json, 'Pending'),
      );

  final bool enabled;
  final int pending;
}

/// Esito di "Invia ora" (`Inbox/NewTitles/Send`).
class NewTitlesSent {
  const NewTitlesSent({required this.titles, required this.recipients});

  /// `Titles` e `Recipients` (interi) ci devono essere.
  factory NewTitlesSent.fromJson(Map<String, dynamic> json) => NewTitlesSent(
        titles: _required<int>(json, 'Titles'),
        recipients: _required<int>(json, 'Recipients'),
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

  /// `Configured` (booleano) ci deve essere; il resto è facoltativo.
  factory SeerrAdminStatus.fromJson(Map<String, dynamic> json) =>
      SeerrAdminStatus(
        configured: _required<bool>(json, 'Configured'),
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

  /// `Ok` (booleano) ci deve essere; il resto è facoltativo.
  factory SeerrTestResult.fromJson(Map<String, dynamic> json) =>
      SeerrTestResult(
        ok: _required<bool>(json, 'Ok'),
        version: jsonString(json, 'Version'),
        error: jsonString(json, 'Error'),
      );

  final bool ok;
  final String? version;

  /// "NotConfigured", "SeerrAuth" o "SeerrUnavailable".
  final String? error;
}

/// Un utente nell'elenco del recupero (`Account/Admin/Users`, spec L §7.6).
class AdminAccountUser {
  const AdminAccountUser({
    required this.id,
    required this.name,
    required this.isAdmin,
    required this.enabled,
    this.discordName,
    this.maskedEmail,
    this.lastReminderAt,
  });

  /// `Id`, `Name`, `IsAdmin` ed `Enabled` ci devono essere; i contatti e
  /// l'ultimo promemoria no.
  factory AdminAccountUser.fromJson(Map<String, dynamic> json) =>
      AdminAccountUser(
        id: _required<String>(json, 'Id'),
        name: _required<String>(json, 'Name'),
        isAdmin: _required<bool>(json, 'IsAdmin'),
        enabled: _required<bool>(json, 'Enabled'),
        discordName: jsonString(
            jsonMap(json['Discord']) ?? const <String, dynamic>{}, 'Name'),
        maskedEmail: jsonString(
            jsonMap(json['Email']) ?? const <String, dynamic>{}, 'Masked'),
        lastReminderAt: jsonDate(json, 'LastReminderAt'),
      );

  /// Nel formato `N` di Jellyfin.
  final String id;
  final String name;
  final bool isAdmin;
  final bool enabled;

  /// Il nome utente Discord collegato; `null` se non c'è.
  final String? discordName;

  /// L'email collegata, mascherata dal plugin ("m•••@example.com"); `null`
  /// se non c'è.
  final String? maskedEmail;

  final DateTime? lastReminderAt;

  bool get hasContacts => discordName != null || maskedEmail != null;
}

/// L'ultimo errore d'invio di un canale.
class AccountSendError {
  const AccountSendError({required this.at, required this.code});

  /// `At` e `Code` ci devono essere.
  factory AccountSendError.fromJson(Map<String, dynamic> json) {
    final at = jsonDate(json, 'At');
    if (at == null) throw const ServerErrorException(null);
    return AccountSendError(at: at, code: _required<String>(json, 'Code'));
  }

  final DateTime at;

  /// `DmClosed`, `SendFailed` o `Invalid`.
  final String code;
}

/// Un canale del recupero: configurato, e l'ultimo errore d'invio.
class AccountChannelStatus {
  const AccountChannelStatus({required this.configured, this.lastError});

  /// `Configured` ci deve essere.
  factory AccountChannelStatus.fromJson(Map<String, dynamic> json) {
    final error = jsonMap(json['LastError']);
    return AccountChannelStatus(
      configured: _required<bool>(json, 'Configured'),
      lastError: error == null ? null : AccountSendError.fromJson(error),
    );
  }

  final bool configured;
  final AccountSendError? lastError;
}

/// Lo stato del recupero (`Account/Admin/Status`, spec L §7.6).
class AccountAdminStatus {
  const AccountAdminStatus({
    required this.discord,
    required this.email,
    required this.withContacts,
    required this.users,
    required this.reminderDays,
  });

  /// Tutti i campi ci devono essere.
  factory AccountAdminStatus.fromJson(Map<String, dynamic> json) {
    final discord = jsonMap(json['Discord']);
    final email = jsonMap(json['Email']);
    if (discord == null || email == null) {
      throw const ServerErrorException(null);
    }
    return AccountAdminStatus(
      discord: AccountChannelStatus.fromJson(discord),
      email: AccountChannelStatus.fromJson(email),
      withContacts: _required<int>(json, 'WithContacts'),
      users: _required<int>(json, 'Users'),
      reminderDays: _required<int>(json, 'ReminderDays'),
    );
  }

  final AccountChannelStatus discord;
  final AccountChannelStatus email;

  /// Utenti attivi e non admin con almeno un contatto raggiungibile.
  final int withContacts;

  /// Utenti attivi e non admin.
  final int users;

  /// Ogni quanti giorni il promemoria; 0: spento.
  final int reminderDays;

  AccountChannelStatus channel(AccountChannel channel) => switch (channel) {
        AccountChannel.discord => discord,
        AccountChannel.email => email,
      };
}

/// L'esito di "Invia prova a me" per canale: un `AccountTestCodes` del
/// plugin (`Ok`, `NotConfigured`, `NoContact`, `Invalid`, `DmClosed`,
/// `SendFailed`…).
class AccountTestResult {
  const AccountTestResult({required this.discord, required this.email});

  /// `Discord` ed `Email` ci devono essere.
  factory AccountTestResult.fromJson(Map<String, dynamic> json) =>
      AccountTestResult(
        discord: _required<String>(json, 'Discord'),
        email: _required<String>(json, 'Email'),
      );

  final String discord;
  final String email;

  String of(AccountChannel channel) => switch (channel) {
        AccountChannel.discord => discord,
        AccountChannel.email => email,
      };
}
