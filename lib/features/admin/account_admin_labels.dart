import '../../app/error_text.dart';
import '../../core/social/account_models.dart';
import '../../core/social/plugin_admin_api.dart';
import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../account/account_texts.dart';

/// Dove è arrivato il codice mandato dall'admin (spec L §9.5).
String recoverySentLabel(AppLocalizations l, List<AccountChannel> channels) =>
    switch ((
      channels.contains(AccountChannel.discord),
      channels.contains(AccountChannel.email),
    )) {
      (true, false) => l.adminUsersRecoverySentDiscord,
      (false, true) => l.adminUsersRecoverySentEmail,
      _ => l.adminUsersRecoverySentBoth,
    };

/// L'errore di un'azione sugli utenti: i `{Code}` del plugin (spec L
/// §7.6), altrimenti `describeError`. [name] è l'utente della riga.
String accountAdminErrorText(AppLocalizations l, Object error, String name) =>
    switch (pluginErrorCode(error)) {
      'NotAllowed' => l.adminUsersNotAllowed,
      'NoContacts' => l.adminUsersNoContacts(name),
      'SendFailed' => l.accountErrorSendFailed,
      'UnknownUser' => l.adminUsersUnknown,
      _ => describeError(l, error),
    };

/// L'ultimo errore d'invio di un canale ("DM chiusi").
String sendErrorLabel(AppLocalizations l, String code) => switch (code) {
      'DmClosed' => l.adminRecoveryErrorDmClosed,
      'Invalid' => l.adminRecoveryErrorInvalid,
      _ => l.adminRecoveryErrorSendFailed,
    };

/// L'esito della prova di un canale (`AccountTestCodes` del plugin).
String testOutcomeLabel(AppLocalizations l, String code) => switch (code) {
      'Ok' => l.adminRecoveryTestSent,
      'NotConfigured' => l.adminRecoveryNotConfigured,
      'NoContact' => l.adminRecoveryTestNoContact,
      'Invalid' => l.adminRecoveryErrorInvalid,
      'DmClosed' => l.adminRecoveryTestDmClosed,
      'MemberNotFound' => l.adminRecoveryTestMemberNotFound,
      'InvalidTarget' => l.adminRecoveryTestInvalidTarget,
      _ => l.adminRecoveryErrorSendFailed,
    };

/// "Discord: inviato · Email: collega prima il tuo contatto".
String testResultLabel(AppLocalizations l, AccountTestResult result) => [
      for (final channel in AccountChannel.values)
        l.adminRecoveryChannelLine(accountChannelName(l, channel),
            testOutcomeLabel(l, result.of(channel))),
    ].join(' · ');
