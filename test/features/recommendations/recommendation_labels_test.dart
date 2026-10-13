import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/recommendation_models.dart';
import 'package:wonderflix/features/recommendations/recommendation_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

RecommendationSender _s(String name, [String? message]) => RecommendationSender(
    userId: name, name: name, message: message, createdAt: DateTime.utc(2026, 10, 12));

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('chi ha consigliato', () {
    expect(recommendedFrom(l, [_s('Luca')]), 'Da Luca');
    expect(recommendedFrom(l, [_s('Luca'), _s('Marta')]), 'Da Luca e Marta');
    expect(recommendedFrom(l, [_s('Luca'), _s('Marta'), _s('Peach')]), 'Da Luca e altri 2');
    expect(recommendedFrom(l, const []), '');
  });

  test('le note: solo chi ha scritto, al massimo 3', () {
    expect(
        recommendationNotes(l, [
          _s('Luca', 'da vedere'),
          _s('Marta'),
          _s('Peach', 'a'),
          _s('Toad', 'b'),
          _s('Yoshi', 'c'),
        ]),
        ['Luca: «da vedere»', 'Peach: «a»', 'Toad: «b»']);
  });
}
