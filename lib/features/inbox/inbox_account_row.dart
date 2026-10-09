import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Il testo del promemoria per i canali del server (spec L §9.4). Senza un
/// canale noto, quello per tutti e due.
String inboxContactReminderText(
        AppLocalizations l, List<AccountChannel> channels) =>
    switch ((
      channels.contains(AccountChannel.discord),
      channels.contains(AccountChannel.email),
    )) {
      (true, false) => l.inboxContactReminderDiscord,
      (false, true) => l.inboxContactReminderEmail,
      _ => l.inboxContactReminderBoth,
    };

/// Il promemoria dei contatti: il clic chiude il pannello e apre
/// Impostazioni, dove la sezione Account è la prima.
class InboxContactReminderContent extends ConsumerWidget {
  const InboxContactReminderContent({
    super.key,
    required this.channels,
    required this.time,
  });

  final List<AccountChannel> channels;
  final String time;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: () {
          ref.read(shellPanelProvider.notifier).close();
          context.go('/settings');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.inboxContactReminderTitle,
                  style: const TextStyle(
                      color: WfColors.cream, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(inboxContactReminderText(l, channels),
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 13)),
              const SizedBox(height: 4),
              Text(time,
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
