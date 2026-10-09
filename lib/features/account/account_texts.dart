import '../../core/social/account_api.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Il nome del canale nei testi: "Discord", "Email".
String accountChannelName(AppLocalizations l, AccountChannel channel) =>
    switch (channel) {
      AccountChannel.discord => l.accountChannelDiscord,
      AccountChannel.email => l.accountChannelEmail,
    };

/// Il testo di un errore dei contatti (spec L §9.2, §10). Il 429 dice "più
/// tardi": i limiti arrivano a un giorno.
String accountFailureText(
        AppLocalizations l, AccountFailure failure, AccountChannel channel) =>
    switch (failure) {
      AccountFailure.unavailable ||
      AccountFailure.channelOff =>
        l.accountChannelOff,
      AccountFailure.invalidTarget => switch (channel) {
          AccountChannel.discord => l.accountErrorInvalidDiscordName,
          AccountChannel.email => l.accountErrorInvalidEmail,
        },
      AccountFailure.memberNotFound => l.accountErrorMemberNotFound,
      AccountFailure.wrongPassword => l.accountWrongPassword,
      AccountFailure.dmClosed => l.accountErrorDmClosed,
      AccountFailure.sendFailed => l.accountErrorSendFailed,
      AccountFailure.invalidCode => l.accountErrorInvalidCode,
      AccountFailure.rateLimited => l.accountErrorRateLimited,
      AccountFailure.weakPassword => l.accountPasswordTooShort,
      AccountFailure.network => l.errorServerUnreachable,
      AccountFailure.invalid || AccountFailure.serverError => l.errorGeneric,
    };
