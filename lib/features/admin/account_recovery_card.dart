import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/account_models.dart';
import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../account/account_providers.dart';
import '../account/account_texts.dart';
import 'account_admin_controllers.dart';
import 'account_admin_labels.dart';
import 'admin_action_button.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';

const _muted = TextStyle(color: WfColors.creamMuted);

/// La card "Recupero password" della scheda WonderFlix (spec L §9.6):
/// Discord ed email, quanti utenti hanno un contatto, i promemoria e "Invia
/// prova a me". Niente campi: la configurazione è nella Dashboard. Senza la
/// funzione `account` del plugin la card non c'è.
class AccountRecoveryCard extends ConsumerStatefulWidget {
  const AccountRecoveryCard({super.key});

  @override
  ConsumerState<AccountRecoveryCard> createState() =>
      _AccountRecoveryCardState();
}

class _AccountRecoveryCardState extends ConsumerState<AccountRecoveryCard> {
  /// L'esito dell'ultima prova, accanto al pulsante.
  AccountTestResult? _result;

  Future<void> _test() async {
    final language = Localizations.localeOf(context).languageCode;
    final result = await ref
        .read(accountAdminControllerProvider.notifier)
        .test(language: language);
    if (mounted) setState(() => _result = result);
  }

  List<Widget> _channelLines(AppLocalizations l, AccountChannel channel,
      AccountChannelStatus status, DateTime now) {
    final lastError = status.lastError;
    return [
      Text(l.adminRecoveryChannelLine(
          accountChannelName(l, channel),
          status.configured
              ? l.adminRecoveryConfigured
              : l.adminRecoveryNotConfigured)),
      if (lastError != null)
        Text(
            l.adminRecoveryLastError(sendErrorLabel(l, lastError.code),
                adminTimeLabel(lastError.at, now, l)),
            style: const TextStyle(color: WfColors.error, fontSize: 13)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Senza la funzione la card non c'è, e lo stato non si legge.
    if (!ref.watch(accountAvailableProvider)) return const SizedBox.shrink();
    final data = ref.watch(accountAdminControllerProvider);
    final status = data.value;
    final error = data.error;
    final updatedAt = data.updatedAt;
    final result = _result;
    final Widget child;
    if (status == null) {
      child = error != null
          ? AdminCardError(
              error: error,
              onRetry: () => unawaited(
                  ref.read(accountAdminControllerProvider.notifier).refresh()))
          : const SkeletonBox(width: 240, height: 20);
    } else {
      final now = clock.now();
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final channel in AccountChannel.values)
            ..._channelLines(l, channel, status.channel(channel), now),
          const SizedBox(height: 8),
          Text(l.adminRecoveryWithContacts(status.withContacts, status.users),
              style: _muted),
          Text(
              status.reminderDays > 0
                  ? l.adminRecoveryReminders(status.reminderDays)
                  : l.adminRecoveryRemindersOff,
              style: _muted),
          const SizedBox(height: 12),
          Row(
            children: [
              AdminActionButton(
                label: l.adminRecoveryTest,
                icon: LucideIcons.send,
                onPressed: _test,
              ),
              if (result != null) ...[
                const SizedBox(width: 12),
                Flexible(child: Text(testResultLabel(l, result))),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(l.adminRecoveryConfigHint,
              style: const TextStyle(
                  color: WfColors.creamMuted, fontSize: 12.5)),
        ],
      );
    }
    // Come la card Seerr: la `Column` c'è sempre, così `child` non cambia
    // posto quando compare la nota (e la prova in corso non perde lo stato).
    return AdminCard(
      title: l.adminRecovery,
      icon: LucideIcons.keyRound,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          if (data.stale && updatedAt != null)
            AdminStaleNote(updatedAt: updatedAt),
        ],
      ),
    );
  }
}
