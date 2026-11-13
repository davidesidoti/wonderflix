import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_buttons.dart';
import '../account/account_contacts_block.dart';
import '../account/account_providers.dart';
import '../account/authorize_device_dialog.dart';
import '../account/change_password_dialog.dart';
import '../auth/session_controller.dart';
import '../profiles/profile_switch.dart';
import '../social/social_providers.dart';
import 'account_card.dart';
import 'share_activity_setting.dart';

/// Impostazioni → Account (spec L §9.2): la tessera (immagine, password,
/// dispositivi, profili), la condivisione, i contatti per il recupero se il
/// plugin li ha e "Esci" da solo in fondo.
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

  Future<void> _authorizeDevice(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await showAuthorizeDeviceDialog(context)) {
      messenger?.showSnackBar(SnackBar(content: Text(l.authorizeDeviceDone)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionSignedIn ? session.user : null;
    final switchProfile = WfButton.secondary(
      label: l.profilesSwitch,
      icon: LucideIcons.users,
      onPressed: () => unawaited(changeProfile(context, ref)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (user != null)
          AccountCard(
            userId: user.id,
            name: user.name,
            imageTag: user.primaryImageTag,
            isAdministrator: user.isAdministrator,
            actions: [
              WfButton.secondary(
                key: const Key('settings-change-password'),
                label: l.settingsChangePassword,
                icon: LucideIcons.keyRound,
                onPressed: () => unawaited(_changePassword(context)),
              ),
              WfButton.secondary(
                key: const Key('settings-quick-connect'),
                label: l.settingsQuickConnect,
                icon: LucideIcons.monitorSmartphone,
                onPressed: () => unawaited(_authorizeDevice(context)),
              ),
              switchProfile,
            ],
          )
        else
          Align(alignment: Alignment.centerLeft, child: switchProfile),
        // Piano 21b, decisione 5: vale per l'account aperto.
        if (user != null &&
            ref.watch(
              socialAvailabilityProvider.select((f) => f.friendsActivity),
            )) ...[
          const SizedBox(height: 16),
          const ShareActivitySetting(),
        ],
        if (user != null && ref.watch(accountAvailableProvider)) ...[
          const SizedBox(height: 24),
          // L'`Align` toglie la larghezza fissa che questa `Column` (con
          // `stretch`) darebbe al blocco: senza, il suo tetto non varrebbe.
          Align(
            alignment: Alignment.centerLeft,
            child: AccountContactsBlock(isAdministrator: user.isAdministrator),
          ),
        ],
        // Staccato dagli altri: è l'unico che toglie l'accesso.
        const SizedBox(height: 32),
        Align(
          alignment: Alignment.centerLeft,
          child: _LogoutButton(
            onPressed: () => unawaited(
              ref.read(sessionControllerProvider.notifier).logout(),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Esci": un bottone secondario con testo e bordo `error`. [WfButton] non ha
/// questa variante e agli altri chiamanti non serve.
class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const side = BorderSide(color: WfColors.error);
    return WfButtonFeedback(
      enabled: true,
      child: OutlinedButton.icon(
        key: const Key('settings-logout'),
        onPressed: onPressed,
        style:
            OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              foregroundColor: WfColors.error,
              side: side,
            ).copyWith(
              side: tvButtonSide(FormFactor.of(context).tv, side),
            ),
        icon: const Icon(LucideIcons.logOut, size: 18),
        label: Text(AppLocalizations.of(context).menuLogout),
      ),
    );
  }
}
