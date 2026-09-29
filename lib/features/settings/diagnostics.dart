import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/logging/app_log.dart';
import '../discord/discord_settings.dart';
import '../player/player_settings.dart';

final _log = Logger('diagnostics');

/// Testo da incollare nelle richieste di aiuto. Non contiene dati
/// dell'account; gli errori sono già senza segreti. L'host del server negli
/// errori lo toglie [collectDiagnosticsProvider].
String buildDiagnostics({
  required String appVersion,
  required String windowsVersion,
  required String? serverVersion,
  required PlayerSettings player,
  required DiscordSettings discord,
  required List<String> recentErrors,
}) {
  final buffer = StringBuffer()
    ..writeln('WonderFlix $appVersion')
    ..writeln('Windows: $windowsVersion')
    ..writeln('Jellyfin: ${serverVersion ?? 'non raggiungibile'}')
    ..writeln('Player: quality=${player.quality.name}, '
        'hardwareDecoding=${player.hardwareDecoding}, '
        'subtitleScale=${player.subtitleScale}, '
        'autoSkipIntro=${player.autoSkipIntro}, '
        'autoplayNext=${player.autoplayNext}')
    ..writeln('Discord: enabled=${discord.enabled}, '
        'showTitle=${discord.showTitle}, showPoster=${discord.showPoster}')
    ..writeln()
    ..writeln('Ultimi errori (${recentErrors.length}):');
  if (recentErrors.isEmpty) buffer.writeln('nessuno');
  for (final error in recentErrors) {
    buffer.writeln(error);
  }
  return buffer.toString();
}

/// Raccoglie la diagnostica (la versione del server con un tentativo di al
/// massimo 5 s).
final collectDiagnosticsProvider =
    Provider<Future<String> Function()>((ref) => () async {
          String? server;
          try {
            server = await ref
                .read(systemApiProvider)
                .serverVersion()
                .timeout(const Duration(seconds: 5));
          } on Object catch (error) {
            _log.info('versione del server non disponibile: $error');
          }
          // L'indirizzo del server può comparire dentro gli errori.
          final host = ref.read(appConfigProvider).serverUrl.host;
          final errors = [
            for (final error in ref.read(appLogProvider).recentErrors)
              host.isEmpty ? error : error.replaceAll(host, '<server>'),
          ];
          return buildDiagnostics(
            appVersion: ref.read(clientInfoProvider).version,
            windowsVersion: Platform.operatingSystemVersion,
            serverVersion: server,
            player: ref.read(playerSettingsProvider),
            discord: ref.read(discordSettingsProvider),
            recentErrors: errors,
          );
        });

/// Apre la cartella dei log in Esplora risorse.
final openLogsFolderProvider =
    Provider<Future<void> Function()>((ref) => () async {
          final directory = ref.read(logsDirectoryProvider);
          try {
            directory.createSync(recursive: true);
            await launchUrl(Uri.file(directory.path, windows: true));
          } on Object catch (error) {
            _log.warning('cartella dei log non aperta: $error');
          }
        });
