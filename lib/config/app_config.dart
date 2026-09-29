/// Configurazione fissata in fase di build con
/// `--dart-define-from-file=config/wonderflix.json`.
class AppConfig {
  const AppConfig({
    required this.serverUrl,
    required this.githubRepo,
    required this.discordAppId,
    required this.supportUrl,
  });

  /// Indirizzo HTTPS del server Jellyfin, senza slash finale.
  final Uri serverUrl;

  /// Repository GitHub pubblico delle release, formato `owner/repo`.
  final String githubRepo;

  /// Application ID del Discord Developer Portal.
  final String discordAppId;

  /// Link per "Password dimenticata?" (es. invito Discord). Opzionale.
  final Uri? supportUrl;

  static AppConfig fromEnvironment() => AppConfig.parse(
        serverUrl: const String.fromEnvironment('serverUrl'),
        githubRepo: const String.fromEnvironment('githubRepo'),
        discordAppId: const String.fromEnvironment('discordAppId'),
        supportUrl: const String.fromEnvironment('supportUrl'),
      );

  static AppConfig parse({
    required String serverUrl,
    required String githubRepo,
    required String discordAppId,
    required String supportUrl,
  }) {
    final server = Uri.tryParse(serverUrl.trim());
    if (server == null || server.scheme != 'https' || server.host.isEmpty) {
      throw AppConfigException(
          'serverUrl deve essere un indirizzo https valido, ricevuto: "$serverUrl"');
    }
    final normalized =
        server.replace(path: server.path.replaceAll(RegExp(r'/+$'), ''));
    final support = supportUrl.trim();
    return AppConfig(
      serverUrl: normalized,
      githubRepo: githubRepo.trim(),
      discordAppId: discordAppId.trim(),
      supportUrl: support.isEmpty ? null : Uri.tryParse(support),
    );
  }
}

class AppConfigException implements Exception {
  AppConfigException(this.message);
  final String message;

  @override
  String toString() => 'AppConfigException: $message';
}
