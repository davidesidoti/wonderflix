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
