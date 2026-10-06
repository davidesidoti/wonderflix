import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/admin_api.dart';
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
  /// collegato dal più recente. A parità, per dispositivo e poi per id: lo
  /// stesso utente su due dispositivi non cambia posto a ogni lettura.
  factory SessionsSnapshot.from(
      List<SessionEntry> sessions, List<PartyGroup> parties) {
    final playing = [
      for (final session in sessions)
        if (session.nowPlaying != null) session,
    ]..sort((a, b) {
        final byName =
            a.userName.toLowerCase().compareTo(b.userName.toLowerCase());
        return byName != 0 ? byName : _byDeviceThenId(a, b);
      });
    final never = DateTime.utc(0);
    final idle = [
      for (final session in sessions)
        if (session.nowPlaying == null) session,
    ]..sort((a, b) {
        final byActivity =
            (b.lastActivity ?? never).compareTo(a.lastActivity ?? never);
        return byActivity != 0 ? byActivity : _byDeviceThenId(a, b);
      });
    return SessionsSnapshot(playing: playing, idle: idle, parties: parties);
  }

  static int _byDeviceThenId(SessionEntry a, SessionEntry b) {
    final byDevice = (a.deviceName ?? '')
        .toLowerCase()
        .compareTo((b.deviceName ?? '').toLowerCase());
    return byDevice != 0 ? byDevice : a.id.compareTo(b.id);
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

  /// Le sessioni e i party si leggono insieme. Le sessioni sono l'essenziale:
  /// se falliscono, fallisce la lettura. Se fallisce solo l'elenco dei party,
  /// restano le sessioni nuove e i party dell'ultima lettura riuscita.
  @override
  Future<SessionsSnapshot> fetch() async {
    final api = ref.read(adminApiProvider);
    // Senza accesso ai watch party Jellyfin rifiuterebbe l'elenco.
    final withParties = ref.read(syncPlayAccessProvider) != SyncPlayAccess.none;
    final sessionsRead = api.sessions();
    final partiesRead = withParties ? _readParties(api) : null;
    final sessions = await sessionsRead;
    final parties = withParties
        ? await partiesRead ?? state.value?.parties ?? const <PartyGroup>[]
        : const <PartyGroup>[];
    return SessionsSnapshot.from(sessions, parties);
  }

  /// `null` se i party non si leggono. Non lancia mai, così una lettura delle
  /// sessioni già fallita non lascia un errore senza chi lo aspetta.
  Future<List<PartyGroup>?> _readParties(AdminApi api) async {
    try {
      return await api.partyGroups();
    } on Object {
      return null;
    }
  }
}

final sessionsControllerProvider = NotifierProvider.autoDispose<
    SessionsController, AdminData<SessionsSnapshot>>(SessionsController.new);
