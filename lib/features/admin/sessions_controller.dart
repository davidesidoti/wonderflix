import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/admin_models.dart';
import '../../core/jellyfin/auth_models.dart';
import '../watch_party/watch_party_providers.dart';
import 'admin_providers.dart';
import 'admin_tab_controller.dart';

/// Il contenuto della scheda Sessioni (spec J §9.3).
class SessionsSnapshot {
  const SessionsSnapshot({
    this.playing = const [],
    this.idle = const [],
    this.parties = const [],
  });

  /// Chi guarda va per nome (senza badare alle maiuscole), chi è solo
  /// collegato dal più recente.
  factory SessionsSnapshot.from(
      List<SessionEntry> sessions, List<PartyGroup> parties) {
    final playing = [
      for (final session in sessions)
        if (session.nowPlaying != null) session,
    ]..sort((a, b) =>
        a.userName.toLowerCase().compareTo(b.userName.toLowerCase()));
    final never = DateTime.utc(0);
    final idle = [
      for (final session in sessions)
        if (session.nowPlaying == null) session,
    ]..sort((a, b) =>
        (b.lastActivity ?? never).compareTo(a.lastActivity ?? never));
    return SessionsSnapshot(playing: playing, idle: idle, parties: parties);
  }

  final List<SessionEntry> playing;
  final List<SessionEntry> idle;
  final List<PartyGroup> parties;
}

/// Sessioni e watch party, riletti ogni 5 s.
class SessionsController extends AdminTabController<SessionsSnapshot> {
  static const every = Duration(seconds: 5);

  @override
  Duration get interval => every;

  @override
  Future<SessionsSnapshot> fetch() async {
    final api = ref.read(adminApiProvider);
    // Senza accesso ai watch party Jellyfin rifiuterebbe l'elenco.
    final withParties = ref.read(syncPlayAccessProvider) != SyncPlayAccess.none;
    final results = await Future.wait<Object>(
      [api.sessions(), if (withParties) api.partyGroups()],
      eagerError: true,
    );
    return SessionsSnapshot.from(
      results[0] as List<SessionEntry>,
      withParties ? results[1] as List<PartyGroup> : const [],
    );
  }
}

final sessionsControllerProvider = NotifierProvider.autoDispose<
    SessionsController, AdminData<SessionsSnapshot>>(SessionsController.new);
