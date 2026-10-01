import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../watch_party/party_notices.dart';

/// Riscontro di un tasto nella pillola del player (spec D §9.2).
@immutable
sealed class PlayerFeedback {
  const PlayerFeedback();
}

/// Spazio: [playing] è lo stato dopo il tasto.
final class PlayFeedback extends PlayerFeedback {
  const PlayFeedback({required this.playing});

  final bool playing;
}

/// ←/→: [offset] è la somma dei salti di fila, [target] la posizione di
/// arrivo.
final class SeekFeedback extends PlayerFeedback {
  const SeekFeedback({required this.offset, required this.target});

  final Duration offset;
  final Duration target;
}

/// ↑/↓ e M: volume (0–100) e muto dopo il tasto.
final class VolumeFeedback extends PlayerFeedback {
  const VolumeFeedback({required this.volume, required this.muted});

  final double volume;
  final bool muted;
}

/// G/H: ritardo dei sottotitoli dopo il tasto.
final class SubtitleDelayFeedback extends PlayerFeedback {
  const SubtitleDelayFeedback(this.delay);

  final Duration delay;
}

/// Stato dell'interfaccia del player (spec D §5.1): controlli, pannello e
/// riscontro dei tasti. Lo stato della riproduzione resta nel
/// `PlayerController`. Lo crea e lo distrugge `PlayerScreen`.
class PlayerChromeController extends ChangeNotifier {
  /// Mouse fermo per questo tempo, in riproduzione: i controlli spariscono.
  static const hideDelay = Duration(seconds: 3);

  /// Quanto resta la pillola dopo l'ultimo tasto.
  static const feedbackDuration = Duration(milliseconds: 1200);

  /// Salti nella stessa direzione entro questo tempo: si sommano.
  static const seekSumWindow = Duration(seconds: 1);

  /// Nel watch party l'avviso "Hai…" di un'azione arriva fino a 400 ms dopo
  /// il tasto (`GroupAuthority.seekDebounce`): entro questo tempo è la
  /// stessa azione, già mostrata dalla pillola del tasto.
  static const keyActionWindow = Duration(seconds: 1);

  bool _controlsVisible = true;
  bool _panelOpen = false;
  bool _playing = false;
  PlayerFeedback? _feedback;

  /// Ultimo riscontro e quando è arrivato: restano anche dopo che la
  /// pillola è sparita (somma dei salti, [isRecentKeyAction]).
  PlayerFeedback? _lastFeedback;
  DateTime? _lastFeedbackAt;
  Timer? _hideTimer;
  Timer? _feedbackTimer;

  bool get controlsVisible => _controlsVisible;

  bool get panelOpen => _panelOpen;

  /// Riscontro da mostrare adesso; `null` = nessuno.
  PlayerFeedback? get feedback => _feedback;

  /// Il mouse si è mosso: controlli visibili, e il conto per nasconderli
  /// riparte.
  void pointerActivity() {
    if (!_controlsVisible) {
      _controlsVisible = true;
      notifyListeners();
    }
    _scheduleHide();
  }

  /// Riproduzione o pausa. In pausa i controlli restano dove sono.
  void setPlaying(bool playing) {
    _playing = playing;
    _scheduleHide();
  }

  /// Apre o chiude il pannello "Audio e sottotitoli": i controlli si vedono
  /// e, a pannello aperto, restano.
  void togglePanel() {
    _panelOpen = !_panelOpen;
    _controlsVisible = true;
    notifyListeners();
    _scheduleHide();
  }

  void closePanel() {
    if (!_panelOpen) return;
    _panelOpen = false;
    notifyListeners();
    _scheduleHide();
  }

  /// Mostra [feedback] per [feedbackDuration]. I controlli non compaiono.
  void showFeedback(PlayerFeedback feedback) {
    _feedback = feedback;
    _lastFeedback = feedback;
    _lastFeedbackAt = clock.now();
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(feedbackDuration, () {
      _feedback = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Salto di [step] da [from]. Se continua una serie nella stessa
  /// direzione (entro [seekSumWindow]) somma l'offset e parte dall'arrivo
  /// precedente. L'arrivo resta tra 0 e [duration] (se nota).
  void seek(Duration step,
      {required Duration from, required Duration duration}) {
    final previous = _lastFeedback;
    final at = _lastFeedbackAt;
    SeekFeedback? series;
    if (previous is SeekFeedback &&
        at != null &&
        clock.now().difference(at) <= seekSumWindow &&
        previous.offset.isNegative == step.isNegative) {
      series = previous;
    }
    final offset = (series?.offset ?? Duration.zero) + step;
    var target = (series?.target ?? from) + step;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    showFeedback(SeekFeedback(offset: offset, target: target));
  }

  /// `true` se l'ultimo tasto (entro [keyActionWindow]) ha fatto la stessa
  /// azione di gruppo [kind]: pausa, ripresa o salto.
  bool isRecentKeyAction(PartyNoticeKind kind) {
    final last = _lastFeedback;
    final at = _lastFeedbackAt;
    if (last == null || at == null) return false;
    if (clock.now().difference(at) > keyActionWindow) return false;
    return switch (kind) {
      PartyNoticeKind.paused => last is PlayFeedback && !last.playing,
      PartyNoticeKind.resumed => last is PlayFeedback && last.playing,
      PartyNoticeKind.seeked => last is SeekFeedback,
      _ => false,
    };
  }

  /// I controlli si nascondono solo in riproduzione e a pannello chiuso.
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_playing || _panelOpen || !_controlsVisible) return;
    _hideTimer = Timer(hideDelay, () {
      _controlsVisible = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    super.dispose();
  }
}
