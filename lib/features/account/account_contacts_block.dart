import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'account_providers.dart';
import 'account_texts.dart';
import 'link_contact_dialog.dart';
import 'unlink_contact_dialog.dart';

const _mutedStyle = TextStyle(color: WfColors.creamMuted, fontSize: 12.5);

/// Larghezza massima delle righe: su uno schermo largo le azioni restano
/// vicine al contatto.
const _rowsMaxWidth = 640.0;

/// Larghezza della colonna del nome del canale, perché gli stati si
/// allineino.
const _channelWidth = 90.0;

/// Contatti per il recupero (spec L §9.2): una riga per canale, con
/// "Collega" o "Cambia" e "Scollega".
class AccountContactsBlock extends ConsumerWidget {
  const AccountContactsBlock({super.key, required this.isAdministrator});

  /// Gli admin non hanno il recupero automatico: lo dice il testo sotto.
  final bool isAdministrator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final contacts = ref.watch(accountContactsProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _rowsMaxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.accountContactsTitle,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          switch (contacts) {
            AsyncData(:final value?) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final channel in AccountChannel.values)
                    _ContactRow(channel: channel, contacts: value),
                ],
              ),
            AsyncError() => Row(
                children: [
                  Flexible(
                      child: Text(l.accountContactsError, style: _mutedStyle)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => ref.invalidate(accountContactsProvider),
                    child: Text(l.retry),
                  ),
                ],
              ),
            AsyncData() => const SizedBox.shrink(),
            _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          },
          const SizedBox(height: 8),
          Text(
              isAdministrator
                  ? '${l.accountContactsHint} ${l.accountContactsAdminHint}'
                  : l.accountContactsHint,
              style: _mutedStyle),
        ],
      ),
    );
  }
}

class _ContactRow extends ConsumerWidget {
  const _ContactRow({required this.channel, required this.contacts});

  final AccountChannel channel;
  final AccountContacts contacts;

  Future<void> _link(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final linked = await showLinkContactDialog(context, channel);
    if (linked == null || !context.mounted) return;
    ref.read(accountContactsProvider.notifier).replace(linked);
    messenger?.showSnackBar(SnackBar(content: Text(l.accountLinkedDone)));
  }

  Future<void> _unlink(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final unlinked = await showUnlinkContactDialog(context, channel);
    if (!unlinked || !context.mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text(l.accountUnlinkedDone)));
    await ref.read(accountContactsProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final available = contacts.isAvailable(channel);
    final value = contacts.contactOf(channel);
    // Un canale spento è grigio anche con il contatto (i contatti restano,
    // spec L §11).
    final status = !available
        ? l.accountChannelOff
        : value == null
            ? l.accountNotLinked
            : l.accountLinked(value);
    final linkedAndOn = available && value != null;
    return Padding(
      key: Key('account-contact-${channel.wire}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            channel == AccountChannel.discord
                ? LucideIcons.messageCircle
                : LucideIcons.mail,
            size: 18,
            color: available ? WfColors.gold : WfColors.creamMuted,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: _channelWidth,
            child: Text(accountChannelName(l, channel),
                style: TextStyle(
                    color: available ? WfColors.cream : WfColors.creamMuted,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(status,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color:
                        linkedAndOn ? WfColors.cream : WfColors.creamMuted)),
          ),
          if (available)
            TextButton(
              key: Key('account-link-${channel.wire}'),
              onPressed: () => unawaited(_link(context, ref)),
              child: Text(value == null ? l.accountLink : l.accountChange),
            ),
          if (value != null)
            TextButton(
              key: Key('account-unlink-${channel.wire}'),
              onPressed: () => unawaited(_unlink(context, ref)),
              child: Text(l.accountUnlink),
            ),
        ],
      ),
    );
  }
}
