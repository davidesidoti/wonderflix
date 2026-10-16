import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../social/social_providers.dart';
import '../watch_party/watch_party_providers.dart';
import '../watch_party/watch_party_session.dart';
import 'match_room_controller.dart';

/// Gli ingressi "Match" si vedono (spec P §7.1–7.2): con la funzione del
/// plugin, il permesso di creare gruppi, fuori da un watch party e fuori da
/// una sala (piano 22b, decisione 10).
final matchEntryProvider = Provider<bool>((ref) {
  if (!ref.watch(socialAvailabilityProvider.select((f) => f.match))) {
    return false;
  }
  if (!ref.watch(syncPlayAccessProvider.select((a) => a.canCreate))) {
    return false;
  }
  if (ref.watch(watchPartySessionProvider.select((s) => s.phase)) !=
      WatchPartyPhase.none) {
    return false;
  }
  final room = ref.watch(matchRoomProvider);
  return room == null || room.closed;
});

/// "Match" in Home, accanto a "Cosa guardo stasera?" (spec P §7.2). Come
/// `TonightButton` non agisce da solo: [onPressed] è di chi lo mette.
class MatchButton extends ConsumerWidget {
  const MatchButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(matchEntryProvider)) return const SizedBox.shrink();
    return WfButton.secondary(
      key: const Key('match-button'),
      label: AppLocalizations.of(context).matchButton,
      icon: LucideIcons.heartHandshake,
      onPressed: onPressed,
    );
  }
}
