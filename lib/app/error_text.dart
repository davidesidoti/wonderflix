import '../core/jellyfin/api_exception.dart';
import '../l10n/gen/app_localizations.dart';

/// Messaggio per l'utente a partire da un errore qualsiasi.
String describeError(AppLocalizations l, Object error) => switch (error) {
      UnauthorizedException() => l.errorInvalidCredentials,
      ForbiddenException() => l.errorAccountDisabled,
      ServerUnreachableException() => l.errorServerUnreachable,
      _ => l.errorGeneric,
    };
