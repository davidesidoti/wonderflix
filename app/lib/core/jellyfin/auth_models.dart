/// Cosa può fare l'utente con i watch party (`Policy.SyncPlayAccess`, spec B
/// §5.9). Il server lo controlla comunque: qui decide cosa mostrare.
enum SyncPlayAccess {
  createAndJoin,
  joinOnly,
  none;

  bool get canCreate => this == createAndJoin;

  bool get canJoin => this != none;
}

/// Valore sconosciuto o assente: accesso completo (decide il server).
SyncPlayAccess _syncPlayAccess(Object? policy) {
  final value =
      policy is Map<String, dynamic> ? policy['SyncPlayAccess'] : null;
  return switch (value) {
    'JoinGroups' => SyncPlayAccess.joinOnly,
    'None' => SyncPlayAccess.none,
    _ => SyncPlayAccess.createAndJoin,
  };
}

/// L'utente è amministratore di Jellyfin (`Policy.IsAdministrator`, spec J
/// §7): solo con un `true` vero.
bool _isAdministrator(Object? policy) =>
    policy is Map<String, dynamic> && policy['IsAdministrator'] == true;

/// L'utente gestisce i sottotitoli (`Policy.EnableSubtitleManagement`, spec R
/// §7.2): solo con un `true` vero.
bool _enableSubtitleManagement(Object? policy) =>
    policy is Map<String, dynamic> &&
    policy['EnableSubtitleManagement'] == true;

class JellyfinUser {
  const JellyfinUser({
    required this.id,
    required this.name,
    this.primaryImageTag,
    this.syncPlayAccess = SyncPlayAccess.createAndJoin,
    this.isAdministrator = false,
    this.enableSubtitleManagement = false,
  });

  factory JellyfinUser.fromJson(Map<String, dynamic> json) => JellyfinUser(
        id: json['Id'] as String,
        name: json['Name'] as String,
        primaryImageTag: json['PrimaryImageTag'] as String?,
        syncPlayAccess: _syncPlayAccess(json['Policy']),
        isAdministrator: _isAdministrator(json['Policy']),
        enableSubtitleManagement: _enableSubtitleManagement(json['Policy']),
      );

  final String id;
  final String name;
  final String? primaryImageTag;
  final SyncPlayAccess syncPlayAccess;

  /// Vede la pagina Amministrazione (spec J §7). Il server controlla comunque
  /// ogni chiamata.
  final bool isAdministrator;

  /// Può cercare, caricare e scaricare sottotitoli anche senza essere admin.
  final bool enableSubtitleManagement;

  /// Uguali se hanno gli stessi campi: così una rilettura dell'utente che non
  /// cambia niente non produce un nuovo stato di sessione.
  @override
  bool operator ==(Object other) =>
      other is JellyfinUser &&
      other.id == id &&
      other.name == name &&
      other.primaryImageTag == primaryImageTag &&
      other.syncPlayAccess == syncPlayAccess &&
      other.isAdministrator == isAdministrator &&
      other.enableSubtitleManagement == enableSubtitleManagement;

  @override
  int get hashCode => Object.hash(id, name, primaryImageTag, syncPlayAccess,
      isAdministrator, enableSubtitleManagement);
}

class AuthResult {
  const AuthResult({required this.user, required this.accessToken});

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        user: JellyfinUser.fromJson(json['User'] as Map<String, dynamic>),
        accessToken: json['AccessToken'] as String,
      );

  final JellyfinUser user;
  final String accessToken;
}

class QuickConnectState {
  const QuickConnectState({
    required this.code,
    required this.secret,
    required this.authenticated,
  });

  factory QuickConnectState.fromJson(Map<String, dynamic> json) =>
      QuickConnectState(
        code: json['Code'] as String,
        secret: json['Secret'] as String,
        authenticated: json['Authenticated'] as bool? ?? false,
      );

  final String code;
  final String secret;
  final bool authenticated;
}
