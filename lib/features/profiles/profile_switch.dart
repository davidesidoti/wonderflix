import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_confirm_dialog.dart';
import '../auth/session_controller.dart';
import '../watch_party/watch_party_session.dart';

final _log = Logger('profiles');

/// Quanto si aspetta l'uscita dal watch party prima di cambiare profilo
/// comunque (spec K §9.7): il gruppo lo pulisce poi Jellyfin.
const partyLeaveTimeout = Duration(seconds: 3);

/// Cambia profilo, o ne aggiunge uno con [addProfile] (spec K §9.5, §9.7). In
/// un watch party chiede conferma ed esce dal gruppo: il token del profilo
/// non si annulla, quindi il party non si chiuderebbe da solo.
///
/// Un cambio confermato si fa anche se chi l'ha chiesto (il menu, le
/// Impostazioni) sparisce mentre si esce dal party; non si fa se nel
/// frattempo la sessione è cambiata (un'uscita, un 401).
Future<void> changeProfile(BuildContext context, WidgetRef ref,
    {bool addProfile = false}) async {
  // Tutto quello che serve dopo le attese si legge prima: dopo, `ref` e
  // `context` possono non valere più.
  final container = ProviderScope.containerOf(context, listen: false);
  final session = ref.read(sessionControllerProvider.notifier);
  final before = ref.read(sessionControllerProvider);
  final userId = before is SessionSignedIn ? before.user.id : null;
  if (ref.read(watchPartySessionProvider).phase != WatchPartyPhase.none) {
    final party = ref.read(watchPartySessionProvider.notifier);
    final l = AppLocalizations.of(context);
    final action = addProfile ? l.profilesAdd : l.profilesSwitch;
    final confirmed = await showWfConfirmDialog(
      context,
      title: action,
      message: l.profilesSwitchLeavesParty,
      confirmLabel: action,
      cancelLabel: l.profilesCancel,
    );
    if (!confirmed) return;
    try {
      await party.leave().timeout(partyLeaveTimeout);
    } on TimeoutException {
      _log.info('uscita dal watch party lenta: si cambia profilo lo stesso');
    }
    final now = container.read(sessionControllerProvider);
    if (userId == null || now is! SessionSignedIn || now.user.id != userId) {
      return;
    }
  }
  if (addProfile) {
    session.addProfile();
  } else {
    session.switchProfile();
  }
}
