import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../social/social_providers.dart';
import 'friends_controller.dart';

/// Icona "Amici" nella barra, con il numero delle richieste in arrivo
/// (spec F §8.2). Solo con la funzione amici del plugin (che c'è solo con
/// l'accesso ai watch party).
class FriendsButton extends ConsumerWidget {
  const FriendsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.friends))) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final count =
        ref.watch(friendsControllerProvider.select((s) => s.incomingCount));
    // Tiene vivo lo stato del pannello finché la barra c'è.
    ref.watch(shellPanelProvider);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        key: const Key('friends-button'),
        tooltip: l.friendsTitle,
        onPressed: () =>
            ref.read(shellPanelProvider.notifier).toggle(ShellPanel.friends),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          backgroundColor: WfColors.gold,
          textColor: WfColors.bg,
          child: const Icon(LucideIcons.users, size: 20, color: WfColors.cream),
        ),
      ),
    );
  }
}
