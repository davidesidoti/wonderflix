import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/error_text.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
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
}
