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
import 'admin_kit.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';

const _muted = TextStyle(color: WfColors.creamMuted);

/// "Invia prova a me" con l'esito accanto: la prova (fino a 24 s) la fanno
/// la fascia.
class _RecoveryTest extends ConsumerStatefulWidget {
  const _RecoveryTest();

  @override
  ConsumerState<_RecoveryTest> createState() => _RecoveryTestState();
}

class _RecoveryTestState extends ConsumerState<_RecoveryTest>
    with AutomaticKeepAliveClientMixin {
  /// L'esito dell'ultima prova, accanto al pulsante.
  AccountTestResult? _result;

  /// La prova è in corso (dura fino a 24 s).
  bool _testing = false;

  /// Il pulsante sta in una `ListView` che smonta ciò che esce dalla vista:
  /// scorrendo durante la prova (o dopo, con l'esito accanto al pulsante) si
  /// perderebbero l'esito e lo stato del pulsante, e se ne potrebbe far
  /// partire un'altra. Resta finché la prova dura e finché c'è un esito da
  /// leggere.
  @override
  bool get wantKeepAlive => _testing || _result != null;

  Future<void> _test() async {
    final language = Localizations.localeOf(context).languageCode;
    // Un esito vecchio non resta accanto a una prova nuova, nemmeno se
    // questa fallisce.
    setState(() {
      _testing = true;
      _result = null;
    });
    updateKeepAlive();
    try {
      final result = await ref
          .read(accountAdminControllerProvider.notifier)
          .test(language: language);
      if (mounted) setState(() => _result = result);
    } finally {
      if (mounted) {
        setState(() => _testing = false);
        updateKeepAlive();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
    final result = _result;
    return Row(
      mainAxisSize: MainAxisSize.min,
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
    );
  }
}

/// Lo stato del recupero con i suoi stati (errore, scheletro, "Dati non
/// aggiornati"); senza la funzione `account` non c'è niente e non si legge.
class _RecoveryStatus extends ConsumerWidget {
  const _RecoveryStatus({required this.builder});

  final Widget Function(AccountAdminStatus status) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(accountAvailableProvider)) return const SizedBox.shrink();
    final data = ref.watch(accountAdminControllerProvider);
    final status = data.value;
    final error = data.error;
    final updatedAt = data.updatedAt;
    final Widget child;
    if (status == null) {
      child = error != null
          ? AdminCardError(
              error: error,
              onRetry: () => unawaited(
                  ref.read(accountAdminControllerProvider.notifier).refresh()))
          : const SkeletonBox(width: 240, height: 20);
    } else {
      child = builder(status);
    }
    // La `Column` c'è sempre, così `child` non cambia posto quando compare la
    // nota (e la prova in corso non perde lo stato).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        child,
        if (data.stale && updatedAt != null)
          AdminStaleNote(updatedAt: updatedAt),
      ],
    );
  }
}

/// Il dettaglio del recupero: canali con l'ultimo errore, conteggi,
/// promemoria e dove si configura.
class _RecoveryDetail extends StatelessWidget {
  const _RecoveryDetail({required this.status});

  final AccountAdminStatus status;

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
    final now = clock.now();
    return Column(
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
        Text(l.adminRecoveryConfigHint,
            style:
                const TextStyle(color: WfColors.creamMuted, fontSize: 12.5)),
      ],
    );
  }
}

/// La fascia "Recupero password" in cima a Utenti: una spia per canale
/// (verde configurato, spenta no, rossa con l'ultimo errore) e "Invia prova
/// a me". Cliccandola si apre sotto il dettaglio (canali con l'ultimo errore,
/// conteggi, promemoria). Senza la funzione `account` del plugin non c'è.
class AccountRecoveryBand extends ConsumerStatefulWidget {
  const AccountRecoveryBand({super.key});

  @override
  ConsumerState<AccountRecoveryBand> createState() =>
      _AccountRecoveryBandState();
}

class _AccountRecoveryBandState extends ConsumerState<AccountRecoveryBand> {
  bool _open = false;

  Widget _channel(
      AppLocalizations l, AccountChannel channel, AccountChannelStatus status) {
    final name = accountChannelName(l, channel);
    final lastError = status.lastError;
    final state = lastError != null
        ? LampState.broken
        : status.configured
            ? LampState.ok
            : LampState.off;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WfLamp(
          state: state,
          label: l.adminRecoveryChannelLine(
              name,
              status.configured
                  ? l.adminRecoveryConfigured
                  : l.adminRecoveryNotConfigured),
        ),
        const SizedBox(width: 6),
        Text(name),
        if (lastError != null) ...[
          const SizedBox(width: 6),
          Text(sendErrorLabel(l, lastError.code),
              style: const TextStyle(color: WfColors.error, fontSize: 12.5)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: WfColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: WfColors.border),
      ),
      child: _RecoveryStatus(
        builder: (status) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(l.adminRecovery,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                          for (final channel in AccountChannel.values)
                            _channel(l, channel, status.channel(channel)),
                          const _RecoveryTest(),
                        ],
                      ),
                    ),
                    Icon(
                        _open
                            ? LucideIcons.chevronUp
                            : LucideIcons.chevronDown,
                        size: 18,
                        color: WfColors.creamMuted),
                  ],
                ),
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _RecoveryDetail(status: status),
              ),
          ],
        ),
      ),
    );
  }
}
