import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';
import '../watch_party/party_notice_pill.dart';
import '../watch_party/party_notices.dart';
import 'player_chrome.dart';
import 'tracks_panel.dart';

/// "+20 s", "-10 s".
String formatSeekOffset(Duration offset) =>
    '${offset.isNegative ? '-' : '+'}${offset.inSeconds.abs()} s';

/// Testo del riscontro di un tasto (spec D §9.2).
String playerFeedbackText(AppLocalizations l, PlayerFeedback feedback) =>
    switch (feedback) {
      PlayFeedback(playing: true) => l.playerFeedbackPlaying,
      PlayFeedback(playing: false) => l.playerFeedbackPaused,
      SeekFeedback(:final offset, :final target) =>
        l.playerFeedbackSeek(formatSeekOffset(offset), formatClock(target)),
      VolumeFeedback(muted: true) => l.playerFeedbackMuted,
      VolumeFeedback(:final volume) => l.playerFeedbackVolume(volume.round()),
      SubtitleDelayFeedback(:final delay) => l.playerFeedbackSubtitles(
          formatSubtitleDelay(delay, l.decimalSeparator)),
    };

/// Icona oro del riscontro di un tasto.
IconData playerFeedbackIcon(PlayerFeedback feedback) => switch (feedback) {
      PlayFeedback(:final playing) =>
        playing ? LucideIcons.play : LucideIcons.pause,
      SeekFeedback(:final offset) =>
        offset.isNegative ? LucideIcons.rewind : LucideIcons.fastForward,
      VolumeFeedback(:final volume, :final muted) =>
        muted || volume == 0 ? LucideIcons.volumeX : LucideIcons.volume2,
      SubtitleDelayFeedback() => LucideIcons.captions,
    };

/// Pillola in alto al centro del player (spec D §9.3): il riscontro dei
/// tasti o, senza, l'avviso corrente del watch party. Cambiando contenuto non
/// sparisce: testo e icona sfumano e la larghezza si adatta.
class PlayerPill extends StatefulWidget {
  const PlayerPill({super.key, this.feedback, this.notice});

  final PlayerFeedback? feedback;
  final PartyNotice? notice;

  /// Di quanto sta più in alto a pillola nascosta.
  static const hiddenShift = 12.0;

  /// Larghezza massima della pillola: un avviso più lungo (il titolo di un
  /// episodio) resta su una riga e finisce con i puntini, invece di uscire
  /// dallo schermo.
  static const maxWidth = 560.0;

  @override
  State<PlayerPill> createState() => _PlayerPillState();
}

/// [kind] decide quando il contenuto sfuma: finché non cambia (un tasto
/// tenuto premuto, che cambia il testo ogni ~33 ms) la riga si aggiorna sul
/// posto; cambiandolo, la vecchia sfuma e la nuova entra.
typedef _PillContent = ({IconData icon, String text, Object kind});

class _PlayerPillState extends State<PlayerPill> {
  /// Ultimo contenuto mostrato: resta mentre la pillola sfuma via.
  _PillContent? _last;
  bool _visible = false;

  _PillContent? _content(AppLocalizations l) {
    final feedback = widget.feedback;
    if (feedback != null) {
      return (
        icon: playerFeedbackIcon(feedback),
        text: playerFeedbackText(l, feedback),
        kind: switch (feedback) {
          PlayFeedback(:final playing) => (PlayFeedback, playing),
          SeekFeedback(:final offset) => (SeekFeedback, offset.isNegative),
          VolumeFeedback() => VolumeFeedback,
          SubtitleDelayFeedback() => SubtitleDelayFeedback,
        },
      );
    }
    final notice = widget.notice;
    if (notice != null) {
      return (
        icon: partyNoticeIcon(notice.kind),
        text: partyNoticeText(l, notice),
        // `PartyNotice` non ha `==`: ogni avviso nuovo sfuma.
        kind: notice,
      );
    }
    return null;
  }

  void _onFaded() {
    if (!_visible && mounted) setState(() => _last = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final content = _content(l);
    _visible = content != null;
    if (content != null) _last = content;
    final shown = _last;
    final duration =
        _visible ? motion.duration(WfMotion.medium) : WfMotion.fast;
    final curve = _visible ? WfMotion.emphasized : WfMotion.accelerate;
    final shift =
        _visible || motion.isReduced ? 0.0 : -PlayerPill.hiddenShift;
    return AnimatedOpacity(
      key: const Key('player-pill'),
      opacity: _visible ? 1 : 0,
      duration: duration,
      curve: curve,
      onEnd: _onFaded,
      child: AnimatedContainer(
        duration: duration,
        curve: curve,
        transform: Matrix4.translationValues(0, shift, 0),
        child: shown == null ? const SizedBox.shrink() : _frame(shown, motion),
      ),
    );
  }

  Widget _frame(_PillContent content, WfMotion motion) {
    final row = AnimatedSwitcher(
      duration: WfMotion.fast,
      child: Row(
        key: ValueKey(content.kind),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(content.icon, size: 18, color: WfColors.gold),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              content.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: WfColors.cream),
            ),
          ),
        ],
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: PlayerPill.maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: WfColors.surfaceHigh.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: WfColors.border),
        ),
        // Ridotto: niente movimento, solo sfumature (spec §6.2): la larghezza
        // cambia di colpo. Niente `AnimatedSize` con durata zero: il suo
        // render object rimanda il layout a se stesso e l'assert scatta.
        child: motion.isReduced
            ? row
            : AnimatedSize(
                duration: WfMotion.medium,
                curve: WfMotion.emphasized,
                child: row,
              ),
      ),
    );
  }
}
