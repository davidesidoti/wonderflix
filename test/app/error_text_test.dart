import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/error_text.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/core/video/video_engine.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('ogni errore ha un messaggio dedicato', () {
    expect(describeError(l, const UnauthorizedException()),
        'Nome utente o password errati.');
    expect(describeError(l, const ForbiddenException()),
        'Account disabilitato o accesso non consentito.');
    expect(describeError(l, const ServerUnreachableException()),
        startsWith('WonderFlix non è raggiungibile'));
    expect(describeError(l, const ServerErrorException(500)),
        'Qualcosa è andato storto. Riprova.');
    expect(describeError(l, StateError('x')),
        'Qualcosa è andato storto. Riprova.');
  });

  test('errori della riproduzione', () {
    expect(describeError(l, const PlaybackUnavailableException('NotAllowed')),
        'Questo contenuto non si può riprodurre.');
    expect(describeError(l, const EngineOpenException('x')),
        'Il video non si è avviato.');
  });

  test('Seerr giù o non configurato', () {
    expect(describeError(l, const RequestsException(RequestsFailure.seerrUnavailable)),
        'Seerr non risponde');
    expect(describeError(l, const RequestsException(RequestsFailure.notConfigured)),
        'Seerr non risponde');
    expect(describeError(l, const RequestsException(RequestsFailure.network)),
        l.errorGeneric);
  });

  test('un profilo in più del massimo', () {
    expect(describeError(l, const ProfileLimitException()), 'Massimo 5 profili');
  });
}
