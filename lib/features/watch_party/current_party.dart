import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/syncplay/party_mode.dart';
import '../social/social_providers.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

/// Il party in cui siamo, come lo dice il plugin (spec F §9.3).
class CurrentParty {
  const CurrentParty({
    required this.groupId,
    required this.mode,
    this.code,
    this.invited = const {},
    this.announceCode = false,
  });

  final String groupId;
  final PartyMode mode;

  /// Solo per i privati.
  final String? code;

  /// Amici invitati da noi (il menu li mostra come "Invitato").
  final Set<String> invited;

  /// Il codice va mostrato una volta nella pillola del player: party privato
  /// appena creato da noi.
  final bool announceCode;

  CurrentParty copyWith({Set<String>? invited, bool? announceCode}) =>
      CurrentParty(
        groupId: groupId,
        mode: mode,
        code: code,
        invited: invited ?? this.invited,
        announceCode: announceCode ?? this.announceCode,
      );
}

/// Legge modalità e codice entrando in un gruppo (con la funzione `parties`
/// del plugin); `null` fuori da un gruppo.
class CurrentPartyController extends Notifier<CurrentParty?> {
  /// Cresce a ogni ricostruzione: una lettura superata non vale.
  int _loads = 0;

  @override
  CurrentParty? build() {
    final groupId = ref.watch(watchPartySessionProvider
        .select((s) => s.inGroup ? s.group?.id : null));
    final parties =
        ref.watch(socialAvailabilityProvider.select((f) => f.parties));
    final load = ++_loads;
    if (groupId == null || !parties) return null;
    unawaited(Future.microtask(() => _load(groupId, load)));
    return null;
  }

  Future<void> _load(String groupId, int load) async {
    // Registrato da noi intanto: il dato c'è già.
    if (!ref.mounted || load != _loads || state?.groupId == groupId) return;
    try {
      final details = await ref.read(socialApiProvider).partyDetails(groupId);
      if (!ref.mounted || load != _loads || state?.groupId == groupId) return;
      state = CurrentParty(
          groupId: groupId, mode: details.mode, code: details.code);
    } on Object catch (error) {
      _log.info('party corrente non letto: ${error.runtimeType}');
    }
  }

  /// Party appena creato e registrato da noi (spec F §9.2). La registrazione
  /// può finire dopo l'uscita dal gruppo: allora non vale.
  void registered(String groupId, PartyMode mode, String? code) {
    final session = ref.read(watchPartySessionProvider);
    if (!session.inGroup || session.group?.id != groupId) return;
    state = CurrentParty(
      groupId: groupId,
      mode: mode,
      code: code,
      announceCode: mode == PartyMode.private && code != null,
    );
  }

  /// La pillola ha mostrato il codice.
  void codeAnnounced() {
    final current = state;
    if (current != null) state = current.copyWith(announceCode: false);
  }

  /// Abbiamo invitato [userId].
  void invited(String userId) {
    final current = state;
    if (current != null) {
      state = current.copyWith(invited: {...current.invited, userId});
    }
  }
}

final currentPartyProvider =
    NotifierProvider<CurrentPartyController, CurrentParty?>(
        CurrentPartyController.new);
