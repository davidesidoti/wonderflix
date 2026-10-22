/// Configurazione fissata in fase di build con
/// `--dart-define-from-file=config/wonderflix.json`.
class AppConfig {
  const AppConfig({
    required this.serverUrl,
    required this.githubRepo,
    required this.discordAppId,
    required this.supportUrl,
    this.accessRequestUrl,
  });

  /// Indirizzo HTTPS del server Jellyfin, senza slash finale.
  final Uri serverUrl;

  /// Repository GitHub pubblico delle release, formato `owner/repo`.
  final String githubRepo;

  /// Application ID del Discord Developer Portal.
  final String discordAppId;

  /// Link per "Password dimenticata?" (es. invito Discord). Opzionale.
  final Uri? supportUrl;

  /// Link del pulsante «Chiedi l'accesso» nell'attività su Discord (es. il
  /// profilo Discord del proprietario). Opzionale.
  final Uri? accessRequestUrl;

  static AppConfig fromEnvironment() => AppConfig.parse(
        serverUrl: const String.fromEnvironment('serverUrl'),
        githubRepo: const String.fromEnvironment('githubRepo'),
        discordAppId: const String.fromEnvironment('discordAppId'),
        supportUrl: const String.fromEnvironment('supportUrl'),
        accessRequestUrl: const String.fromEnvironment('accessRequestUrl'),
      );

  static AppConfig parse({
    required String serverUrl,
    required String githubRepo,
    required String discordAppId,
    required String supportUrl,
    String accessRequestUrl = '',
  }) {
    final server = Uri.tryParse(serverUrl.trim());
    if (server == null || server.scheme != 'https' || server.host.isEmpty) {
      throw AppConfigException(
          'serverUrl deve essere un indirizzo https valido, ricevuto: "$serverUrl"');
    }
    final normalized =
        server.replace(path: server.path.replaceAll(RegExp(r'/+$'), ''));
    final support = supportUrl.trim();
    final access = Uri.tryParse(accessRequestUrl.trim());
    return AppConfig(
      serverUrl: normalized,
      githubRepo: githubRepo.trim(),
      discordAppId: discordAppId.trim(),
      supportUrl: support.isEmpty ? null : Uri.tryParse(support),
      accessRequestUrl: access != null &&
              (access.isScheme('https') || access.isScheme('http'))
          ? access
          : null,
    );
  }
}

class AppConfigException implements Exception {
  AppConfigException(this.message);
  final String message;

  @override
  String toString() => 'AppConfigException: $message';
}
