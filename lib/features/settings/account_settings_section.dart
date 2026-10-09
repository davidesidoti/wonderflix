import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../account/account_contacts_block.dart';
import '../account/account_providers.dart';
import '../account/change_password_dialog.dart';
import '../auth/session_controller.dart';
import '../profiles/avatar_dialog.dart';
import '../profiles/profile_switch.dart';

/// Diametro dell'avatar in Impostazioni → Account.
const _accountAvatarSize = 64.0;

/// Impostazioni → Account (spec L §9.2): chi è aperto, immagine, password,
/// profili, uscita e, con la funzione `account` del plugin, i contatti per
/// il recupero.
class AccountSettingsSection extends ConsumerWidget {
  const AccountSettingsSection({super.key});

  Future<void> _changePassword(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await showChangePasswordDialog(context)) {
      messenger
          ?.showSnackBar(SnackBar(content: Text(l.accountPasswordChanged)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionSignedIn ? session.user : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (user != null)
          Row(
            children: [
              UserAvatar(
                userId: user.id,
                name: user.name,
                size: _accountAvatarSize,
                imageTag: user.primaryImageTag,
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(l.settingsSignedInAs(user.name))),
            ],
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (user != null) ...[
              WfButton.secondary(
                label: l.settingsChangeImage,
                icon: LucideIcons.imagePlus,
                onPressed: () => unawaited(showAvatarDialog(context,
                    userId: user.id,
                    name: user.name,
                    imageTag: user.primaryImageTag)),
              ),
              WfButton.secondary(
                key: const Key('settings-change-password'),
                label: l.settingsChangePassword,
                icon: LucideIcons.keyRound,
                onPressed: () => unawaited(_changePassword(context)),
              ),
            ],
            WfButton.secondary(
              label: l.profilesSwitch,
              icon: LucideIcons.users,
              onPressed: () => unawaited(changeProfile(context, ref)),
            ),
            WfButton.secondary(
              label: l.menuLogout,
              icon: LucideIcons.logOut,
              onPressed: () => unawaited(
                  ref.read(sessionControllerProvider.notifier).logout()),
            ),
          ],
        ),
        if (user != null && ref.watch(accountAvailableProvider)) ...[
          const SizedBox(height: 24),
          // L'`Align` toglie la larghezza fissa che questa `Column` (con
          // `stretch`) darebbe al blocco: senza, il suo tetto non varrebbe.
          Align(
            alignment: Alignment.centerLeft,
            child: AccountContactsBlock(isAdministrator: user.isAdministrator),
          ),
        ],
      ],
    );
  }
}
