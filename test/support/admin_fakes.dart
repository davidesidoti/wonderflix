import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/jellyfin/admin_api.dart';
import 'package:wonderflix/core/jellyfin/admin_models.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/admin/admin_providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import 'admin_json.dart';
import 'fake_session_controller.dart';

const testAdmin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);

const testServerInfo = ServerInfo(name: 'WonderFlix', version: '10.11.9');

/// Le sessioni di [sessionsJson]: viviroby (episodio transcodificato), lucia
/// (film in remux, in pausa), davide.sidoti (collegato).
List<SessionEntry> testSessions() => parseSessions(sessionsJson);

/// Il party di [partyGroupsJson] ("Serata Lost").
List<PartyGroup> testParties() => parsePartyGroups(partyGroupsJson);

/// Una sessione costruita a mano.
SessionEntry testSession(
  String id,
  String userName, {
  NowPlaying? playing,
  DateTime? lastActivity,
  PlayMethod playMethod = PlayMethod.unknown,
  TranscodeInfo? transcode,
}) =>
    SessionEntry(
      id: id,
      userId: 'id-$userName',
      userName: userName,
      client: 'WonderFlix',
      deviceName: 'PC',
      lastActivity: lastActivity,
      nowPlaying: playing,
      playMethod: playMethod,
      transcode: transcode,
    );

const testMovie = NowPlaying(
  itemId: 'm1',
  name: 'Dune',
  kind: NowPlayingKind.movie,
  year: 2021,
  runtime: Duration(minutes: 155),
);

/// Jellyfin finto per la pagina Amministrazione.
class FakeAdminApi implements AdminApi {
  List<SessionEntry> sessionsValue = const [];
  List<PartyGroup> partiesValue = const [];
  ServerInfo serverInfoValue = testServerInfo;

  /// Errori delle letture: restano finché il test non li toglie.
  Object? sessionsError;
  Object? partiesError;
  Object? serverInfoError;

  /// Errore di [restart].
  Object? restartError;

  /// Risposte di [isServerUp], in ordine; finite, `true`.
  final upAnswers = <bool>[];

  /// Chiamate in ordine: `sessions`, `parties`, `info`, `up`, `restart`.
  final calls = <String>[];

  int count(String call) => calls.where((c) => c == call).length;

  @override
  Future<List<SessionEntry>> sessions() async {
    calls.add('sessions');
    final error = sessionsError;
    if (error != null) throw error;
    return sessionsValue;
  }

  @override
  Future<List<PartyGroup>> partyGroups() async {
    calls.add('parties');
    final error = partiesError;
    if (error != null) throw error;
    return partiesValue;
  }

  @override
  Future<ServerInfo> serverInfo() async {
    calls.add('info');
    final error = serverInfoError;
    if (error != null) throw error;
    return serverInfoValue;
  }

  @override
  Future<bool> isServerUp() async {
    calls.add('up');
    return upAnswers.isEmpty ? true : upAnswers.removeAt(0);
  }

  @override
  Future<void> restart() async {
    calls.add('restart');
    final error = restartError;
    if (error != null) throw error;
  }
}

/// Finestra in vista finta: niente `AppLifecycleListener`, la cambia il test.
class FakeAdminForeground extends AdminForeground {
  FakeAdminForeground([this.initial = true]);

  final bool initial;

  @override
  bool build() => initial;

  void set(bool visible) => state = visible;
}

/// Jellyfin finto, sessione di un admin e finestra in vista.
List<Override> adminTestOverrides(
  FakeAdminApi api, {
  FakeSessionController? session,
  FakeAdminForeground? foreground,
}) =>
    [
      adminApiProvider.overrideWithValue(api),
      sessionControllerProvider.overrideWith(() =>
          session ?? FakeSessionController(const SessionSignedIn(testAdmin))),
      adminForegroundProvider
          .overrideWith(() => foreground ?? FakeAdminForeground()),
    ];
