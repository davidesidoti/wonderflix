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
Future<void> switchProfile(BuildContext context, WidgetRef ref,
    {bool addProfile = false}) async {
  if (ref.read(watchPartySessionProvider).phase != WatchPartyPhase.none) {
    final l = AppLocalizations.of(context);
    final confirmed = await showWfConfirmDialog(
      context,
      title: l.profilesSwitch,
      message: l.profilesSwitchLeavesParty,
      confirmLabel: l.profilesSwitch,
      cancelLabel: l.profilesCancel,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(watchPartySessionProvider.notifier)
          .leave()
          .timeout(partyLeaveTimeout);
    } on TimeoutException {
      _log.info('uscita dal watch party lenta: si cambia profilo lo stesso');
    }
    if (!context.mounted) return;
  }
  final session = ref.read(sessionControllerProvider.notifier);
  if (addProfile) {
    session.addProfile();
  } else {
    session.switchProfile();
  }
}
