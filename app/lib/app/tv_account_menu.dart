import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../features/auth/profiles_state.dart';
import '../l10n/gen/app_localizations.dart';
import '../ui/wf_buttons.dart';
import '../ui/wf_dialog.dart';
import 'app_shell.dart';

/// Il menu dell'avatar sulla TV: Cambia account, Aggiungi account,
/// Impostazioni, Esci. La voce scelta la esegue [runUserMenuAction] con
/// [context], che dev'essere quello della shell (resta montato a finestra
/// chiusa).
Future<void> showTvAccountMenu(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  // Come nel menu del PC: al massimo 5 profili.
  final canAdd = !ref.read(profilesProvider).book.isFull;
  final choice = await showWfDialog<String>(
    context,
    maxWidth: 360,
    semanticLabel: l.tvAccountSwitch,
    // La TV è larga ~960 dp: il layout "stretto" non c'entra.
    fullPageWhenCompact: false,
    builder: (dialog) {
      Widget button(
        String value,
        String label,
        IconData icon, {
        bool autofocus = false,
      }) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          width: double.infinity,
          child: WfButton.secondary(
            label: label,
            icon: icon,
            autofocus: autofocus,
            onPressed: () => Navigator.of(dialog).pop(value),
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(
              'switch',
              l.tvAccountSwitch,
              LucideIcons.users,
              autofocus: true,
            ),
            if (canAdd) button('add', l.tvAccountAdd, LucideIcons.userPlus),
            button('settings', l.menuSettings, LucideIcons.settings),
            button('logout', l.menuLogout, LucideIcons.logOut),
          ],
        ),
      );
    },
  );
  if (choice != null && context.mounted) {
    runUserMenuAction(context, ref, choice);
  }
}
