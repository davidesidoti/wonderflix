import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/match_api.dart';
import 'package:wonderflix/features/match/match_actions.dart';
import 'package:wonderflix/l10n/gen/app_localizations_it.dart';

void main() {
  test('i motivi diventano testi', () {
    final l = AppLocalizationsIt();
    expect(matchFailureText(l, MatchFailure.started), 'Il match è già iniziato');
    expect(matchFailureText(l, MatchFailure.closed), 'Sala chiusa');
    expect(matchFailureText(l, MatchFailure.notInvited), 'Sala chiusa');
    expect(matchFailureText(l, MatchFailure.notMember), 'Sala chiusa');
    expect(matchFailureText(l, MatchFailure.full), 'Sala piena');
    expect(matchFailureText(l, MatchFailure.inAnotherRoom),
        'Sei già in un\'altra sala');
    expect(matchFailureText(l, MatchFailure.network), 'Non riuscito, riprova');
  });
}
