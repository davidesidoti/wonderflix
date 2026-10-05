import '../core/jellyfin/api_exception.dart';
import '../core/requests/requests_api.dart';
import '../core/video/video_engine.dart';
import '../l10n/gen/app_localizations.dart';

/// Messaggio per l'utente a partire da un errore qualsiasi.
String describeError(AppLocalizations l, Object error) => switch (error) {
      UnauthorizedException() => l.errorInvalidCredentials,
      ForbiddenException() => l.errorAccountDisabled,
      ServerUnreachableException() => l.errorServerUnreachable,
      PlaybackUnavailableException() => l.errorPlaybackUnavailable,
      EngineOpenException() => l.errorPlaybackFailed,
      RequestsException(
        failure: RequestsFailure.seerrUnavailable || RequestsFailure.notConfigured
      ) =>
        l.requestsSeerrDown,
      _ => l.errorGeneric,
    };
