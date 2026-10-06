import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/jellyfin/activity_models.dart';
import 'package:wonderflix/core/jellyfin/admin_api.dart';
import 'package:wonderflix/core/jellyfin/admin_models.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/maintenance_models.dart';
import 'package:wonderflix/core/social/plugin_admin_api.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/admin_providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import 'admin_json.dart';
import 'fake_session_controller.dart';
import 'social_fakes.dart';

const testAdmin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);

const testServerInfo = ServerInfo(name: 'WonderFlix', version: '10.11.9');

/// Le sessioni di [sessionsJson]: viviroby (episodio transcodificato), lucia
/// (film in remux, in pausa), davide.sidoti (collegato).
List<SessionEntry> testSessions() => parseSessions(sessionsJson);

/// Il party di [partyGroupsJson] ("Serata Lost").
List<PartyGroup> testParties() => parsePartyGroups(partyGroupsJson);

/// Le librerie di [librariesJson] (Movies in scansione).
List<LibraryFolder> testLibraries() => parseLibraries(librariesJson);

/// Le attività di [tasksJson].
List<ScheduledTask> testTasks() => parseTasks(tasksJson);

/// Le voci di [activityJson], dalla più recente.
List<ActivityEntry> testActivity() => parseActivityPage(activityJson).items;

/// [count] voci del registro, dalla più recente (id da [count] a 1); quelle
/// pari hanno un utente.
List<ActivityEntry> testActivityEntries(int count) => [
      for (var id = count; id >= 1; id--)
        ActivityEntry(
          id: id,
          name: 'Voce $id',
          date: DateTime.utc(2026, 10, 6, 8).subtract(Duration(minutes: count - id)),
          userId: id.isEven ? 'u$id' : null,
        ),
    ];

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

  List<LibraryFolder> librariesValue = const [];
  List<ScheduledTask> tasksValue = const [];

  /// Le voci del registro, dalla più recente: [activity] le filtra e le
  /// divide in pagine come Jellyfin.
  List<ActivityEntry> activityValue = const [];

  Object? librariesError;
  Object? tasksError;
  Object? activityError;

  /// Errore delle azioni: scansioni, Avvia, Ferma.
  Object? actionError;

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

  @override
  Future<List<LibraryFolder>> libraries() async {
    calls.add('libraries');
    final error = librariesError;
    if (error != null) throw error;
    return librariesValue;
  }

  @override
  Future<void> scanLibrary(String itemId) async {
    calls.add('scan:$itemId');
    final error = actionError;
    if (error != null) throw error;
  }

  @override
  Future<List<ScheduledTask>> tasks() async {
    calls.add('tasks');
    final error = tasksError;
    if (error != null) throw error;
    return tasksValue;
  }

  @override
  Future<void> startTask(String id) async {
    calls.add('start:$id');
    final error = actionError;
    if (error != null) throw error;
  }

  @override
  Future<void> stopTask(String id) async {
    calls.add('stop:$id');
    final error = actionError;
    if (error != null) throw error;
  }

  @override
  Future<ActivityPage> activity({required int startIndex, bool? hasUserId}) async {
    calls.add('activity:$startIndex:${hasUserId ?? 'all'}');
    final error = activityError;
    if (error != null) throw error;
    final matching = [
      for (final entry in activityValue)
        if (hasUserId == null || (entry.userId != null) == hasUserId) entry,
    ];
    return ActivityPage(
      items: matching.skip(startIndex).take(AdminApi.activityPageSize).toList(),
      total: matching.length,
    );
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

/// Seerr configurato, ultimo evento "Richiesta in attesa" alle 9 del
/// 2026-10-06.
final testSeerrStatus = SeerrAdminStatus(
  configured: true,
  lastEventAt: DateTime.utc(2026, 10, 6, 9),
  lastEventType: 'MEDIA_PENDING',
);

/// Il plugin finto per la scheda WonderFlix.
class FakePluginAdminApi implements PluginAdminApi {
  NewTitlesStatus newTitlesValue = const NewTitlesStatus(enabled: true, pending: 3);
  NewTitlesSent sentValue = const NewTitlesSent(titles: 3, recipients: 12);

  /// `null`: plugin più vecchio della 1.4.0.
  SeerrAdminStatus? seerrValue = testSeerrStatus;
  SeerrTestResult testValue = const SeerrTestResult(ok: true, version: '3.4.1');
  int announceRecipients = 12;

  Object? newTitlesError;
  Object? seerrError;

  /// Errore delle azioni: annuncio, interruttore, "Invia ora", prova.
  Object? actionError;

  /// Chiamate in ordine: `announce:<testo>`, `newTitles`, `send`, `seerr`,
  /// `test`, `notify:<true|false>`.
  final calls = <String>[];

  int count(String call) => calls.where((c) => c == call).length;

  @override
  Future<int> announce(String text) async {
    calls.add('announce:$text');
    final error = actionError;
    if (error != null) throw error;
    return announceRecipients;
  }

  @override
  Future<NewTitlesStatus> newTitles() async {
    calls.add('newTitles');
    final error = newTitlesError;
    if (error != null) throw error;
    return newTitlesValue;
  }

  @override
  Future<NewTitlesSent> sendNewTitles() async {
    calls.add('send');
    final error = actionError;
    if (error != null) throw error;
    return sentValue;
  }

  @override
  Future<SeerrAdminStatus?> seerrStatus() async {
    calls.add('seerr');
    final error = seerrError;
    if (error != null) throw error;
    return seerrValue;
  }

  @override
  Future<SeerrTestResult> testSeerr() async {
    calls.add('test');
    final error = actionError;
    if (error != null) throw error;
    return testValue;
  }

  /// Come il plugin vero: la lettura dopo dà il valore scritto.
  @override
  Future<void> setNotifyNewTitles(bool enabled) async {
    calls.add('notify:$enabled');
    final error = actionError;
    if (error != null) throw error;
    newTitlesValue =
        NewTitlesStatus(enabled: enabled, pending: newTitlesValue.pending);
  }
}

/// Jellyfin e plugin finti, sessione di un admin, finestra in vista, plugin
/// con la cassetta delle notifiche (scheda WonderFlix).
List<Override> adminTestOverrides(
  FakeAdminApi api, {
  FakeSessionController? session,
  FakeAdminForeground? foreground,
  FakePluginAdminApi? plugin,
  SocialFeatures features = const SocialFeatures(inbox: true),
}) =>
    [
      adminApiProvider.overrideWithValue(api),
      pluginAdminApiProvider.overrideWithValue(plugin ?? FakePluginAdminApi()),
      sessionControllerProvider.overrideWith(() =>
          session ?? FakeSessionController(const SessionSignedIn(testAdmin))),
      adminForegroundProvider
          .overrideWith(() => foreground ?? FakeAdminForeground()),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
    ];
