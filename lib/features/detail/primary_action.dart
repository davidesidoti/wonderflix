import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';

/// Azione del pulsante principale di una scheda.
sealed class PrimaryAction {
  const PrimaryAction(this.target);

  /// Elemento da riprodurre (per le serie: l'episodio).
  final JellyfinItem target;
}

final class PlayAction extends PrimaryAction {
  const PlayAction(super.target);
}

final class ResumeAction extends PrimaryAction {
  const ResumeAction(super.target, this.position);

  final Duration position;
}

PrimaryAction primaryActionFor(JellyfinItem target, UserItemData userData) =>
    userData.playbackPositionTicks > 0 && !userData.played
        ? ResumeAction(target, userData.playbackPosition)
        : PlayAction(target);

String primaryActionLabel(AppLocalizations l, PrimaryAction action) {
  final code = episodeCode(action.target);
  return switch (action) {
    ResumeAction(:final position) when code != null =>
      '${l.actionResumeEpisode(code)} · ${formatClock(position)}',
    ResumeAction(:final position) => l.actionResumeAt(formatClock(position)),
    PlayAction() when code != null => l.actionPlayEpisode(code),
    PlayAction() => l.actionPlay,
  };
}
