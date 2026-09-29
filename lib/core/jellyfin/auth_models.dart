class JellyfinUser {
  const JellyfinUser({required this.id, required this.name, this.primaryImageTag});

  factory JellyfinUser.fromJson(Map<String, dynamic> json) => JellyfinUser(
        id: json['Id'] as String,
        name: json['Name'] as String,
        primaryImageTag: json['PrimaryImageTag'] as String?,
      );

  final String id;
  final String name;
  final String? primaryImageTag;
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
