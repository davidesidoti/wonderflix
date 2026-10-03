import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/shell_side_panel.dart';
import '../social/social_providers.dart';
import 'inbox_controller.dart';
import 'inbox_panel.dart';

/// Oltre questo numero l'icona mostra "99+".
const inboxBadgeMax = 99;

/// Il numero sull'icona.
String inboxBadgeLabel(int count) =>
    count > inboxBadgeMax ? '$inboxBadgeMax+' : '$count';

/// Icona "Notifiche" nella barra, con il numero dorato dei non letti (spec
/// G §7.4). Solo con la cassetta del plugin, anche senza accesso ai watch
/// party.
class InboxButton extends ConsumerWidget {
  const InboxButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.inbox))) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final count = ref.watch(inboxControllerProvider.select((s) => s.unread));
    // Tiene vivo lo stato dei pannelli finché la barra c'è.
    ref.watch(shellPanelProvider);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        key: const Key('inbox-button'),
        tooltip: l.inboxTitle,
        onPressed: () =>
            ref.read(shellPanelProvider.notifier).toggle(ShellPanel.inbox),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(inboxBadgeLabel(count)),
          backgroundColor: WfColors.gold,
          textColor: WfColors.bg,
          child: const Icon(LucideIcons.inbox, size: 20, color: WfColors.cream),
        ),
      ),
    );
  }
}

/// Il pannello si vede: aperto e con la cassetta del plugin.
final inboxPanelVisibleProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(shellPanelProvider) == ShellPanel.inbox &&
    ref.watch(socialAvailabilityProvider.select((f) => f.inbox)));

/// Pannello Notifiche sopra la shell e la barra (spec G §7.5), nel
/// contenitore comune dei pannelli laterali.
class InboxPanelHost extends ConsumerWidget {
  const InboxPanelHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Funzione sparita a pannello aperto: si chiude davvero.
    ref.listen(inboxPanelVisibleProvider, (_, visible) {
      if (!visible && ref.read(shellPanelProvider) == ShellPanel.inbox) {
        ref.read(shellPanelProvider.notifier).close();
      }
    });
    return ShellSidePanel(
      open: ref.watch(inboxPanelVisibleProvider),
      onClose: () => ref.read(shellPanelProvider.notifier).close(),
      scrimKey: const Key('inbox-panel-scrim'),
      child: const InboxPanel(),
    );
  }
}
