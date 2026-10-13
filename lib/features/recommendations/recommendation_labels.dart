import '../../core/social/recommendation_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Messaggi al massimo nell'anteprima di una card (spec N §7.4).
const recommendationNotesMax = 3;

/// "Da Luca", "Da Luca e Marta", "Da Luca e altri 2": i mittenti sono già dal
/// più recente (spec N §7.3).
String recommendedFrom(AppLocalizations l, List<RecommendationSender> from) =>
    switch (from) {
      [] => '',
      [final one] => l.recommendedFromOne(one.name),
      [final first, final second] => l.recommendedFromTwo(first.name, second.name),
      [final first, ...final others] => l.recommendedFromMany(first.name, others.length),
    };

/// I messaggi per l'anteprima: "Luca: «da vedere»"; chi non ha scritto non
/// compare.
List<String> recommendationNotes(
        AppLocalizations l, List<RecommendationSender> from) =>
    [
      for (final sender in from)
        if (sender.message case final message?)
          l.recommendationQuote(sender.name, message),
    ].take(recommendationNotesMax).toList();
