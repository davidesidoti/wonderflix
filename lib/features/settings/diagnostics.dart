import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/providers.dart';
import '../../core/logging/app_log.dart';
import '../../core/party_channel/party_channel_models.dart';
import '../../core/social/social_models.dart';
import '../discord/discord_settings.dart';
import '../player/player_settings.dart';
import '../social/social_providers.dart';
import '../watch_party/party_channel.dart';
import '../watch_party/watch_party_session.dart';

final _log = Logger('diagnostics');

/// Stato del watch party per la diagnostica (spec B §5.10); `null` fuori da
/// un gruppo. Niente nomi: solo id, stato e tempi.
String? describeWatchParty({
  required WatchPartyState state,
  Duration? offset,
  Duration? ping,
  Duration? startLag,
  Duration? lastDrift,
}) {
  final group = state.group;
  if (!state.inGroup || group == null) return null;
  String ms(Duration? d) => d == null ? '-' : '${d.inMilliseconds} ms';
  return 'group=${group.id}, state=${state.groupState.name}, '
      'members=${state.members.length}, offset=${ms(offset)}, '
      'ping=${ms(ping)}, startLag=${ms(startLag)}, lastDrift=${ms(lastDrift)}';
}

/// Plugin e canale del watch party per la diagnostica (spec E §13). Niente
/// testi né nomi: solo versione e contatori.
String describePartyChannel(PartyChannelState state) {
  final version = state.pluginVersion;
  final plugin = switch (state.availability) {
    PartyPluginAvailability.available =>
      '$version (protocollo $partyChannelProtocol)',
    PartyPluginAvailability.unavailable =>
      version == null ? 'assente' : '$version (protocollo diverso)',
    PartyPluginAvailability.unknown => 'sconosciuto',
  };
  return '$plugin, canale=${state.active ? 'attivo' : 'spento'}, '
      'inviati=${state.sent}, ricevuti=${state.received}';
}

/// Funzioni del plugin per la diagnostica (spec F §7.2).
String describePluginFeatures(Set<String> features) {
  final names = [
    if (features.contains(PluginFeatures.friends)) 'amici',
    if (features.contains(PluginFeatures.parties)) 'party',
  ];
  return names.isEmpty ? 'nessuna' : names.join(', ');
}

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
  String? watchParty,
  String? watchPartyPlugin,
  String? pluginFeatures,
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
        'showTitle=${discord.showTitle}, showPoster=${discord.showPoster}');
  if (watchParty != null) buffer.writeln('Watch party: $watchParty');
  if (watchPartyPlugin != null) {
    buffer.writeln('Plugin watch party: $watchPartyPlugin');
  }
  if (pluginFeatures != null) {
    buffer.writeln('Funzioni del plugin: $pluginFeatures');
  }
  buffer
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
          String? watchParty;
          try {
            final session = ref.read(watchPartySessionProvider.notifier);
            final clock = session.serverClock;
            watchParty = describeWatchParty(
              state: ref.read(watchPartySessionProvider),
              offset: clock?.offset,
              ping: clock?.ping,
              startLag: session.startLag?.value,
              lastDrift: session.lastDrift,
            );
          } on Object catch (error) {
            _log.info('stato del watch party non disponibile: $error');
          }
          String? watchPartyPlugin;
          try {
            await ref.read(partyChannelProvider.notifier).refreshInfo();
            watchPartyPlugin =
                describePartyChannel(ref.read(partyChannelProvider));
          } on Object catch (error) {
            _log.info('stato del plugin del watch party non disponibile: '
                '$error');
          }
          String? pluginFeatures;
          try {
            final info = await ref
                .read(socialApiProvider)
                .info()
                .timeout(PartyChannel.infoTimeout);
            pluginFeatures = describePluginFeatures(info.features);
          } on Object catch (error) {
            _log.info(
                'funzioni del plugin non disponibili: ${error.runtimeType}');
          }
          return buildDiagnostics(
            appVersion: ref.read(clientInfoProvider).version,
            windowsVersion: Platform.operatingSystemVersion,
            serverVersion: server,
            player: ref.read(playerSettingsProvider),
            discord: ref.read(discordSettingsProvider),
            recentErrors: errors,
            watchParty: watchParty,
            watchPartyPlugin: watchPartyPlugin,
            pluginFeatures: pluginFeatures,
          );
        });

/// Avvia un processo esterno senza aspettarne la fine. Sostituibile nei test.
final processStarterProvider =
    Provider<Future<Object?> Function(String executable, List<String> args)>(
        (ref) => (executable, args) =>
            Process.start(executable, args, mode: ProcessStartMode.detached));

/// Apre la cartella dei log in Esplora risorse.
final openLogsFolderProvider =
    Provider<Future<void> Function()>((ref) => () async {
          final directory = ref.read(logsDirectoryProvider);
          try {
            directory.createSync(recursive: true);
            await ref
                .read(processStarterProvider)('explorer.exe', [directory.path]);
          } on Object catch (error) {
            _log.warning('cartella dei log non aperta: $error');
          }
        });
